# frozen_string_literal: true

module Inertia
  module Core
    # A prop: something that produces a value, what it tells the client about
    # itself, and the rule that decides whether this visit gets it at all. The
    # presets (`always`, `defer`, `merge`, …) are this class with one option
    # locked, which is why they compose as options instead of by nesting.
    class Prop
      def self.preset
        nil
      end

      # What this prop tells the client about itself, read by the metadata
      # contributors once the walk is done.
      attr_reader :cache, :defer, :merge, :once, :scroll

      def initialize(**options, &block)
        @options = Options.new(self.class.preset, options)
        @block = block
        @value = options[:value]
        @producer = options[:producer]
        refuse_missing_body!
        @cache = Cache.build(@options[:cache])
        @defer = Announcements::Defer.new(group: @options[:group]) if @options.defers?
        @merge = build_merge
        @once = Announcements::Once.new(**@options.once_parts) if @options.onces?
        @scroll = nil
      end

      # What DevTools badges this prop as, and the group it announces under.
      def kind
        self.class.preset || :plain
      end

      def group
        @defer&.group
      end

      def rescue?
        @options.on?(:rescue)
      end

      # An array slot has no path the client can address, so a prop cannot sit
      # in one — caching is the exception, being invisible to the client.
      def requires_key?
        true
      end

      def overrides_exclusion?
        @options.always?
      end

      # The verdict, top to bottom: an excluded prop is silenced unless it is
      # `always`; a client holding a `once` value is not sent it again; a
      # first load leaves `optional` and `defer` out. Whether the path is
      # excluded is the walk's to say: an `always` above this prop has already
      # won the visit's exclusion of everything below.
      def decide(visit, path, eager: false, excluded: false)
        return :silenced if excluded && !@options.always?
        return :held if @once&.held?(visit, path)
        return :omitted if @options.withholds? && !visit.partial? && !eager

        :delivered
      end

      def produce(evaluator)
        return evaluator.run(@block) if @block
        return @producer.call(evaluator) if @producer
        return evaluator.run(@value) if @value.is_a?(Proc)
        return @value.call if @value.respond_to?(:call)

        @value
      end

      private

      def build_merge
        Announcements::Merge.new(**@options.merge_parts) if @options.merges?
      end

      def value?
        @options.given?(:value)
      end

      def refuse_missing_body!
        return if @producer
        raise ArgumentError, 'You must provide either a value or a block, not both' if value? && @block
        raise ArgumentError, 'You must provide either a value or a block' unless value? || @block

        return unless @value.is_a?(Prop)

        raise ArgumentError,
              "A #{Core.type_name(@value.class)} cannot be another prop's value — " \
              'combine prop types as options on one prop instead.'
      end
    end

    # The historical name of the base class.
    BaseProp = Prop
  end
end
