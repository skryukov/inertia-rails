# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # The one word the extension files an entry under. The client says what
      # it meant a request for; `rendered` (did an Inertia page come out of
      # it) tells an initial page load from a plain HTTP request.
      module RequestType
        PRECOGNITION = 'HTTP_PRECOGNITION'
        PARTIAL = 'HTTP_X_INERTIA_PARTIAL_COMPONENT'
        # A browser announces a speculative fetch under one of these.
        PREFETCH_HEADERS = %w[HTTP_PURPOSE HTTP_SEC_PURPOSE HTTP_X_MOZ].freeze

        module_function

        def of(env, rendered:, prefetch: prefetch?(env))
          return 'precognition' if Headers.read(env, PRECOGNITION)
          return rendered ? 'initial' : 'http' unless Core::Rack::Request.new(env).inertia?
          return 'deferred' if Headers.read(env, Headers::DEFERRED)
          return 'poll' if Headers.read(env, Headers::POLL)
          return 'partial' if env.key?(PARTIAL)
          return 'prefetch' if prefetch

          'navigate'
        end

        # `Sec-Purpose` may carry qualifiers (`prefetch;anonymous-client-ip`).
        def prefetch?(env)
          PREFETCH_HEADERS.any? { |header| env[header].to_s.downcase.include?('prefetch') }
        end
      end
    end
  end
end
