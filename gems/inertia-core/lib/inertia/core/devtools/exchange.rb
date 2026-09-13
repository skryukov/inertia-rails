# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # One request and the response it got, as the entry needs them. The
      # defaults answer from the Rack env and the Rack response alone; a host
      # subclasses to hand over what only its framework has (the parsed
      # parameters, the matched route, a body it already buffered).
      class Exchange
        attr_reader :env, :status, :headers, :body

        def initialize(env, status: nil, headers: {}, body: nil)
          @env = env
          @status = status
          @headers = headers.to_h { |name, value| [name.to_s.downcase, value] }
          @body = body
        end

        def request_method
          request.request_method
        end

        def url
          request.url
        end

        def inertia?
          request.inertia?
        end

        # The framework's parsed parameters, or nil when it parsed none.
        def request_parameters
          nil
        end

        # Read after the app ran, so the stream is rewound first; one that
        # cannot rewind was consumed and has nothing left to record.
        def raw_request_body
          input = @env['rack.input']
          return unless input.respond_to?(:rewind)

          input.rewind
          input.read
        end

        # nil unless the body is already in memory: a file or a stream must
        # not be drained to record it.
        def response_content
          @body.to_ary.join if @body.respond_to?(:to_ary)
        end

        # `{ name:, uri:, action:, actionSource: }` for the route that handled it.
        def route
          nil
        end

        def header(name)
          value = @headers[name]
          value.is_a?(Array) ? value.first : value
        end

        # Where the response sends the client: a full-page location wins over
        # a 3xx target.
        def redirect_location
          location = header(Protocol::LOCATION_HEADER.downcase)
          location = header('location') if blank?(location) && (300...400).cover?(@status)
          location unless blank?(location)
        end

        private

        def request
          @request ||= Core::Rack::Request.new(@env)
        end

        def blank?(value)
          value.nil? || value.empty?
        end
      end
    end
  end
end
