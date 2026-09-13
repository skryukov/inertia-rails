# frozen_string_literal: true

module Inertia
  module Core
    # Normalizes pagination metadata for `scrollProps`. An adapter answers
    # `match?(metadata)` and `call(metadata, **options)` with the page fields;
    # one that also answers `accepted_options` is validated against them,
    # while one that does not stays open and takes every option.
    module ScrollMetadata
      class MissingMetadataAdapterError < Error; end

      # What the built-in adapters (and the bare page-fields form) accept.
      STANDARD_OVERRIDES = %i[page_name previous_page next_page current_page].freeze

      WIRE_KEYS = {
        page_name: :pageName,
        previous_page: :previousPage,
        next_page: :nextPage,
        current_page: :currentPage,
      }.freeze

      class HashAdapter
        def accepted_options = STANDARD_OVERRIDES

        def match?(metadata)
          metadata.is_a?(Hash)
        end

        def call(metadata, **_options)
          {
            page_name: metadata.fetch(:page_name),
            previous_page: metadata.fetch(:previous_page),
            next_page: metadata.fetch(:next_page),
            current_page: metadata.fetch(:current_page),
          }
        end
      end

      # The bare page-fields form: nothing to read from, every field an override.
      class PageFields
        def accepted_options = STANDARD_OVERRIDES

        def match?(_metadata)
          true
        end

        def call(_metadata, **_options)
          {}
        end
      end

      class << self
        attr_accessor :adapters

        def extract(metadata, **options)
          adapter = adapter_for(metadata)
          refuse_unknown_options!(adapter, options)
          fields = adapter.call(metadata, **options).merge(options.slice(*STANDARD_OVERRIDES))
          refuse_missing_fields!(metadata, fields)
          WIRE_KEYS.to_h { |field, wire| [wire, fields[field]] }
        end

        def register_adapter(adapter)
          adapters.unshift(adapter.new)
        end

        # Validation without extraction, so a prop can refuse a bad override
        # when it is built instead of when it first announces.
        def validate!(metadata, **options)
          refuse_unknown_options!(adapter_for(metadata), options)
        end

        private

        def adapter_for(metadata)
          adapters.find { |candidate| candidate.match?(metadata) } || page_fields
        end

        def page_fields
          @page_fields ||= PageFields.new
        end

        # An adapter that declares nothing stays open — whether registered or
        # assigned to `adapters` directly.
        def refuse_unknown_options!(adapter, options)
          return unless adapter.respond_to?(:accepted_options)

          accepted = adapter.accepted_options
          unknown = options.keys - accepted
          return if unknown.empty?

          raise ArgumentError,
                "Unknown scroll metadata option(s): #{unknown.join(', ')} — " \
                "#{adapter.class} accepts #{accepted.join(', ')}."
        end

        def refuse_missing_fields!(metadata, fields)
          return if (STANDARD_OVERRIDES - fields.keys).empty?

          raise MissingMetadataAdapterError,
                "No ScrollMetadata adapter found for #{metadata.inspect} " \
                '- pass Pagy/Kaminari, a Hash, or the page fields as options.'
        end
      end

      # An adapter for a pagination library ships with the host that depends
      # on it, registered here (`inertia_rails` registers Kaminari and Pagy).
      self.adapters = [HashAdapter.new]
    end
  end
end
