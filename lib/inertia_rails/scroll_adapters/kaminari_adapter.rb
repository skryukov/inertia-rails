# frozen_string_literal: true

module InertiaRails
  module ScrollAdapters
    # Reads the page fields off a Kaminari-paginated relation.
    class KaminariAdapter
      def accepted_options = Inertia::Core::ScrollMetadata::STANDARD_OVERRIDES

      def match?(metadata)
        defined?(::Kaminari) && metadata.is_a?(::Kaminari::PageScopeMethods)
      end

      def call(metadata, **_options)
        {
          page_name: (::Kaminari.config.param_name || 'page').to_s,
          previous_page: metadata.prev_page,
          next_page: metadata.next_page,
          current_page: metadata.current_page,
        }
      end
    end
  end
end
