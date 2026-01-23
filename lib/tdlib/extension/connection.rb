module TD
  module Extension
    module Connection
      AUTH_STATE_MAP = {
        'WaitTdlibParameters' => :wait_tdlib_parameters,
        'WaitPhoneNumber' => :wait_phone_number,
        'WaitCode' => :wait_code,
        'WaitPassword' => :wait_password,
        'Ready' => :ready
      }.freeze

      def setup_handlers
        @client.on(TD::Types::Update::AuthorizationState) do |update|
          state_name = update.authorization_state.class.name.split('::').last
          puts "   🔄 [СТАН] Змінено на: #{state_name}"

          mapped = AUTH_STATE_MAP[state_name]
          if mapped == :ready
            @auth_state = :ready
            @auth_ready = true
          elsif mapped
            @auth_state = mapped
          else
            puts "   ⚠️  Невідомий стан: #{state_name}"
            @auth_state = :unknown
          end
        end
      end

      def process_auth_state(by_qr: false)
        current_state = @auth_state
        @auth_state = nil
        return unless current_state

        case current_state
        when :wait_phone_number
          if by_qr
            handle_qr_login
          else
            handle_phone_number
          end
        when :wait_other_device_confirmation
          puts "⏳ Очікування сканування QR-коду..."
        when :wait_code
          handle_code
        when :wait_password
          handle_password
        when :ready
          puts "✅ Авторизація успішна!"
        else
          puts "⚠️ Неочікуваний auth_state: #{current_state}"
        end
      end

      private

      def handle_qr_login
        puts "\n========================================"
        puts "🚀 Запуск входу через QR-код"
        puts "========================================"
        @client.request_qr_code_authentication(other_user_ids: [])

        sleep 4

        begin
          auth_state = @client.get_authorization_state.value!

          if auth_state.respond_to?(:link)
            link = auth_state.link

            puts "\n🔗 ПОСИЛАННЯ (Дійсне 30 сек):"
            puts link
            puts "\n📸 Скануйте QR нижче:"
            if system("which qrencode > /dev/null 2>&1")
              system("qrencode -t ANSIUTF8 '#{link}'")
            else
              puts "❌ Утиліта 'qrencode' не знайдена. Встановіть її: sudo apt install qrencode"
              puts "Або відкрийте посилання вище в генераторі QR."
            end
          else
            puts "⚠️  Посилання ще не готове. Стан: #{auth_state.class}"
          end
        rescue => e
          puts "❌ Помилка при отриманні QR: #{e.message}"
        end
      end

      def handle_phone_number
        @client.set_authentication_phone_number(phone_number: @phone, settings: nil)
      end

      def handle_code
        print '   📱 [ДІЯ] Введіть код підтвердження: '
        code = $stdin.gets&.strip
        if code.nil? || code.empty?
          puts '   ❌ Код не введено.'
          return
        end
        @client.check_authentication_code(code:)
      end

      def handle_password
        print '   🔐 [ДІЯ] Введіть ваш пароль 2FA: '
        password = $stdin.gets&.strip
        if password.nil? || password.empty?
          puts '   ❌ Пароль не введено.'
          return
        end
        @client.check_authentication_password(password: password)
      end

      def connect
        @client.connect
        puts '   ✅ Connected'
        state_result = @client.get_authorization_state.value!(5) rescue nil

        if state_result.is_a?(TD::Types::AuthorizationState::Ready)
          puts "   ✅ [CLIENT] Стан вже 'Ready'. Вхід не потрібен."
          @auth_state = :ready
          @auth_ready = true
        elsif state_result
          state_name = state_result.class.name.split('::').last
          puts "   ℹ️  [CLIENT] Поточний стан: #{state_name}"
        end

        true
      rescue StandardError
        false
      end

      def setup_directories
        FileUtils.mkdir_p(TD.config.client.database_directory)
        FileUtils.mkdir_p(TD.config.client.files_directory)
      end

      def close
        @client&.close
      rescue StandardError => e
        puts "   ⚠️ Помилка при закритті клієнта: #{e.message}"
      ensure
        puts '   ...очікуємо завершення C++ потоків...'
        sleep 1
        puts '   ...вихід.'
      end
    end
  end
end
