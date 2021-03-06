module ActiveModel
  class Serializer
    class Adapter
      class JsonApi < Adapter
        def initialize(serializer, options = {})
          super
          serializer.root = true
          @hash = {}
          @top = @options.fetch(:top) { @hash }
        end

        def serializable_hash(options = {})
          @root = (@options[:root] || serializer.json_key.to_s.pluralize).to_sym

          if serializer.respond_to?(:each)
            @hash[@root] = serializer.map do |s|
              self.class.new(s, @options.merge(top: @top)).serializable_hash(options)[@root]
            end
          else
            @hash[@root] = attributes_for_serializer(serializer, @options)

            add_resource_links(@hash[@root], serializer)
          end

          @hash
        end

        private

        def add_links(resource, name, serializers)
          type = serialized_object_type(serializers)
          resource[:links] ||= {}

          if name.to_s == type || !type
            resource[:links][name] ||= []
            resource[:links][name] += serializers.map{|serializer| serializer.id.to_s }
          else
            resource[:links][name] ||= {}
            resource[:links][name][:type] = type
            resource[:links][name][:ids] ||= []
            resource[:links][name][:ids] += serializers.map{|serializer| serializer.id.to_s }
          end
        end

        def add_link(resource, name, serializer)
          resource[:links] ||= {}
          resource[:links][name] = nil

          if serializer
            type = serialized_object_type(serializer)
            id = serializer.id.to_s
            href = serializer.href

            resource[:links][name] ||= {}
            resource[:links][name][:type] = type unless name.to_s == type || !type
            resource[:links][name][:href] = href unless href.nil?
            resource[:links][name][:id] = id
          end
        end

        def add_linked(resource_name, serializers, parent = nil)
          serializers = Array(serializers) unless serializers.respond_to?(:each)

          resource_path = [parent, resource_name].compact.join('.')

          if include_assoc?(resource_path)
            type = serialized_object_type(serializers)
            return unless type
            plural_name = type.pluralize.to_sym
            @top[:linked] ||= {}
            @top[:linked][plural_name] ||= []

            serializers.each do |serializer|
              attrs = attributes_for_serializer(serializer, @options)

              add_resource_links(attrs, serializer, add_linked: true)

              if attrs_already_present_by_id?(attrs, plural_name)
                merge_attributes(attrs, plural_name)
              else
                @top[:linked][plural_name].push(attrs) unless @top[:linked][plural_name].include?(attrs)
              end
            end
          end

          serializers.each do |serializer|
            serializer.each_association do |name, association, opts|
              add_linked(name, association, resource_path) if association
            end if include_nested_assoc? resource_path
          end
        end

        def attrs_already_present_by_id?(attrs, plural_name)
          find_existing_attrs_based_on(attrs, plural_name).present?
        end

        def find_existing_attrs_based_on(attrs, plural_name)
          id = get_id(attrs)
          @top[:linked][plural_name].find { |existing| get_id(existing) == id }
        end

        def get_id(attrs)
          attrs[:id] || attrs['id']
        end

        def merge_attributes(attrs, plural_name)
          existing_attrs = find_existing_attrs_based_on(attrs, plural_name)
          existing_attrs.deep_merge!(attrs)
        end

        def attributes_for_serializer(serializer, options)
          if serializer.respond_to?(:each)
            result = []
            serializer.each do |object|
              attributes = object.attributes(options)
              attributes[:id] = attributes[:id].to_s if attributes[:id]
              result << attributes
            end
          else
            result = serializer.attributes(options)
            result[:id] = result[:id].to_s if result[:id]
          end

          result
        end

        def include_assoc?(assoc)
          return false unless @options[:include]
          check_assoc("#{assoc}$")
        end

        def include_nested_assoc?(assoc)
          return false unless @options[:include]
          check_assoc("#{assoc}.")
        end

        def check_assoc(assoc)
          return true if @options[:include].include?(:all)
          @options[:include].any? do |s|
            s.to_s.match(/^#{assoc.to_s.gsub('.', '\.')}/)
          end
        end

        def serialized_object_type(serializer)
          return false unless Array(serializer).first

          if Array(serializer).first.respond_to?(:serialized_object_type)
            return Array(serializer).first.serialized_object_type
          end

          type_name = Array(serializer).first.object.class.to_s.underscore
          if serializer.respond_to?(:first)
            type_name.pluralize
          else
            type_name
          end
        end

        def add_resource_links(attrs, serializer, options = {})
          options[:add_linked] = options.fetch(:add_linked, true)

          serializer.each_association do |name, association, opts|
            attrs[:links] ||= {}

            if association.respond_to?(:each)
              add_links(attrs, name, association)
            else
              add_link(attrs, name, association)
            end

            if @options[:embed] != :ids && options[:add_linked]
              Array(association).each do |association|
                add_linked(name, association)
              end
            end
          end
        end
      end
    end
  end
end
