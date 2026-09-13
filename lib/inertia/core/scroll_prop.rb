# frozen_string_literal: true

module Inertia
  module Core
    # One page of an infinite scroll: the value merges the way the client says
    # it is scrolling, and the page carries the pagination the client needs to
    # ask for the next one.
    class ScrollProp < Prop
      # What a scroll prop reads itself. Anything else belongs to the
      # pagination adapter, which knows its own vocabulary.
      OWN_OPTIONS = %i[wrapper deep_merge match_on optional defer group rescue].freeze

      # Options that contradict paging: the direction is the client's to pick,
      # the value changes every request, and there is nothing to hold back.
      UNSUPPORTED = %i[merge append prepend once always fresh expires_in value cache live].freeze

      def self.preset
        :scroll
      end

      def initialize(metadata: nil, wrapper: nil, **options, &block)
        refuse_unsupported!(options)
        refuse_wrapped_deep_merge!(wrapper, options)
        @wrapper = wrapper.nil? ? nil : WireName.check!(:wrapper, wrapper)
        super(**options.slice(*OWN_OPTIONS), &block)
        @scroll = Announcements::Scroll.new(metadata: metadata, options: options.except(*OWN_OPTIONS))
      end

      private

      # The next page merges under the wrapper, the way the visit says it is
      # scrolling.
      def build_merge
        deep = @options.on?(:deep_merge)
        Announcements::Merge.new(
          append: deep ? nil : (@wrapper || true),
          match_on: @options[:match_on],
          deep_merge: deep,
          intent: true
        )
      end

      def refuse_unsupported!(options)
        name = UNSUPPORTED.find { |option| options.key?(option) }
        return unless name

        raise ArgumentError, "`#{name}:` is not supported on scroll props#{reason(name)}."
      end

      def reason(name)
        return '' unless name == :cache

        ' — an infinite scroll changes with every request; cache the query instead, keying on the page'
      end

      def refuse_wrapped_deep_merge!(wrapper, options)
        return unless wrapper && options[:deep_merge]

        raise ArgumentError,
              'Cannot combine `deep_merge` with `wrapper`: a deep merge already reaches ' \
              'every array inside the prop.'
      end
    end
  end
end
