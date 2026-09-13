# frozen_string_literal: true

module InertiaRails
  # The core protocol middleware with the Rails conventions hooked in.
  class Middleware < Inertia::Core::Rack::Middleware
    protected

    def call_app(env)
      if prevent_precognition_writes?(env)
        ActiveRecord::Base.while_preventing_writes { super }
      else
        super
      end
    end

    def request_for(env)
      ProtocolRequest.new(env)
    end

    def configuration_for(request)
      controller = request.controller
      return InertiaRails.configuration unless controller.respond_to?(:inertia_configuration, true)

      controller.send(:inertia_configuration)
    end

    # Controller-less endpoints (route-level redirects, mounted Rack apps) cannot
    # carry the mixin, so only a present non-Inertia controller opts out.
    def inertia_request?(request)
      controller = request.controller
      request.inertia? && (controller.nil? || controller.respond_to?(:inertia_configuration, true))
    end

    # Inertia session data is added via redirect_to and must survive every redirect
    # until a render consumes it. session.loaded? avoids forcing session I/O on
    # requests that never touched it — and could not have set the keys either.
    # Without a session middleware Rails 6.1 hands back a bare Hash instead.
    def after_app(request, status, stale:)
      return if Inertia::Core::Protocol::Redirect.redirect?(status) || stale

      session = request.session
      return unless session.respond_to?(:loaded?) && session.loaded?

      request.session.delete(:inertia_errors)
      request.session.delete(:inertia_clear_history)
      request.session.delete(:inertia_preserve_fragment)
    end

    def refresh_response(request, _configuration, _headers, _body)
      request.flash.keep
      super
    end

    private

    def prevent_precognition_writes?(env)
      env['HTTP_PRECOGNITION'] == 'true' &&
        InertiaRails.configuration.precognition_prevent_writes &&
        defined?(ActiveRecord::Base)
    end
  end
end
