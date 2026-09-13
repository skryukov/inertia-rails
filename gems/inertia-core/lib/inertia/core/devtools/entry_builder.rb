# frozen_string_literal: true

require 'json'
require 'time'

module Inertia
  module Core
    module Devtools
      # One recorded request in the shape the extension reads: `__meta`, the
      # HTTP exchange, and the page half the collector assembled.
      class EntryBuilder
        RAW_BODY_LIMIT = 256_000
        WRITE_METHODS = %w[POST PUT PATCH DELETE].freeze
        TEXTUAL = %w[json text/ xml javascript].freeze
        EMPTY_ROUTE = { name: nil, uri: '', action: nil }.freeze

        def initialize(exchange, id:, batch_id: nil, elapsed_ms: 0.0, prefetch: false, collector: nil,
                       redactor: Redactor.new, error: nil)
          @exchange = exchange
          @id = id
          @batch_id = batch_id
          @elapsed_ms = elapsed_ms
          @prefetch = prefetch
          @collector = collector
          @redactor = redactor
          @error = error
        end

        def build
          page = @collector&.build || {}

          {
            __meta: meta,
            http: {
              requestHeaders: @redactor.redact_headers(request_headers),
              responseHeaders: @redactor.redact_headers(@exchange.headers),
              requestBody: request_body,
              responseBody: response_body(page[:responseBody]),
            },
            props: page[:props] || {},
            propValues: page[:propValues] || {},
            route: @exchange.route || EMPTY_ROUTE,
            renderSource: page[:renderSource],
            componentPath: page[:componentPath],
          }
        end

        private

        def meta
          now = Time.now
          env = @exchange.env

          meta = {
            id: @id,
            tabUuid: Headers.read(env, Headers::TAB),
            batchId: @batch_id,
            timestamp: now.utc.iso8601(3),
            utime: now.to_f,
            method: @exchange.request_method,
            url: @exchange.url,
            component: @collector&.component,
            requestType: RequestType.of(env, rendered: !@collector.nil?, prefetch: @prefetch),
            status: @exchange.status,
            redirectLocation: @exchange.redirect_location,
            serverTimingMs: @elapsed_ms,
            visitId: Headers.read(env, Headers::VISIT),
          }
          meta[:error] = { class: @error.class.name, message: @error.message.to_s } if @error
          meta
        end

        # Rack keeps request headers as `HTTP_*` env keys, bar the two
        # content ones.
        def request_headers
          @exchange.env.each_with_object({}) do |(key, value), headers|
            next unless value.is_a?(String)

            name = key.delete_prefix('HTTP_') if key.start_with?('HTTP_')
            name ||= key if %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
            headers[name.downcase.tr('_', '-')] = value if name
          end
        end

        def request_body
          if WRITE_METHODS.include?(@exchange.request_method) && !@exchange.inertia?
            return omitted('non-inertia-request')
          end

          parameters = @exchange.request_parameters
          return present(@redactor.redact(parameters)) unless parameters.nil? || parameters.empty?

          structured(@exchange.raw_request_body)
        rescue StandardError
          omitted('unserializable')
        end

        # The action raised: what went out is the framework's error page, and
        # `__meta.error` says why.
        def response_body(page)
          return omitted('non-inertia-response') if @error
          return raw_response_body unless @collector

          page.nil? ? { status: 'empty' } : present(@redactor.redact(page))
        end

        def raw_response_body
          content_type = @exchange.header('content-type').to_s.downcase
          return omitted('non-textual') unless TEXTUAL.any? { |needle| content_type.include?(needle) }

          content = @exchange.response_content
          return omitted('streamed') if content.nil?
          return { status: 'empty' } if content.empty?

          content_type.include?('json') ? structured(content) : omitted('non-inertia-response')
        end

        # A raw body is kept only as JSON: keys are what the redactor matches,
        # and an HTML page or a text blob can hide a secret under none.
        # The reason is one the extension has words for: to it, a body that
        # is not a JSON object is one that could not be serialized.
        def structured(content)
          return { status: 'empty' } if content.nil? || content.empty?
          return omitted('too-large') if content.bytesize > RAW_BODY_LIMIT

          decoded = JSON.parse(content)
          return omitted('unserializable') unless decoded.is_a?(Hash) || decoded.is_a?(Array)

          present(@redactor.redact(decoded))
        rescue JSON::ParserError
          omitted('unserializable')
        end

        def present(value)
          { status: 'present', value: value }
        end

        def omitted(reason)
          { status: 'omitted', reason: reason }
        end
      end
    end
  end
end
