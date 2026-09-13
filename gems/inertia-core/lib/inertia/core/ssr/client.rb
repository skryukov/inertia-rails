# frozen_string_literal: true

require 'digest/md5'
require 'net/http'

module Inertia
  module Core
    module SSR
      # Renders a page through the SSR server: POSTs the page JSON, answers
      # `{ 'head' => [...], 'body' => '...' }` or nil when SSR is off, the
      # bundle is missing, or the render failed and the configuration says to
      # fall back to the client.
      class Client
        DEFAULT_URL = 'http://localhost:13714'
        # Paths a configured `ssr_url` may already end with.
        RENDER_PATHS = ['/render', '/__inertia_ssr'].freeze

        def initialize(configuration, page:, host:, cache: nil)
          @configuration = configuration
          @page = page
          @host = host
          @cache = cache
          @dev_server_url = host.dev_server_url
        end

        def render
          return unless bundle_exists?

          if (cache_options = cache_options_hash)
            @host.cache_store.fetch(cache_key, **cache_options) { request }
          else
            request
          end
        rescue SSRError => e
          handle_error(e)
        rescue StandardError => e
          handle_error(SSRError.from_exception(e))
        end

        def url
          configured = @configuration.ssr_url
          if configured && RENDER_PATHS.any? { |path| configured.end_with?(path) }
            configured
          elsif configured
            "#{configured}/render"
          elsif @dev_server_url
            "#{@dev_server_url}/__inertia_ssr"
          else
            "#{DEFAULT_URL}/render"
          end
        end

        private

        def page_json
          @page_json ||= @page.to_json
        end

        def request
          @host.instrument(:ssr, url: url, component: @page[:component]) do
            uri = URI.parse(url)
            response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
              http.post(uri.request_uri, page_json, 'Content-Type' => 'application/json')
            end

            raise SSRError.from_response(error_body(response)) unless response.is_a?(Net::HTTPSuccess)

            JSON.parse(response.body)
          end
        end

        def error_body(response)
          body = begin
            JSON.parse(response.body)
          rescue JSON::ParserError
            {}
          end
          body['error'] ||= "SSR server returned #{response.code}"
          body
        end

        def handle_error(error)
          @host.report_error(error, ssr: true, component: @page[:component])
          @configuration.on_ssr_error&.call(error, @page)
          raise error if @configuration.ssr_raise_on_error

          nil
        end

        # The dev server renders every request fresh.
        def cache_options_hash
          return if @dev_server_url

          raw = @cache.nil? ? @configuration.ssr_cache : @cache
          case raw
          when true then {}
          when Hash then raw
          end
        end

        def cache_key
          "inertia_ssr/#{Digest::MD5.hexdigest(page_json)}"
        end

        def bundle_exists?
          return true if @dev_server_url

          bundle = @configuration.ssr_bundle
          return true if bundle.nil?

          Array(bundle).any? { |path| File.exist?(path) }
        end
      end
    end
  end
end
