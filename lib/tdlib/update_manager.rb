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

      unless update.nil?
        extra  = update.delete('@extra')
        update = TD::Types.wrap(update)
        callback&.call(update)

        match_handlers!(update, extra).each { |h| h.async.run(update) }
      end
    rescue StandardError => e
      log_unwrappable_update(e, extra)
      force_feed_raw_hash(update, extra)
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
      return if extra.nil? # Не можемо врятувати, якщо немає 'extra' ID

      # Знаходимо слухачів ТІЛЬКИ за 'extra', ігноруючи їх 'update_type'
      @mutex.synchronize do
        matched_handlers = handlers.select { |h| h.extra == extra }

        matched_handlers.each do |handler|
          # Примусово "годуємо" слухача сирим хешем
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
