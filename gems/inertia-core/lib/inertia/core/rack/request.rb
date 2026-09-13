# frozen_string_literal: true

module Inertia
  module Core
    module Rack
      # The few things the protocol needs to know about a request, read
      # straight from a Rack env so no Rack gem is required.
      #
      # The origin follows the `X-Forwarded-*` headers, because the app builds
      # its redirect URLs from those too and the protocol compares the two:
      # reading the raw connection would call every redirect external.
      class Request
        attr_reader :env

        def initialize(env)
          @env = env
        end

        def inertia?
          @env.key?('HTTP_X_INERTIA')
        end

        def request_method
          @env['REQUEST_METHOD']
        end

        def get?
          request_method == 'GET'
        end

        def version
          @env['HTTP_X_INERTIA_VERSION']
        end

        # The markers a TLS-terminating proxy leaves, in the order Rack reads
        # them: `HTTPS=on`, `X-Forwarded-Ssl: on`, then the forwarded scheme.
        # Chains are read from the front: proxies prepend, so the first entry
        # faced the client.
        def scheme
          @scheme ||= tls_marker_scheme || forwarded_scheme || @env['rack.url_scheme'] || 'http'
        end

        # Without brackets, the way `URI#hostname` answers, so the two compare.
        def host
          authority_host
        end

        # Never `SERVER_PORT`: that is the port the app listens on, not the one
        # the client reached.
        def port
          authority_port || last_forwarded('HTTP_X_FORWARDED_PORT')&.to_i || default_port
        end

        # Query string included: a location response sends the client here.
        def url
          host_with_port = port == default_port ? bracketed_host : "#{bracketed_host}:#{port}"
          "#{scheme}://#{host_with_port}#{fullpath}"
        end

        def fullpath
          path = "#{@env['SCRIPT_NAME']}#{@env['PATH_INFO']}"
          query = @env['QUERY_STRING']
          query.nil? || query.empty? ? path : "#{path}?#{query}"
        end

        private

        def tls_marker_scheme
          'https' if @env['HTTPS'] == 'on' || @env['HTTP_X_FORWARDED_SSL'] == 'on'
        end

        def forwarded_scheme
          rfc_forwarded('proto') || first_forwarded('HTTP_X_FORWARDED_PROTO', 'HTTP_X_FORWARDED_SCHEME')
        end

        # RFC 7239: `Forwarded: for=1.2.3.4;proto=https, for=10.0.0.1;proto=http`,
        # one element per proxy, the client-facing one first.
        def rfc_forwarded(parameter)
          forwarded(['HTTP_FORWARDED'])&.each do |element|
            element.split(';').each do |pair|
              key, value = pair.split('=', 2)
              return value.strip.delete_prefix('"').delete_suffix('"') if key&.strip&.casecmp?(parameter) && value
            end
          end
          nil
        end

        def default_port
          scheme == 'https' ? 443 : 80
        end

        def authority
          @authority ||= last_forwarded('HTTP_X_FORWARDED_HOST') || @env['HTTP_HOST'] ||
                         [@env['SERVER_NAME'], @env['SERVER_PORT']].compact.join(':')
        end

        def authority_host
          split_authority.first
        end

        def authority_port
          split_authority.last
        end

        # `[::1]:3000` splits at the last colon outside the brackets; a bare
        # `[::1]` or `example.com` has no port of its own.
        def split_authority
          @split_authority ||= begin
            value = authority.to_s
            colon = port_separator(value)
            host = colon ? value[0...colon] : value
            port = value[(colon + 1)..] if colon
            [host.delete_prefix('[').delete_suffix(']'), (port.to_i unless port.nil? || port.empty?)]
          end
        end

        # The colon before a port sits after an IPv6 host's closing bracket.
        def port_separator(value)
          colon = value.rindex(':')
          bracket = value.rindex(']')
          colon if colon && (bracket.nil? || colon > bracket)
        end

        def bracketed_host
          host.include?(':') ? "[#{host}]" : host
        end

        def first_forwarded(*keys)
          forwarded(keys)&.first
        end

        def last_forwarded(*keys)
          forwarded(keys)&.last
        end

        def forwarded(keys)
          keys.each do |key|
            value = @env[key]
            next if value.nil? || value.empty?

            entries = value.split(',').map(&:strip).reject(&:empty?)
            return entries unless entries.empty?
          end
          nil
        end
      end
    end
  end
end
