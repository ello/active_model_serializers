require 'active_support/core_ext/class/attribute'

module ActionController
  module Serialization
    extend ActiveSupport::Concern

    include ActionController::Renderers

    def get_serializer(resource)
      @_serializer ||= @_serializer_opts.delete(:serializer)
      @_serializer ||= ActiveModel::Serializer.serializer_for(resource)

      if @_serializer_opts.key?(:each_serializer)
        @_serializer_opts[:serializer] = @_serializer_opts.delete(:each_serializer)
      end

      @_serializer
    end

    def default_serializer_options
      {}
    end

    def use_adapter?
      !(@_serializer_opts.key?(:adapter) && !@_serializer_opts[:adapter])
    end

    [:_render_option_json, :_render_with_renderer_json].each do |renderer_method|
      define_method renderer_method do |resource, options|
        @_serializer_opts = default_serializer_options.merge(options)

        if use_adapter? && (serializer = get_serializer(resource))
          # omg hax
          object = serializer.new(resource, @_serializer_opts)
          adapter = ActiveModel::Serializer::Adapter.create(object, @_serializer_opts)
          super(adapter, options)
        else
          super(resource, options)
        end
      end
    end
  end
end
