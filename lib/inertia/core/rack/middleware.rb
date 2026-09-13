# frozen_string_literal: true

module Inertia
  module Core
    module Rack
      # The response-side protocol for any Rack app. Mount it inside the
      # session middleware: a location response keeps the app's headers,
      # Set-Cookie included. An adapter subclasses to hook its own request,
      # configuration and session conventions in.
      class Middleware
        # The XSRF cookie comes back as a header the app reads under the CSRF name.
        XSRF_HEADER_ENV_KEY = 'HTTP_X_XSRF_TOKEN'
        CSRF_HEADER_ENV_KEY = 'HTTP_X_CSRF_TOKEN'

        def initialize(app, configuration: nil)
          @app = app
          @configuration = configuration
        end

        def call(env)
          copy_xsrf_to_csrf!(env)
          status, headers, body = call_app(env)

          request = request_for(env)
          configuration = configuration_for(request)
          handled = configuration && inertia_request?(request)

          if handled && external_redirect?(request, configuration, status, headers)
            status, headers, body = location_response!(headers, body, url: delete_header(headers, 'Location'),
                                                                      version: configuration.version)
          end

          stale = handled && stale?(request, configuration)
          after_app(request, status, stale: stale)
          return [status, headers, body] unless handled

          return refresh_response(request, configuration, headers, body) if stale && !location?(headers)

          [Protocol::Redirect.status_for(request.request_method, status), headers, body]
        end

        protected

        def call_app(env)
          @app.call(env)
        end

        # Subclass `Rack::Request` when the framework knows the request better
        # (its session, the path before routing rewrote it).
        def request_for(env)
          Request.new(env)
        end

        # nil leaves the request alone.
        def configuration_for(_request)
          @configuration
        end

        def inertia_request?(request)
          request.inertia?
        end

        # Runs for every response, between the app and the protocol rewrites:
        # an adapter clears per-visit session state here, unless the visit
        # goes on (`stale`, or a redirect status).
        def after_app(request, status, stale:); end

        def refresh_response(request, configuration, headers, body)
          location_response!(headers, body, url: request.url, version: configuration.version)
        end

        def stale?(request, configuration)
          request.get? && Protocol::Version.stale?(request.version, configuration.version)
        end

        private

        def copy_xsrf_to_csrf!(env)
          token = env[XSRF_HEADER_ENV_KEY]
          env[CSRF_HEADER_ENV_KEY] = token if token
        end

        # XHR follows redirects transparently, so a cross-origin target is
        # only reachable through a window.location visit.
        def external_redirect?(request, configuration, status, headers)
          configuration.convert_external_redirects &&
            Protocol::Redirect::CONVERTIBLE.include?(status) &&
            Protocol::Redirect.external?(header(headers, 'Location'),
                                         scheme: request.scheme, host: request.host, port: request.port)
        end

        # Mutates the headers in place to keep the rest of the response,
        # notably Set-Cookie (which matters mid-OAuth).
        def location_response!(headers, body, url:, version:)
          delete_header(headers, 'Content-Type')
          delete_header(headers, 'Content-Length')
          body.close if body.respond_to?(:close)
          Protocol.location_headers(url, version: version).each do |name, value|
            headers[Rack.header_name(name)] = value
          end
          [409, headers, []]
        end

        def location?(headers)
          !header(headers, Protocol::LOCATION_HEADER).nil?
        end

        def header(headers, name)
          headers[name] || headers[name.downcase]
        end

        def delete_header(headers, name)
          value = headers.delete(name)
          headers.delete(name.downcase) || value
        end
      end
    end
  end
end
