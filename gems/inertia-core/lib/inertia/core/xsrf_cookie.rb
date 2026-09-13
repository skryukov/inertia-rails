# frozen_string_literal: true

module Inertia
  module Core
    # The XSRF handshake: the server sets `XSRF-TOKEN`, the client echoes it
    # as `X-XSRF-TOKEN`, and the middleware hands that to the app as its CSRF
    # header.
    module XsrfCookie
      COOKIE = 'XSRF-TOKEN'
      HEADER_ENV_KEY = 'HTTP_X_XSRF_TOKEN'
      CSRF_HEADER_ENV_KEY = 'HTTP_X_CSRF_TOKEN'
      SAFE_METHODS = %w[GET HEAD].freeze
      REFRESH_POLICIES = %i[always lazy].freeze

      module_function

      # Whether a protected response rewrites the cookie. `:always` does;
      # `:lazy` spares a safe request carrying one the host vouches for — the
      # block answers true when the cookie still matches the session, or when
      # checking would cost a session load.
      def refresh?(policy, request_method, cookie)
        return true unless policy == :lazy
        return true unless SAFE_METHODS.include?(request_method)
        return true if cookie.to_s.strip.empty?

        !yield(cookie)
      end
    end
  end
end
