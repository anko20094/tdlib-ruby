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
        return unless update.is_a?(TD::Types::Update::MessageEdited)

        puts "Message edited in chat #{update.chat_id}: #{update.message_id}"
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
            enqueue_media_group(chat_id, group_id, msg)
          else
            message_sending([msg])
          end
        end
      end

      # Buffer is keyed by [chat_id, media_album_id]: media_album_id alone is not globally unique,
      # so albums from different sources handled by the same client must not collide.
      def enqueue_media_group(chat_id, group_id, msg)
        key = [chat_id, group_id]

        @media_mutex.synchronize do
          @media_buffer[key] ||= { messages: [], timer: nil, deadline: monotonic_time + media_group_max_hold }

          new_msg_id = HashHelper.get_unknown_structure_data(msg, 'id')
          existing_ids = @media_buffer[key][:messages].map do |message|
            HashHelper.get_unknown_structure_data(message, 'id')
          end

          @media_buffer[key][:messages] << msg unless existing_ids.include?(new_msg_id)

          # Debounce: every new part resets the timer, but never beyond the hard deadline —
          # an endless stream of parts cannot hold the batch in the buffer forever.
          delay = [media_group_debounce, @media_buffer[key][:deadline] - monotonic_time].min
          @media_buffer[key][:timer]&.kill
          @media_buffer[key][:timer] = Thread.new do
            sleep delay if delay.positive?
            flush_media_group(key)
          end
        end
      end

      def flush_media_group(key)
        data = nil
        @media_mutex.synchronize do
          data = @media_buffer.delete(key)
        end

        if data && data[:messages].any?
          message_sending(data[:messages])
        end
      end

      def media_group_debounce
        TD.config.media_group_debounce
      end

      def media_group_max_hold
        TD.config.media_group_max_hold
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Abstract hook: override in your TelegramClient subclass. Receives a flat Array of
      # normalized (string-keyed, '@type'-carrying) message hashes; album parts arrive
      # together after the debounce window, nesting them into groups is the consumer's job.
      def message_sending(messages)
        raise NotImplementedError, "#{self.class} must implement #message_sending(messages)"
      end
    end
  end
end
