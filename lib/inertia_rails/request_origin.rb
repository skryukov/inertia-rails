# frozen_string_literal: true

module InertiaRails
  # The origin the client reached, as the proxy in front of the app reported it.
  #
  # `ActionDispatch::Request` answers for the connection the app accepted, and
  # that differs from the client's origin in two ways: it ignores
  # `X-Forwarded-Port`, and it reads a chained `X-Forwarded-Proto` from the end,
  # where the scheme the client used sits at the front. An app that builds
  # absolute URLs from the client's origin then sees every redirect of its own
  # called external.
  class RequestOrigin
    def initialize(request)
      @request = request
    end

    # Proxies prepend, so the first entry faced the client. The request still
    # answers for the headers Rack reads on its own — `Forwarded`, `HTTPS`,
    # `X-Forwarded-Ssl`.
    def scheme
      @scheme ||= first_forwarded('HTTP_X_FORWARDED_PROTO', 'HTTP_X_FORWARDED_SCHEME') || @request.scheme
    end

    # Without brackets, the way `URI#hostname` answers, so the two compare.
    def host
      authority_host
    end

    # Never `SERVER_PORT` while a host header is around: that is the port the
    # app listens on, not the one the client reached.
    def port
      authority_port || last_forwarded('HTTP_X_FORWARDED_PORT')&.to_i || default_port
    end

    # Query string included: a location response sends the client here.
    def url
      host_with_port = port == default_port ? bracketed_host : "#{bracketed_host}:#{port}"

      "#{scheme}://#{host_with_port}#{@request.fullpath}"
    end

    private

    def default_port
      scheme == 'https' ? 443 : 80
    end

    # `X-Forwarded-Host`, else the `Host` header, else `SERVER_NAME:SERVER_PORT`.
    def authority
      @request.raw_host_with_port
    end

    def authority_host
      split_authority.first
    end

    def authority_port
      split_authority.last
    end

    # `[::1]:3000` splits at the last colon outside the brackets; a bare `[::1]`
    # or `example.com` has no port of its own.
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
        entries = @request.get_header(key).to_s.split(',').map(&:strip).reject(&:empty?)

        return entries unless entries.empty?
      end

      nil
    end
  end
end
