require 'inertia_rails/renderer'
require 'inertia_rails/engine'

require 'patches/debug_exceptions'
require 'patches/better_errors'
require 'patches/request'
require 'patches/mapper'

ActionController::Renderers.add :inertia do |component, options|
  InertiaRails::Renderer.new(
    component,
    self,
    request,
    response,
    method(:render),
    props: options[:props],
    view_data: options[:view_data],
    deep_merge: options[:deep_merge],
  ).render
end

module InertiaRails
  class Error < StandardError; end

  class UnoptimizedPartialReloadHandler
    def call(*args)
      event = ActiveSupport::Notifications::Event.new(*args)
      action = event.payload[:configuration].action_on_unoptimized_partial_reload
      return unless action

      message =
        "InertiaRails: The \"#{event.payload[:paths].join(', ')}\" " \
          "prop(s) were excluded in a partial reload but still evaluated because they are defined as values. " \
          "Consider wrapping them in something callable like a lambda."

      case action
      when :log
        Rails.logger.debug(message)
      when :raise
        raise InertiaRails::UnoptimizedPartialReloadError.new(event.payload[:paths])
      else
        return action.call(event) if action.respond_to?(:call)

        raise ArgumentError, "Unknown action for InertiaRails: #{action.inspect}"
      end
    end
  end

  class UnoptimizedPartialReloadError < StandardError
    attr_reader :paths

    def initialize(paths)
      @paths = paths
      super("The #{paths.join(', ')} prop(s) were excluded in a partial reload but still evaluated because they are defined as values.")
    end
  end

  def self.deprecator # :nodoc:
    @deprecator ||= ActiveSupport::Deprecation.new
  end
end
