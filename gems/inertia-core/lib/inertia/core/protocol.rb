# frozen_string_literal: true

require 'cgi'
require 'uri'

module Inertia
  module Core
    # The wire vocabulary of the Inertia protocol and the pure decisions an
    # adapter makes with it.
    module Protocol
      HEADER = 'X-Inertia'
      VERSION_HEADER = 'X-Inertia-Version'
      LOCATION_HEADER = 'X-Inertia-Location'

      # HTML shells embed the page JSON in a `<script>`: `</` must not end it.
      SCRIPT_TERMINATOR = %r{</}

      module_function

      # The header's value is `true` by protocol, but presence is what every
      # adapter checks.
      def request?(headers)
        !headers[HEADER].nil?
      end

      # Keeps a cache from serving the JSON and HTML forms of one URL to each
      # other.
      def vary(existing)
        values = existing.to_s.split(',').map(&:strip).reject(&:empty?)
        values << HEADER unless values.any? { |value| value.casecmp?(HEADER) }
        values.join(', ')
      end

      # JSON safe to embed inside a `<script>` element.
      def script_json(json)
        json.gsub(SCRIPT_TERMINATOR, '<\/')
      end

      # What the client boots from on a first load: the page JSON in a
      # `<script>` next to an empty root, or the root itself carrying the page
      # in `data-page`.
      def root_element(page, id:, script: false, nonce: nil)
        json = page.to_json
        return %(<div id="#{escape_html(id)}" data-page="#{escape_html(json)}"></div>) unless script

        attributes = %(data-page="#{escape_html(id)}" type="application/json")
        attributes += %( nonce="#{escape_html(nonce)}") if nonce
        %(<script #{attributes}>#{script_json(json)}</script>\n<div id="#{escape_html(id)}"></div>)
      end

      def escape_html(value)
        CGI.escapeHTML(value.to_s)
      end

      # Tells the client to make a full page visit to `url`.
      def location_headers(url, version: nil)
        headers = { LOCATION_HEADER => url }
        headers[VERSION_HEADER] = version.to_s unless version.nil?
        headers
      end

      # The whole response, for an adapter that halts a request with it.
      def location_response(url, version: nil)
        [409, location_headers(url, version: version), []]
      end

      # The client echoes the version it booted with; a differing one on a GET
      # means its assets are stale.
      module Version
        module_function

        # A numeric server version compares numerically, so `1` and `'1.0'`
        # agree; anything else compares as the strings the header carries.
        def stale?(client, server)
          coerce(client, server) != coerce(server, server)
        end

        def coerce(value, server)
          server.is_a?(Numeric) ? value.to_f : value
        end
        private_class_method :coerce
      end

      # Redirect semantics for XHR visits.
      module Redirect
        STATUSES = [301, 302, 303, 307, 308].freeze
        # A 303 already forces a GET on follow, and 307/308 preserve the
        # request method by design.
        REWRITABLE = [301, 302].freeze
        # A redirect after these would replay the method on the target.
        NON_GET_METHODS = %w[PUT PATCH DELETE].freeze
        # A full page visit is always a GET, so only these can become one.
        CONVERTIBLE = [301, 302, 303].freeze

        module_function

        def redirect?(status)
          STATUSES.include?(status)
        end

        def status_for(method, status)
          REWRITABLE.include?(status) && NON_GET_METHODS.include?(method) ? 303 : status
        end

        # Whether `location` leaves the origin the request came in on. `host`
        # is compared without brackets, the way `URI#hostname` answers.
        def external?(location, scheme:, host:, port:)
          return false if location.nil? || location.empty?

          uri = URI.parse(location)
          return false if uri.host.nil? || uri.host.empty?

          target_scheme = uri.scheme || scheme
          target_port = uri.port || (target_scheme == 'https' ? 443 : 80)
          target_scheme != scheme || !uri.hostname.casecmp?(host) || target_port != port
        rescue URI::InvalidURIError
          false
        end
      end
    end
  end
end
