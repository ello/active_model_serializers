module ActiveModel
  class Serializer
    class Adapter
      class Json < Adapter
        def serializable_hash(options = {})
          if serializer.respond_to?(:each)
            @result = serializer.map{|s| self.class.new(s).serializable_hash }
          else
            @result = serializer.attributes(options)

            serializer.each_association do |name, association, opts|
              if association.respond_to?(:each)
                array_serializer = association
                @result[name] = array_serializer.map { |s| self.class.new(s).serializable_hash }
              else
                if association
                  @result[name] = self.class.new(association).serializable_hash
                else
                  @result[name] = nil
                end
              end
            end
          end

          if root = options.fetch(:root, serializer.json_key)
            @result = { root => @result }
          end

          @result
        end
      end
    end
  end
end
