module TD
  class UpdateManager
    TIMEOUT = 30

    def initialize(td_client)
      @td_client = td_client
      @handlers = Concurrent::Array.new
      @mutex = Mutex.new
    end

    def add_handler(handler)
      @mutex.synchronize { @handlers << handler }
    end

    alias << add_handler

    def run(callback: nil)
      Thread.start do
        catch(:client_closed) do
          loop do
            handle_update(callback: callback)
            sleep 0.001
          end
        end
        @mutex.synchronize { @handlers = [] }
      end
    end

    private

    attr_reader :handlers

    def handle_update(callback: nil)
      update = TD::Api.client_receive(@td_client, TIMEOUT)
      return if update.nil?

      extra = update.delete('@extra')

      # Only the wrap itself may fall back to raw-hash delivery; a callback/dispatch
      # failure would otherwise masquerade as an "unwrappable update" and force-feed
      # an already-wrapped struct to the @extra-correlated waiter.
      begin
        update = TD::Types.wrap(update)
      rescue StandardError => e
        log_unwrappable_update(e, extra)
        force_feed_raw_hash(update, extra)
        return
      end

      callback&.call(update)
      match_handlers!(update, extra).each { |h| h.async.run(update) }
    rescue StandardError => e
      warn("Uncaught exception in update manager: #{e.message}")
    end

    # An update TD::Types.wrap can't parse (e.g. a @type missing from tdlib-schema)
    # must never vanish silently — the @type is in the error message.
    def log_unwrappable_update(error, extra)
      message = "TDLib update dropped to raw-hash delivery (extra=#{extra.inspect}): " \
                "#{error.class}: #{error.message}"

      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end
    end

    def force_feed_raw_hash(raw_update, extra)
      return if extra.nil? # nothing to rescue without the '@extra' correlation id

      # Match listeners by '@extra' only: the hash never wrapped, so type matching is impossible.
      @mutex.synchronize do
        matched_handlers = handlers.select { |h| h.extra == extra }

        matched_handlers.each do |handler|
          # Deliver the raw hash as-is; HashHelper-based consumers handle both shapes.
          handler.async.run(raw_update)
          handlers.delete(handler) if handler.disposable?
        end
      end
    end

    def match_handlers!(update, extra)
      @mutex.synchronize do
        matched_handlers = handlers.select { |h| h.match?(update, extra) }
        matched_handlers.each { |h| handlers.delete(h) if h.disposable? }
        matched_handlers
      end
    end
  end
end
