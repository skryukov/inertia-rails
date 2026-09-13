# frozen_string_literal: true

module InertiaRails
  module ScrollAdapters
    # Reads the page fields off a Pagy instance; `vars` in Pagy 9 and below,
    # `options` from Pagy 10 on.
    class PagyAdapter
      def accepted_options = Inertia::Core::ScrollMetadata::STANDARD_OVERRIDES

      def match?(metadata)
        defined?(::Pagy) && metadata.is_a?(::Pagy)
      end

      def call(metadata, **_options)
        page_name = metadata.respond_to?(:vars) ? metadata.vars.fetch(:page_param) : metadata.options[:page_key]
        {
          page_name: page_name.to_s,
          previous_page: metadata.respond_to?(:prev) ? metadata.prev : metadata.previous,
          next_page: metadata.next,
          current_page: metadata.page,
        }
      end
    end
  end
end
