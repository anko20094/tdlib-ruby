module TD
  module Extension
    class HashHelper
      class << self
        def deep_to_hash(obj)
          case obj
          when nil, String, Numeric, TrueClass, FalseClass
            obj
          when Symbol
            obj.to_s
          when Array
            obj.map { |e| deep_to_hash(e) }
          when Hash
            obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_to_hash(v) }
          else
            if obj.respond_to?(:to_h)
              deep_to_hash(obj.to_h)
            elsif obj.respond_to?(:to_hash)
              deep_to_hash(obj.to_hash)
            elsif obj.respond_to?(:to_s)
              obj.to_s
            else
              raise TypeError, "Cannot convert #{obj.class} to JSON"
            end
          end
        end

        def get_unknown_structure_data(structure, field_name)
          if structure.respond_to?(field_name)
            structure.public_send(field_name)
          elsif structure.is_a?(Hash)
            structure[field_name.to_s] || structure[field_name.to_sym]
          end
        end
      end
    end
  end
end
