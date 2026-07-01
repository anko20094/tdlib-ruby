module TD
  module Extension
    # Backfill struct fields the pinned tdlib-schema marks required but the older libtdjson core on the
    # servers omits from spontaneous updates. Without this TD::Types.wrap raises Dry::Struct::Error and
    # UpdateManager drops the whole update (e.g. updateNewMessage carrying MessageReplyTo::Message — the
    # bot<->userbot PM reply handshake never arrives). Extend DEFAULTS when a new missing-field error shows
    # in the listener log; drop an entry once the core catches up.
    module SchemaDrift
      DEFAULTS = {
        TD::Types::MessageReplyTo::Message => { 'poll_option_id' => '' },
        TD::Types::ChatPermissions => { 'can_react_to_messages' => false }
      }.freeze

      module_function

      def install!
        DEFAULTS.each { |type, defaults| type.singleton_class.prepend(wrapper(defaults)) }
      end

      def backfill(attributes, defaults)
        return attributes unless attributes.is_a?(::Hash)

        attributes = attributes.transform_keys(&:to_s)
        defaults.each { |key, value| attributes[key] = value unless attributes.key?(key) }
        attributes
      end

      # Anonymous module prepended onto a struct's singleton class so `new` backfills before the real
      # Dry::Struct constructor runs (explicit-arg super is supported inside define_method).
      def wrapper(defaults)
        Module.new do
          define_method(:new) do |attributes = {}|
            super(TD::Extension::SchemaDrift.backfill(attributes, defaults))
          end
        end
      end
    end
  end
end

TD::Extension::SchemaDrift.install!
