# frozen_string_literal: true

require 'json'
require 'uri'

module Inertia
  module Core
    module Devtools
      # Scrubs an entry before it touches the disk: values by key, headers by
      # name, URLs by query key. The key filter is the host's (Rails hands in
      # the one that keeps secrets out of its logs); the header names are a
      # plain list.
      class Redactor
        REDACTED = '[REDACTED]'
        UNSERIALIZABLE = '[UNSERIALIZABLE]'
        URL_KEYS = %w[url redirectlocation].freeze
        URL_HEADERS = %w[location content-location referer refresh x-inertia-location].freeze
        # A host's filter only filters, so a key is sensitive when filtering
        # this stand-in changes it.
        PROBE = 'inertia-devtools-probe'

        def initialize(filter: KeyFilter.new, header_keys: [])
          @filter = filter
          @header_keys = header_keys.map { |key| key.to_s.downcase }
        end

        def redact(value)
          case value
          when Hash then @filter.filter(value)
          when Array then value.map { |item| redact(item) }
          else value
          end
        end

        # Values flattened to the strings the extension shows.
        def redact_headers(headers)
          headers.each_with_object({}) do |(name, value), result|
            result[name] = header_value(name.to_s.downcase, value)
          end
        end

        # The storage pass: query strings under `url`-like keys, then every
        # leaf JSON would refuse, so one bad value never costs the entry.
        def redact_payload(value, key = nil)
          case value
          when Hash then value.to_h { |nested_key, nested| [nested_key, redact_payload(nested, nested_key)] }
          when Array then value.map { |item| redact_payload(item) }
          when String then self.class.sanitize(URL_KEYS.include?(key.to_s.downcase) ? redact_url(value) : value)
          else self.class.sanitize(value)
          end
        end

        def redact_url(url)
          return url unless url.include?('?')

          uri = URI.parse(url)
          return url if uri.query.nil? || uri.query.empty?

          uri.query = URI.encode_www_form(
            URI.decode_www_form(uri.query).map { |name, value| [name, sensitive_query?(name) ? REDACTED : value] }
          )
          uri.to_s
        rescue StandardError
          # A query that will not parse may still hold the secret: dropped whole.
          "#{url.split('?').first}?#{REDACTED}"
        end

        class << self
          def sanitize(value)
            case value
            when Hash then value.transform_values { |nested| sanitize(nested) }
            when Array then value.map { |item| sanitize(item) }
            else encodable?(value) ? value : UNSERIALIZABLE
            end
          end

          def encodable?(value)
            return true if value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding?

            JSON.generate([value])
            true
          rescue StandardError
            false
          end
        end

        private

        def header_value(name, value)
          return REDACTED if @header_keys.include?(name)

          value = value.is_a?(Array) ? value.join(', ') : value.to_s
          URL_HEADERS.include?(name) ? redact_url(value) : value
        end

        # `user[token]` is sensitive at any depth.
        def sensitive_query?(name)
          name.scan(/[^\[\]]+/).any? { |segment| @filter.filter_param(segment, PROBE) != PROBE }
        end
      end
    end
  end
end
