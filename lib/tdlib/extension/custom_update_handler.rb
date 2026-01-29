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
            # May be needed later for updates investigation
            # puts "Unhandled update type: #{update.class} — #{update.inspect}"
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

      def message_editing(update)
        chat_id = update.chat_id
        message_ids = update.message_ids

        puts "Messages edited in chat #{chat_id}: #{message_ids.join(', ')}"
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

          new_msg_id = HashHelper.get_unknown_structure_data(msg, 'id')
          existing_ids = @media_buffer[group_id][:messages].map do |message|
            HashHelper.get_unknown_structure_data(message, 'id')
          end

          @media_buffer[group_id][:messages] << msg if existing_ids.exclude?(new_msg_id)

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
end
