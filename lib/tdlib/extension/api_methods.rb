require_relative 'hash_helper'
module TD
  module Extension
    module ApiMethods
      CHAT_ID_OFFSET = -1_000_000_000_000.freeze
      ALBUM_MAX_PARTS = 10 # Telegram hard limit for one media group
      MEDIA_GROUP_FETCH_ATTEMPTS = 3

      def subscribe_to_link(raw_link)
        return if logged_out?

        link = raw_link.to_s.strip

        subscribe_by_message_link(link) || subscribe_by_username_link(link) ||
          subscribe_by_invite_link(link) || subscribe_by_channel_name(link)
      rescue TD::Error => e
        raise unless e.message&.include?('USER_ALREADY_PARTICIPANT')

        already = resolve_already_subscribed_chat(link)
        already && joined_from(already)
      end

      def resolve_already_subscribed_chat(link)
          chat_id = resolve_chat_id(link)

          if chat_id.nil? && (m = link.match(%r{t\.me/c/(\d+)/\d+}))
            short_id = m[1].to_i
            chat_id = CHAT_ID_OFFSET - short_id
          end

          invite_code = link.match(%r{(?:t\.me/joinchat/|t\.me/\+|tg://join\?invite=)([A-Za-z0-9_-]+)})
          if chat_id.nil? && invite_code
            invite_link = link.include?('http') ? link : "https://t.me/joinchat/#{invite_code[1]}"
            info = @client.check_chat_invite_link(invite_link: invite_link).value!(15)
            chat_id = HashHelper.get_unknown_structure_data(info, 'chat_id') ||
                      HashHelper.get_unknown_structure_data(info, 'id')
          end

          chat_id ? HashHelper.deep_to_hash(get_chat(chat_id)) : nil
      end

      def channel_messages(chat_id, from_message_id = 0, limit = 99, offset = 0)
        return [] if logged_out?

        res = @client.get_chat_history(chat_id:, from_message_id:, limit:, offset:, only_local: false).value!(15)

        messages = HashHelper.get_unknown_structure_data(res, 'messages') || []
        messages.map { |msg| HashHelper.deep_to_hash(msg) }
      end

      # Pull each message into THIS session before it is forwarded. forwardMessages silently returns
      # null for any message the current TDLib session never loaded — e.g. flow content captured by the
      # listener session but forwarded by a separate executor session — which turns resend into a no-op.
      # getMessage fetches from the server (member access is enough), so the later forward resolves.
      def get_messages(chat_id, message_ids)
        return [] if logged_out?

        Array(message_ids).filter_map do |message_id|
          res = @client.get_message(chat_id:, message_id:).value!(15)
          res && HashHelper.deep_to_hash(res)
        rescue TD::Error => e
          puts "⚠️ [API] get_message failed for #{chat_id}/#{message_id}: #{e.message}"
          nil
        end
      end

      # Returns every part of the anchor's media album as normalized hashes sorted by id.
      # A Telegram album is published atomically with adjacent message ids, so one history
      # slice anchored at any known part covers the whole group (DNA-1124).
      def get_media_group(chat_id, anchor_message)
        anchor = HashHelper.deep_to_hash(anchor_message)
        album_id = HashHelper.get_unknown_structure_data(anchor, 'media_album_id').to_s
        return [anchor] if album_id.empty? || album_id == '0'

        anchor_id = HashHelper.get_unknown_structure_data(anchor, 'id')
        parts = { anchor_id => anchor }

        # getChatHistory may return fewer messages than requested (documented TDLib
        # behavior, especially on a cold local database) — refetch while parts keep
        # arriving, stop early once the album is provably complete.
        MEDIA_GROUP_FETCH_ATTEMPTS.times do |attempt|
          slice = album_history_slice(chat_id, anchor_id)
          added = merge_album_parts(parts, slice, album_id)

          break if parts.size >= ALBUM_MAX_PARTS || album_enclosed?(parts, slice)
          break if added.zero? && attempt.positive?
        end

        parts.values.sort_by { |part| part['id'].to_i }
      end

      def read_messages(chat_id, message_ids)
        @client.open_chat(chat_id:).value!
        @client.view_messages(chat_id:, message_ids:, force_read: true, source: nil).value!
      end

      # DNA-1209: an optional deep-link payload ("/start <payload>") lets a non-production userbot
      # self-register with the production mother bot. Production always sends a bare "/start" (the
      # payload is dropped there), so the same call is safe in every environment.
      def start_chat_with_bot(bot, payload = nil)
        return if logged_out?

        chat_id = resolve_chat_id(bot)
        return if chat_id.nil?

        options = {
          '@type' => 'messageSendOptions',
          'disable_notification' => false,
          'from_background' => false,
          'protect_content' => false
        }

        @client.send_message(
          chat_id:,
          topic_id: nil,
          reply_to: nil,
          options:,
          reply_markup: nil,
          input_message_content: start_message_content(payload)
        ).value!(15)
      end

      def forward_messages_to_bot(bot, from_chat_id, message_ids)
        return if logged_out?

        bot_chat_id = resolve_chat_id(bot)
        return if bot_chat_id.nil?

        # Load the source messages into this session first; without it forwardMessages no-ops on
        # cross-session (flow) content and the bot file is never minted (DNA-1173 hop3).
        get_messages(from_chat_id, message_ids)

        options = {
          '@type' => 'messageSendOptions',
          'disable_notification' => false,
          'from_background' => false,
          'protect_content' => false
        }

        result = @client.forward_messages(
          chat_id: bot_chat_id,
          from_chat_id:,
          message_ids:,
          topic_id: nil,
          options:,
          send_copy: false,
          remove_caption: false
        ).value!(20)

        result && HashHelper.deep_to_hash(result)
      end

      def group_media_groups(messages)
        return [] unless messages.is_a?(Array)

        album_map = {}
        seen = {}
        result = []

        messages.each do |m|
          album_id = HashHelper.get_unknown_structure_data(m, 'media_album_id').to_s
          if album_id.empty? || album_id == '0'
            result << m
          else
            album_map[album_id] ||= []
            if seen[album_id].nil?
              result << album_map[album_id]
              seen[album_id] = true
            end
            album_map[album_id] << m
          end
        end

        sort_by_id(result)
      end

      def sort_by_id(messages)
        messages.map do |entry|
          if entry.is_a?(Array)
            entry.sort_by { |msg| HashHelper.get_unknown_structure_data(msg, 'id').to_i }
          else
            entry
          end
        end
      end

      private

      def start_message_content(payload)
        {
          '@type' => 'inputMessageText',
          'text' => { '@type' => 'formattedText', 'text' => start_command(payload) },
          'disable_web_page_preview' => true
        }
      end

      # A deep-link "/start <payload>" only fires outside production (e.g. a dev/staging userbot
      # self-registering with the production mother bot); production always sends a bare "/start".
      def start_command(payload)
        return '/start' if payload.to_s.empty? || production_environment?

        "/start #{payload}"
      end

      def production_environment?
        return Rails.env.production? if defined?(Rails) && Rails.respond_to?(:env)

        ENV['RAILS_ENV'].to_s == 'production' || ENV['RACK_ENV'].to_s == 'production'
      end

      def resolve_chat_id(target)
        return if logged_out?
        return target.to_i if target.is_a?(Integer) || target.to_s =~ /\A-?\d+\z/

        username = target.to_s.strip.sub(/\A@/, '')
        res = @client.search_public_chat(username:).value!(10)

        HashHelper.get_unknown_structure_data(res, 'id')
      rescue TD::Error => e
        # Only "no such username" degrades to nil; transient errors (flood wait,
        # network) must propagate so callers can classify and retry them.
        return if e.message.to_s.match?(/USERNAME_INVALID|USERNAME_NOT_OCCUPIED/)

        raise
      end

      def get_chat(chat_id)
        return {} if logged_out?

        @client.get_chat(chat_id:).value!(15)
      end

      def subscribe_by_message_link(link)
        return unless (m = link.match(%r{t\.me/c/(\d+)/\d+}))

        chat_id = CHAT_ID_OFFSET - m[1].to_i
        join_outcome(@client.join_chat(chat_id:).value!(20), chat_id:)
      end

      def subscribe_by_username_link(link)
        m = link.match(%r{(?:tg://resolve\?domain=|https?://(?:www\.)?(?:t\.me|telegram\.me)/)@?([A-Za-z0-9_]{5,32})})
        return if m.nil?

        chat = @client.search_public_chat(username: m[1]).value!(15)
        id = HashHelper.get_unknown_structure_data(chat, 'id')
        return if id.nil?

        join_outcome(@client.join_chat(chat_id: id).value!(20), chat:)
      end

      def subscribe_by_invite_link(link)
        return unless (m = link.match(%r{(?:t\.me/joinchat/|t\.me/\+|tg://join\?invite=)([A-Za-z0-9_-]+)}))

        invite_link = link.include?('http') ? link : "https://t.me/joinchat/#{m[1]}"
        invite_info = @client.check_chat_invite_link(invite_link:).value!(15)

        join_outcome(@client.join_chat_by_invite_link(invite_link:).value!(20), invite_info:)
      end

      def subscribe_by_channel_name(username)
        clean_username = username.gsub('@', '').strip
        return if clean_username.include?('/') || clean_username.empty?

        chat = search_public_chat_safe(clean_username)
        id = HashHelper.get_unknown_structure_data(chat, 'id')
        return if id.nil?

        join_outcome(@client.join_chat(chat_id: id).value!, chat:)
      end

      # DNA-1235 Phase 0 (valuable already on 1.8.64): only "no such username" degrades to nil; floodwait /
      # transient errors must propagate so MainService#with_operation classifies + retries them (mirrors
      # resolve_chat_id). The old bare `rescue TD::Error → nil` collapsed a floodwait into a dead source.
      def search_public_chat_safe(username)
        @client.search_public_chat(username:).value!
      rescue TD::Error => e
        raise unless e.message.to_s.match?(/USERNAME_INVALID|USERNAME_NOT_OCCUPIED/)

        nil
      end

      # DNA-1235: normalize the 1.8.65 ChatJoinResult union into an outcome-keyed hash the app reads
      # version-agnostically (no TD::Types::ChatJoinResult constant anywhere → no NameError on any schema).
      # nil is reserved for a genuine dead link (no subscribe_by_* matched).
      def join_outcome(join_result, chat: nil, chat_id: nil, invite_info: nil)
        case chat_join_result_variant(join_result)
        when :success then joined_outcome(join_result, chat:, chat_id:)
        when :request_sent then request_sent_outcome(chat:, invite_info:)
        when :guard then guard_outcome(join_result, chat:, invite_info:)
        when :declined then { 'outcome' => 'declined' }
        else legacy_joined(join_result, chat:) # 1.8.64 core (Ok/Chat) or an already-member chat payload
        end
      end

      def chat_join_result_variant(res)
        name = res.class.name.to_s
        return :legacy unless name.include?('ChatJoinResult')

        { 'Success' => :success, 'RequestSent' => :request_sent,
          'GuardBotApprovalRequired' => :guard, 'Declined' => :declined }[name.split('::').last] || :legacy
      end

      def joined_outcome(res, chat: nil, chat_id: nil)
        chat ||= resolve_chat_safe(chat_id || HashHelper.get_unknown_structure_data(res, 'chat_id'))
        joined_from(chat)
      end

      def joined_from(chat)
        h = HashHelper.deep_to_hash(chat)
        { 'outcome' => 'joined', 'id' => h['id'], 'title' => h['title'], 'type' => h['type'] }
      end

      # DNA-1208 mirror: a floodwait/timeout resolving the chat must not discard an already-successful join.
      def resolve_chat_safe(chat_id)
        return {} if chat_id.to_i.zero?

        HashHelper.deep_to_hash(get_chat(chat_id))
      rescue TD::Error
        { 'id' => chat_id }
      end

      def request_sent_outcome(chat: nil, invite_info: nil)
        { 'outcome' => 'request_sent' }.merge(identity_from(chat || invite_info))
      end

      def guard_outcome(res, chat: nil, invite_info: nil)
        { 'outcome' => 'guard_required',
          'bot_user_id' => HashHelper.get_unknown_structure_data(res, 'bot_user_id'),
          'query_id' => HashHelper.get_unknown_structure_data(res, 'query_id') }
          .merge(identity_from(chat || invite_info))
      end

      # check_chat_invite_link returns chat_id 0 for an approval-gated chat you have not joined — treat 0 as
      # unknown so the app does not persist a bogus source_id (DNA-1235).
      def identity_from(source)
        return {} if source.nil?

        h = HashHelper.deep_to_hash(source)
        chat_id = h['id'] || h['chat_id']
        { 'id' => (chat_id.to_i.zero? ? nil : chat_id), 'title' => h['title'] }.compact
      end

      # 1.8.64 core (join_chat → Ok, join_chat_by_invite_link → Chat) or an already-member chat → joined.
      def legacy_joined(res, chat: nil)
        h = HashHelper.deep_to_hash(chat || res)
        return joined_from(h) if h.is_a?(Hash) && !h['id'].nil?

        { 'outcome' => 'joined' }
      end

      # offset -9 / limit 19 reaches up to 9 newer and 9 older neighbours of the anchor:
      # an album holds at most ALBUM_MAX_PARTS messages with adjacent ids.
      def album_history_slice(chat_id, anchor_id)
        res = @client.get_chat_history(chat_id:, from_message_id: anchor_id, offset: -9,
                                       limit: 19, only_local: false).value!(15)
        if res.nil?
          raise TD::Error, TD::Types::Error.new(code: 0, message: 'get_media_group: getChatHistory timed out')
        end

        messages = HashHelper.get_unknown_structure_data(res, 'messages') || []
        messages.map { |msg| HashHelper.deep_to_hash(msg) }
      end

      def merge_album_parts(parts, slice, album_id)
        fresh = slice.select do |msg|
          HashHelper.get_unknown_structure_data(msg, 'media_album_id').to_s == album_id && parts[msg['id']].nil?
        end
        fresh.each { |msg| parts[msg['id']] = msg }
        fresh.size
      end

      # The album is provably complete when the slice contains non-album messages on
      # both sides of the collected parts.
      def album_enclosed?(parts, slice)
        ids = parts.keys.map(&:to_i)
        outsiders = slice.reject { |msg| parts.key?(msg['id']) }

        outsiders.any? { |msg| msg['id'].to_i < ids.min } && outsiders.any? { |msg| msg['id'].to_i > ids.max }
      end

      def logged_out?
        !logged_in?
      end

      def logged_in?
        return true if @auth_ready

        puts '⚠️ [API] Client not logged in yet.'

        false
      end
    end
  end
end
