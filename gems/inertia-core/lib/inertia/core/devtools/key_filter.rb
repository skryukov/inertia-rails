# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # The plain-Ruby key filter: a key matches exactly (case-insensitive) or
      # by a Regexp. A host with its own log filtering hands the Redactor
      # anything answering `filter(hash)` and `filter_param(key, value)`
      # instead (Rails: `ActiveSupport::ParameterFilter`).
      class KeyFilter
        def initialize(keys = [], mask: Redactor::REDACTED)
          @patterns = Array(keys).filter_map { |key| pattern(key) }
          @mask = mask
        end

        def filter(value)
          case value
          when Hash then value.to_h { |key, nested| [key, filter_param(key, nested)] }
          when Array then value.map { |item| filter(item) }
          else value
          end
        end

        def filter_param(key, value)
          sensitive?(key) ? @mask : filter(value)
        end

        private

        def pattern(key)
          return key if key.is_a?(Regexp)

          name = key.to_s
          /\A#{Regexp.escape(name)}\z/i unless name.empty?
        end

        def sensitive?(key)
          (key.is_a?(String) || key.is_a?(Symbol)) && @patterns.any? { |pattern| pattern.match?(key.to_s) }
        end
      end
    end
  end
end
