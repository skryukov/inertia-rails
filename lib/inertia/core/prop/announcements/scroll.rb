# frozen_string_literal: true

module Inertia
  module Core
    class Prop
      module Announcements
        # `scrollProps`: where the client is in the pagination. The pagination
        # object is snapshotted when the prop is built and read when the page
        # announces, so an adapter's refusal lands on the request that would
        # have shown the page.
        class Scroll
          # Nothing was delivered, so there is no page for the client to be on.
          def self.contribute(ledger, _visit)
            pages = {}
            ledger.each do |entry|
              scroll = entry.prop.scroll
              pages[entry.path] = scroll.fields.merge(reset: entry.reset?) if scroll && entry.delivered?
            end
            { scrollProps: pages }
          end

          def initialize(metadata:, options:)
            ScrollMetadata.validate!(metadata, **options)
            @metadata = metadata.is_a?(::Hash) ? metadata.dup.freeze : metadata
            @options = options.transform_values { |value| value.is_a?(String) ? value.dup.freeze : value }.freeze
          end

          def fields
            ScrollMetadata.extract(@metadata, **@options)
          end
        end
      end
    end
  end
end
