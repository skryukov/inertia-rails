# frozen_string_literal: true

module Inertia
  module Core
    # The resolved value is stored as JSON in the host's cache store and
    # replayed verbatim. The client never learns of it, so it needs no prop key
    # of its own and may sit anywhere a value may.
    class CachedProp < Prop
      def self.preset
        :cache
      end

      def initialize(key, **options, &block)
        super(cache: options.empty? ? key : { key: key, **options }, &block)
      end

      def requires_key?
        false
      end
    end
  end
end
