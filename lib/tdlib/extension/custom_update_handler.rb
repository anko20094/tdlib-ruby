module TD
  module Extension
    module CustomUpdateHandler
      MAX_DELIVERED_ALBUMS = 256

      def initialize(params)
        @media_buffer = {}
        @delivered_albums = {}
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

          if group_id.zero?
            message_sending([msg])
          else
            deliver_media_group(chat_id, group_id, msg)
          end
        end
      end

      # Primary album path (DNA-1124): a Telegram album is atomic on the server, so one
      # anchored fetch returns every part at once instead of waiting out the debounce
      # window. The debounce buffer below remains as the fallback when the fetch fails.
      def deliver_media_group(chat_id, group_id, msg)
        key = [chat_id, group_id]
        msg_id = HashHelper.get_unknown_structure_data(msg, 'id')
        return if album_part_delivered?(key, msg_id)

        batch = get_media_group(chat_id, msg)
        fresh = record_delivered_parts(key, batch)

        # A part absent from an earlier fetched batch must still go out on its own —
        # downstream self-healing (tail merge) depends on receiving it.
        message_sending(fresh) if fresh.any?
      rescue StandardError => e
        warn("get_media_group failed for chat #{chat_id} album #{group_id} " \
             "(#{e.class}: #{e.message}); falling back to debounce buffering")
        enqueue_media_group(chat_id, group_id, msg)
      end

      def album_part_delivered?(key, msg_id)
        @media_mutex.synchronize { @delivered_albums[key]&.include?(msg_id) || false }
      end

      def record_delivered_parts(key, batch)
        @media_mutex.synchronize do
          delivered = (@delivered_albums[key] ||= [])
          fresh = batch.reject { |part| delivered.include?(HashHelper.get_unknown_structure_data(part, 'id')) }
          delivered.concat(fresh.map { |part| HashHelper.get_unknown_structure_data(part, 'id') })

          # plain FIFO cap — albums are short-lived, no need for true LRU recency
          @delivered_albums.shift while @delivered_albums.size > MAX_DELIVERED_ALBUMS

          fresh
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
