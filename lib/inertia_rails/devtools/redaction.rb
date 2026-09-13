# frozen_string_literal: true

require 'active_support/parameter_filter'

module InertiaRails
  module Devtools
    # The core redactor with the app's `config.filter_parameters` folded into the
    # configured lists, so a secret Rails already keeps out of its logs is never recorded.
    module Redaction
      REDACTED = Inertia::Core::Devtools::Redactor::REDACTED
      UNSERIALIZABLE = Inertia::Core::Devtools::Redactor::UNSERIALIZABLE

      module_function

      # Rebuilt only when the lists change: compiling the filter is the expensive part.
      def redactor
        key = [application_filter_parameters,
               Array(InertiaRails.configuration.devtools_redact_keys),
               Array(InertiaRails.configuration.devtools_redact_headers)]

        cached = @redactor
        return cached.last if cached && cached.first == key

        redactor = build(*key)
        @redactor = [key, redactor]
        redactor
      end

      def redact(value)
        redactor.redact(value)
      end

      def redact_headers(headers)
        redactor.redact_headers(headers)
      end

      def redact_payload(payload)
        redactor.redact_payload(payload)
      end

      def redact_url(url)
        redactor.redact_url(url)
      end

      def sanitize(value)
        Inertia::Core::Devtools::Redactor.sanitize(value)
      end

      def build(app_filters, keys, header_keys)
        filter = ActiveSupport::ParameterFilter.new(app_filters + exact_matchers(keys), mask: REDACTED)
        Inertia::Core::Devtools::Redactor.new(filter: filter, header_keys: header_keys)
      end

      def application_filter_parameters
        Rails.application&.config&.filter_parameters || []
      rescue StandardError
        []
      end

      # The configured keys name a parameter exactly; the app's own filters
      # keep Rails' substring semantics.
      def exact_matchers(keys)
        keys.filter_map { |key| /\A#{Regexp.escape(key.to_s.downcase)}\z/i if key.to_s != '' }.uniq
      end
    end
  end
end
