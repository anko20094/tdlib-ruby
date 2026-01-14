require_relative 'hash_helper'
module TD
  module Extension
    module ApiMethods
      def subscribe_to_link(raw_link)
        return unless logged_in?

        link = raw_link.to_s.strip

        subscribe_by_message_link(link) || subscribe_by_username_link(link) || subscribe_by_invite_link(link)
      end

      def chat_ids(limit = 1000)
        return [] unless logged_in?

        res =  @client.get_chats(chat_list: { '@type' => 'chatListMain' }, limit:).value!(15)
        HashHelper.get_unknown_structure_data(res, 'chat_ids')
      rescue ArgumentError, TypeError => e
        puts "❌ Error forwarding messages: #{e.class} - #{e.message}"

        nil
      end

      def channel_messages(chat_id, from_message_id = 0, limit = 99, offset = 0)
        return [] unless logged_in?

        res = @client.get_chat_history(chat_id:, from_message_id:, limit:, offset:, only_local: false).value!(15)

        HashHelper.get_unknown_structure_data(res, 'messages') || []
      end

      def read_messages(chat_id, message_ids)
        @client.open_chat(chat_id:).value! # should check if this is needed
        @client.view_messages(chat_id:, message_ids:, force_read: true, source: nil).value!
      end

      def start_chat_with_bot(bot)
        return unless logged_in?

        chat_id = resolve_chat_id(bot)
        return if chat_id.blank?

        input = {
          '@type' => 'inputMessageText',
          'text' => { '@type' => 'formattedText', 'text' => '/start' },
          'disable_web_page_preview' => true
        }
        options = {
          '@type' => 'messageSendOptions',
          'disable_notification' => false,
          'from_background' => false,
          'protect_content' => false
        }

        @client.send_message(
          chat_id:,
          message_thread_id: 0,
          reply_to: nil,
          options:,
          reply_markup: nil,
          input_message_content: input
        ).value!(15)
      rescue ArgumentError, TypeError => e
        puts "❌ Error forwarding messages: #{e.class} - #{e.message}"

        nil
      end

      def forward_messages_to_bot(bot, from_chat_id, message_ids)
        return unless logged_in?

        bot_chat_id = resolve_chat_id(bot)
        return if bot_chat_id.nil?

        options = {
          '@type' => 'messageSendOptions',
          'disable_notification' => false,
          'from_background' => false,
          'protect_content' => false
        }

        @client.forward_messages(
          chat_id: bot_chat_id,
          from_chat_id:,
          message_ids:,
          message_thread_id: 0,
          options:,
          send_copy: false,
          remove_caption: false
        ).value!(20)
      rescue ArgumentError, TypeError => e
        puts "❌ Error forwarding messages: #{e.class} - #{e.message}"

        nil
      end

      def group_media_groups(messages)
        return [] unless messages.is_a?(Array)

        album_map = {}
        seen = {}
        result = []

        messages.each do |m|
          album_id = (m['media_album_id'] || m.dig('media', 'album_id')).to_s
          if album_id && !album_id.empty? && album_id != '0'
            album_map[album_id] ||= []
            unless seen[album_id]
              result << album_map[album_id]
              seen[album_id] = true
            end
            album_map[album_id] << m
          else
            result << m
          end
        end

        sort_by_id(result)
      end

      def fetch_interaction_info(message)
        HashHelper.get_unknown_structure_data(message, 'interaction_info')
      end

      # Щоб отримати коментарі до поста, ми використовуємо його ID як message_thread_id.
      # TDLib сам знає, куди йти (в linked chat) за коментарями.

      def fetch_post_comments(chat_id, message_id, limit = 100)
        return [] unless logged_in?

        puts "📡 Завантажуємо коментарі для поста #{message_id}..."

        # lib has error on this method
        res = @client.get_message_thread_history(
          chat_id:,
          message_id: message_id,
          from_message_id: 0,
          offset: 0,
          limit:
        ).value!(15)

        messages = HashHelper.get_unknown_structure_data(res, 'messages') || []

        # Фільтруємо, щоб прибрати сам пост, якщо він раптом потрапив у видачу (хоча зазвичай ні)
        comments = messages.reject { |m| HashHelper.get_unknown_structure_data(m, 'id') == message_id }

        puts "✅ Знайдено коментарів: #{comments.count}"
        comments
      rescue TD::Error => e
        puts "❌ TDLib Error: #{e.message}"
        []
      end

      def sort_by_id(messages)
        messages.map do |entry|
          if entry.is_a?(Array)
            entry.sort_by { |msg| (msg['id'] || msg['message_id'] || msg.dig('message', 'id') || 0).to_i }
          else
            entry
          end
        end
      end

      private

      def resolve_chat_id(target)
        return unless logged_in?
        return target.to_i if target.is_a?(Integer) || target.to_s =~ /\A-?\d+\z/

        username = target.to_s.strip.sub(/\A@/, '')
        res = @client.search_public_chat(username:).value!(10)

        HashHelper.get_unknown_structure_data(res, 'id')
      end

      def get_chat(chat_id)
        return {} unless logged_in?

        @client.get_chat(chat_id:).value!(15)
      end

      def get_chat_full_info(chat_id)
        return 0 unless logged_in?

        chat = @client.get_chat(chat_id: chat_id).value!

        case HashHelper.get_unknown_structure_data(chat, 'type')
        when TD::Types::ChatType::Supergroup
          supergroup_id = HashHelper.get_unknown_structure_data(chat, 'type').supergroup_id
          full_info = @client.get_supergroup_full_info(supergroup_id: supergroup_id).value!

          puts "📊 Аудиторія каналу: #{full_info.member_count}"
          full_info
        when TD::Types::ChatType::BasicGroup
          basic_group_id = chat.type.basic_group_id
          @client.get_basic_group_full_info(basic_group_id: basic_group_id).value!

        else
          2
        end
      end

      def get_message(chat_id, message_id)
        return {} unless logged_in?

        @client.get_message(chat_id:, message_id:).value!(15)
      end

      def subscribe_by_message_link(link)
        if (m = link.match(%r{t\.me/c/(\d+)/\d+}))
          short_id = m[1].to_i
          chat_id = -100_000_000_000 + short_id

          @client.join_chat(chat_id:).value!(20)
        end
      end

      def subscribe_by_username_link(link)
        m = link.match(%r{(?:tg://resolve\?domain=|https?://(?:www\.)?(?:t\.me|telegram\.me)/)@?([A-Za-z0-9_]{5,32})})
        if m.present?
          username = m[1]
          chat = @client.search_public_chat(username:).value!(15)
          id = HashHelper.get_unknown_structure_data(chat, 'id')
          return if chat.blank? || id.blank?

          @client.join_chat(chat_id: id).value!(20)
        end
        nil
      end

      def subscribe_by_invite_link(link)
        if (m = link.match(%r{(?:t\.me/joinchat/|t\.me/\+|tg://join\?invite=)([A-Za-z0-9_-]+)}))
          invite_code = m[1]
          invite_link = link.include?('http') ? link : "https://t.me/joinchat/#{invite_code}"
          info = @client.check_chat_invite_link(invite_link:).value!(15)

          return if !info.is_a?(Hash) && info.blank?

          @client.join_chat_by_invite_link(invite_link:).value!(20)
        end
      end

      def logged_in?
        unless @auth_ready
          puts '   ⚠️  [API] Помилка: Клієнт не авторизований. API-запит скасовано.'
          return false
        end
        true
      end

      def sort_by_id(messages)
        messages.map do |entry|
          if entry.is_a?(Array)
            entry.sort_by { |msg| (msg['id'] || msg['message_id'] || msg.dig('message', 'id') || 0).to_i }
          else
            entry
          end
        end
      end
    end
  end
end
