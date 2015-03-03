module ActiveModel
  class Serializer
    extend ActiveSupport::Autoload
    autoload :Configuration
    autoload :ArraySerializer
    autoload :Adapter
    include Configuration

    class << self
      attr_accessor :_attributes
      attr_accessor :_associations
      attr_accessor :_urls
      attr_accessor :_href
    end

    def self.inherited(base)
      base._attributes = {}
      base._associations = {}
      base._urls = []
      base._href = nil
    end

    def self.inherit_attributes
      @_attributes = superclass._attributes.dup
    end

    def self.inherit_associations
      @_associations = superclass._associations.dup
    end

    def self.group(name, &block)
      raise ArgumentError, 'Expected block' unless block_given?
      with_options group: name do |instance|
        instance.instance_eval(&block)
      end
    end

    def self.attributes(*attrs)
      options = attrs.extract_options!
      attrs.each { |attr| attribute(attr, options) }
    end

    def self.attribute(attr, options = {})
      key = options.fetch(:key, attr)
      @_attributes ||= {}
      @_attributes[key] = { options: options }

      define_method key do
        object.read_attribute_for_serialization(attr)
      end unless method_defined?(key)
    end

    def self.href(&block)
      raise ArgumentError, 'Expected block' unless block_given?
      @_href = block
    end

    def serialized_object_type
      self.class.root_name.to_s.pluralize
    end

    # Defines an association in the object that should be rendered.
    #
    # The serializer object should implement the association name
    # as a method which should return an array when invoked. If a method
    # with the association name does not exist, the association name is
    # dispatched to the serialized object.
    def self.has_many(*attrs)
      associate(:has_many, attrs)
    end

    # Defines an association in the object that should be rendered.
    #
    # The serializer object should implement the association name
    # as a method which should return an object when invoked. If a method
    # with the association name does not exist, the association name is
    # dispatched to the serialized object.
    def self.belongs_to(*attrs)
      associate(:belongs_to, attrs)
    end

    def self.associate(type, attrs) #:nodoc:
      options = attrs.extract_options!

      attrs.each do |attr|
        @_associations[attr] = { type: type, options: options }
        key = options.fetch(:as, attr)

        define_method key do
          object.send(key)
        end unless method_defined?(key)
      end
    end

    def self.url(attr)
      @_urls.push attr
    end

    def self.urls(*attrs)
      @_urls.concat attrs
    end

    def self.serializer_for(resource)
      if resource.respond_to?(:to_ary)
        config.array_serializer
      else
        get_serializer_for(resource.class)
      end
    end

    def self.adapter
      adapter_class = case config.adapter
      when Symbol
        ActiveModel::Serializer::Adapter.adapter_class(config.adapter)
      when Class
        config.adapter
      end
      unless adapter_class
        valid_adapters = Adapter.constants.map { |klass| ":#{klass.to_s.downcase}" }
        raise ArgumentError, "Unknown adapter: #{config.adapter}. Valid adapters are: #{valid_adapters}"
      end

      adapter_class
    end

    def self._root
      @@root ||= false
    end

    def self._root=(root)
      @@root = root
    end

    def self.root_name
      name.demodulize.underscore.sub(/_serializer$/, '') if name
    end

    attr_accessor :object, :root

    def initialize(object, options = {})
      @object = object
      @options = options.dup
      @root = options[:root] || (self.class._root ? self.class.root_name : false)

      @including = @options.delete(:including) || []
      @excluding = @options.delete(:excluding) || []
      @include = @options.delete(:include) || []
      @exclude = @options.delete(:exclude) || []
    end

    def json_key
      if root == true || root.nil?
        self.class.root_name
      else
        root
      end
    end

    def attributes(_options = {})
      hash = {}
      self.class._attributes.each do |name, options|
        next unless include_in_serialization?(name, options[:options])
        hash[name] = send(name)
      end
      hash
    end

    def href
      return nil unless self.class._href.respond_to?(:call)
      instance_eval(&self.class._href)
    end

    def associations(_options = {})
      hash = {}
      self.class._associations.each do |name, options|
        next unless include_in_serialization?(name, options[:options])
        hash[options[:options].fetch(:as, name)] = options[:options]
      end
      hash
    end

    def each_association(&block)
      self.class._associations.each do |name, options|
        next unless include_in_serialization?(name, options[:options])
        association_options = options[:options].dup
        key = association_options.fetch(:as, name)
        association = send(key)
        next unless association

        serializer_class = association_options.delete(:serializer)
        serializer_class ||= ActiveModel::Serializer.serializer_for(association)

        association_options[:serializer] = association_options.delete(:each_serializer)
        association_options[:parent] = self
        association_options[:association_name] = name
        association_options = @options.dup.merge(association_options)

        serializer = serializer_class.new(association, association_options) if serializer_class

        block.call(key, serializer, association_options) if block_given?
      end
    end

    protected

    def include_in_serialization?(attr, options)
      ret = true
      if options[:group]
        ret = false
        ret = true unless @excluding.empty?
        ret = true if has_included_group?(options[:group])
        return false if has_excluded_group?(options[:group])
      end
      ret = true if has_included_attr?(attr)
      ret = false if has_excluded_attr?(attr)
      # let the serializer finally decide
      return ret && send("include_#{attr}?") if respond_to?("include_#{attr}?", true)
      ret
    end

    def has_excluded_group?(group)
      @excluding.include?(group)
    end

    def has_included_group?(group)
      @including.include?(group)
    end

    def has_excluded_attr?(name)
      @exclude.include?(name)
    end

    def has_included_attr?(name)
      @include.include?(name) || @include.include?(:all)
    end

    private

    def self.get_serializer_for(klass)
      serializer_class_name = "#{klass.name}Serializer"
      serializer_class = serializer_class_name.safe_constantize

      if serializer_class
        serializer_class
      elsif klass.superclass
        get_serializer_for(klass.superclass)
      end
    end

  end
end
