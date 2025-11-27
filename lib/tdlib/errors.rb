module TD
  class MissingLibPathError < StandardError
    def initialize(message = 'Please, configure the path to tdlibjson library')
      super
    end
  end

  # Proxy class that is used in failed promises to represent TDlib errors
  class Error < StandardError
    def initialize(td_error)
      @td_error = td_error
    end

    def method_missing(method, *)
      @td_error.public_send(method, *)
    end

    def respond_to_missing?(*)
      @td_error.respond_to?(*)
    end

    def to_s
      @td_error.inspect
    end

    def message
      @td_error.message
    end

    alias inspect to_s
  end
end
