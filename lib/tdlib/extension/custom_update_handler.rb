module TD
  module Extension
    module CustomUpdateHandler
      def initialize(params)
        @media_buffer = {}
        @media_mutex = Mutex.new

        super
      end

      def subscribe_channel_posts(client)
        client.on(TD::Types::Update) do |update|
          handler = handlers[update.class]
          if handler
            handler.call(update)
          else
            puts "Unhandled update type: #{update.class} — #{update.inspect}"
          end
        end
      end

      def handlers
        {
          TD::Types::Update::ChatReadInbox => method(:new_message),
          TD::Types::Update::DeleteMessages => method(:message_deletion),
          TD::Types::Update::MessageEdited => method(:message_editing)
        }
      end

      def message_deletion(update)
        return unless update.is_a?(TD::Types::Update::DeleteMessages)

        chat_id = update.chat_id
        message_ids = update.message_ids

        puts "Messages deleted in chat #{chat_id}: #{message_ids.join(', ')}"
      end

      # <TD::Types::Update::MessageEdited chat_id=-1003081251595 message_id=112197632 edit_date=1763670155
      # reply_markup=nil>
      def message_editing(update)
        chat_id = update.chat_id
        message_ids = update.message_ids

        puts "Messages deleted in chat #{chat_id}: #{message_ids.join(', ')}"
      end

      def new_message(update)
        return unless update.is_a?(TD::Types::Update::ChatReadInbox)

        chat_id = update.chat_id
        unread_count = update.unread_count

        return if unread_count <= 0

        messages = channel_messages(chat_id, 0, unread_count)

        return if messages.empty?

        newest_id = HashHelper.get_unknown_structure_data(messages.first, 'id')
        read_messages(chat_id, [newest_id])

        messages.each do |msg|
          group_id = HashHelper.get_unknown_structure_data(msg, 'media_album_id').to_i

          if group_id > 0
            enqueue_media_group(group_id, msg)
          else
            message_sending([msg])
          end
        end

      end

      def enqueue_media_group(group_id, msg)
        @media_mutex.synchronize do
          @media_buffer[group_id] ||= { messages: [], timer: nil }

          # Додаємо повідомлення (захист від дублікатів)
          unless @media_buffer[group_id][:messages].any? { |m| HashHelper.get_unknown_structure_data(m, 'id') == HashHelper.get_unknown_structure_data(msg, 'id') }
            @media_buffer[group_id][:messages] << msg
          end

          # Перезапускаємо таймер очікування решти частин (напр. 600 мс)
          @media_buffer[group_id][:timer]&.kill
          @media_buffer[group_id][:timer] = Thread.new do
            sleep 1
            flush_media_group(group_id)
          end
        end
      end

      def flush_media_group(group_id)
        data = nil
        @media_mutex.synchronize do
          data = @media_buffer.delete(group_id)
        end

        if data && data[:messages].any?
          message_sending(data[:messages])
        end
      end

      def message_sending(messages)
        processed = messages.reverse.map { |msg| HashHelper.get_unknown_structure_data(msg, 'id') }
        forward_messages_to_bot('@DNA_DEV_MINIONBot', -1_003_081_251_595, processed)
      end
    end
  end

  # Unhandled update type: TD::Types::Update::SupergroupFullInfo — #<TD::Types::Update::SupergroupFullInfo
  # supergroup_id=3081251595 supergroup_full_info=#<TD::Types::SupergroupFullInfo photo=nil description=""
  # member_count=6 administrator_count=0 restricted_count=0 banned_count=0 linked_chat_id=-1002164780787
  # slow_mode_delay=0 slow_mode_delay_expires_in=0.0 can_enable_paid_reaction=true can_get_members=false
  # has_hidden_members=true can_hide_members=false can_set_sticker_set=false can_set_location=false
  # can_get_statistics=false can_get_revenue_statistics=false can_get_star_revenue_statistics=false
  # can_toggle_aggressive_anti_spam=false is_all_history_available=true can_have_sponsored_messages=true
  # has_aggressive_anti_spam_enabled=false has_paid_media_allowed=true has_pinned_stories=false my_boost_count=0
  # unrestrict_boost_count=0 sticker_set_id=0 custom_emoji_sticker_set_id=0 location=nil invite_link=nil bot_commands=[]
  # upgraded_from_basic_group_id=0 upgraded_from_max_message_id=0>>
  #
  # Unhandled update type: TD::Types::Update::MessageInteractionInfo — #<TD::Types::Update::MessageInteractionInfo
  # chat_id=-1003081251595 message_id=116391936 interaction_info=#<TD::Types::MessageInteractionInfo view_count=2
  # forward_count=0 reply_info=#<TD::Types::MessageReplyInfo reply_count=0 recent_replier_ids=[]
  # last_read_inbox_message_id=0 last_read_outbox_message_id=0 last_message_id=0> reactions=nil>>
end
