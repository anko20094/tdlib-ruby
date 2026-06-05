module TD
  module Extension
    module Connection
      AUTH_STATE_MAP = {
        'WaitTdlibParameters' => :wait_tdlib_parameters,
        'WaitPhoneNumber' => :wait_phone_number,
        'WaitOtherDeviceConfirmation' => :wait_other_device_confirmation,
        'WaitCode' => :wait_code,
        'WaitPassword' => :wait_password,
        'Ready' => :ready
      }.freeze

      def setup_handlers
        @client.on(TD::Types::Update::AuthorizationState) do |update|
          state_name = update.authorization_state.class.name.split('::').last
          puts "🔄 [State]  Changed to: #{state_name}"

          mapped = AUTH_STATE_MAP[state_name]
          if mapped == :ready
            @auth_state = :ready
            @auth_ready = true
          elsif mapped
            @auth_state = mapped
          else
            puts "⚠️  Unknown state: #{state_name}"
            @auth_state = :unknown
          end

          display_qr_link(update.authorization_state) if mapped == :wait_other_device_confirmation
        end
      end

      def process_auth_state(by_qr: false)
        current_state = @auth_state
        @auth_state = nil
        return unless current_state

        case current_state
        when :wait_phone_number
          by_qr ? handle_qr_login : handle_phone_number
        when :wait_other_device_confirmation
          puts "⏳ Waiting for QR-code scanning..."
        when :wait_code
          handle_code
        when :wait_password
          handle_password
        when :ready
          puts "✅ Successfull auth!"
        else
          puts "⚠️ Unknown auth_state: #{current_state}"
        end
      end

      private

      # A failed QR request must halt the auth flow loudly, not strand it in WaitPhoneNumber.
      # The link itself is printed by the AuthorizationState handler on every token rotation.
      def handle_qr_login
        puts "\n========================================"
        puts '🚀  Qr-code login initiated'
        puts '========================================'
        @client.request_qr_code_authentication(other_user_ids: []).value!
      rescue StandardError => e
        log_auth_error('QR login request failed', e)
        raise
      end

      # Telegram rotates the QR token every ~30 seconds and TDLib pushes each fresh link
      # through updateAuthorizationState; reprint it every time so the link on screen is
      # never a stale token (scanning or clicking an expired one silently does nothing).
      def display_qr_link(auth_state)
        link = auth_state.respond_to?(:link) ? auth_state.link.to_s : ''
        return if link.empty? || link == @last_qr_link

        @last_qr_link = link
        puts "\n🔗 Link:"
        puts link
        print_qr_code(link)
      end

      def print_qr_code(link)
        puts "\n📸 Scan qr code below:"
        if system('which qrencode > /dev/null 2>&1')
          system('qrencode', '-t', 'ANSIUTF8', link)
        else
          puts "❌ Utility 'qrencode' not found. Install it: sudo apt install qrencode"
          puts 'Or open the link above in a QR generator.'
        end
      end

      # A failed code request must halt the auth flow loudly, not strand it in WaitPhoneNumber.
      def handle_phone_number
        @client.set_authentication_phone_number(phone_number: @phone, settings: nil).value!
      rescue StandardError => e
        log_auth_error("Failed to request code for #{@phone}", e)
        raise
      end

      def handle_code
        print_code_info
        print "📱 [ACTION] Enter pass code ('r' to resend): "
        code = $stdin.gets&.strip
        if code.nil? || code.empty?
          puts '❌ Code is blank.'
          @auth_state = :wait_code
          return
        end
        return resend_code if code.casecmp('r').zero?

        @client.check_authentication_code(code:).value!
      rescue StandardError => e
        log_auth_error('Code check failed', e)
        @auth_state = :wait_code
      end

      def print_code_info
        state = @client.get_authorization_state.value!(5)
        return unless state.respond_to?(:code_info)

        info = state.code_info
        puts "ℹ️ Code sent via: #{code_type_name(info.type)}, " \
             "next type: #{info.next_type ? code_type_name(info.next_type) : 'none'}, " \
             "resend timeout: #{info.timeout}s"
      rescue StandardError => e
        puts "⚠️ Failed to fetch code info: #{e.message}"
      end

      def code_type_name(type)
        type.class.name.split('::').last
      end

      def resend_code
        @client.resend_authentication_code(reason: nil).value!
        puts '🔁 Code resent.'
      rescue StandardError => e
        log_auth_error('Resend failed', e)
      ensure
        @auth_state = :wait_code
      end

      # Interactive visibility (stdout) plus a persistent trace (Rails log when available)
      def log_auth_error(prefix, error)
        puts "❌ #{prefix}: #{error.message}"
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.error("[TD auth] #{prefix}: #{error.message}")
      end

      # Awaits the check: a swallowed PASSWORD_HASH_INVALID used to leave the flow
      # spinning with zero feedback. Any failure re-arms :wait_password for a re-prompt.
      def handle_password
        print '🔐 [Action] Enter 2FA password: '
        password = $stdin.gets&.strip
        if password.nil? || password.empty?
          puts '❌ Password is blank.'
          @auth_state = :wait_password
          return
        end
        @client.check_authentication_password(password: password).value!
      rescue StandardError => e
        log_auth_error('Password check failed', e)
        @auth_state = :wait_password
      end

      def connect
        @client.connect
        puts '✅ Connected'
        state_result = @client.get_authorization_state.value!(5) rescue nil

        if state_result.is_a?(TD::Types::AuthorizationState::Ready)
          puts "✅ [CLIENT] State is 'Ready'."
          @auth_state = :ready
          @auth_ready = true
        elsif state_result
          state_name = state_result.class.name.split('::').last
          puts "ℹ️ [CLIENT] Current state: #{state_name}"
        end

        true
      rescue StandardError
        false
      end

      # Pre-create the per-instance dirs actually handed to TD::Client — not the
      # TD.config globals, which per-instance params override anyway.
      def setup_directories
        FileUtils.mkdir_p(@database_directory)
        FileUtils.mkdir_p(@media_directory)
      end

      def close
        @client&.close
      rescue StandardError => e
        puts "⚠️ Error closing client: #{e.message}"
      ensure
        puts '...waiting...'
        sleep 1
        puts '...exit.'
      end
    end
  end
end
