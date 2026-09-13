# frozen_string_literal: true

module Inertia
  module Core
    class Prop
      # The options one prop was built with, read once and refused once. A
      # preset (`defer`, `merge`, …) is the same thing as its own flag set to
      # true, so `defer(merge: true)` and a `MergeProp` are judged by the same
      # rules — and composing them on one prop is the only spelling the client
      # can read.
      class Options
        # What turns each announcement on, and which options ride along with it.
        DELIVERY = %i[always defer optional].freeze
        MERGING = %i[merge deep_merge].freeze
        MERGE_PATHS = %i[append prepend match_on].freeze
        ONCE_PARTS = %i[key fresh expires_in].freeze
        DEFER_PARTS = %i[group rescue].freeze
        KNOWN = (DELIVERY + MERGING + MERGE_PATHS + ONCE_PARTS + DEFER_PARTS +
                 %i[once cache value producer]).freeze

        # Presets that merge whatever their options say.
        MERGE_PRESETS = %i[merge scroll].freeze

        # `always` holds nothing back and merges nothing, so every one of these
        # describes the opposite of what it is for.
        AGAINST_ALWAYS = (%i[defer optional once] + MERGING + MERGE_PATHS).freeze

        # Composition is spelled on the delivery preset: `defer(once: true)`,
        # never `once(defer: true)`. Each modifier preset with how it is spelled there.
        MODIFIER_PRESETS = { once: 'once: true', merge: 'merge: true' }.freeze

        attr_reader :preset

        def initialize(preset, options)
          @preset = preset
          @options = options
          @flags = options.select { |_name, value| value }
          @flags[preset] = true if preset
          refuse_unknown!
          refuse_contradiction!
          refuse_always!
          refuse_two_merge_modes!
          refuse_double_withholding!
          refuse_reverse_spelling!
          refuse_orphans!
        end

        def [](name)
          @options[name]
        end

        # Spelled out, whatever the value: `value: nil` is a value.
        def given?(name)
          @options.key?(name)
        end

        def on?(name)
          !!@flags[name]
        end

        def always?
          on?(:always)
        end

        def withholds?
          on?(:defer) || on?(:optional)
        end

        def defers?
          on?(:defer)
        end

        def onces?
          on?(:once)
        end

        def merges?
          MERGE_PRESETS.include?(@preset) || MERGING.any? { |name| on?(name) }
        end

        def merge_parts
          MERGE_PATHS.to_h { |name| [name, @options[name]] }.merge(deep_merge: on?(:deep_merge))
        end

        def once_parts
          ONCE_PARTS.to_h { |name| [name, @options[name]] }
        end

        private

        def refuse_unknown!
          unknown = @options.keys - KNOWN
          return if unknown.empty?

          raise ArgumentError, "Unknown prop option(s): #{unknown.join(', ')}."
        end

        # `once(once: false)` reads as a prop asking not to be what it is.
        def refuse_contradiction!
          return unless @preset && @options.key?(@preset) && !@options[@preset]

          raise ArgumentError, "`#{@preset}: #{@options[@preset].inspect}` contradicts this prop type."
        end

        def refuse_always!
          clash = on?(:always) && AGAINST_ALWAYS.find { |name| on?(name) }
          return unless clash

          raise ArgumentError,
                "Cannot combine `always` with `#{clash}`: an `always` prop is sent on every request, whole."
        end

        def refuse_two_merge_modes!
          return unless @options[:merge] && @options[:deep_merge]

          raise ArgumentError,
                'Cannot combine `merge` with `deep_merge`: the client merges a prop one way or the other.'
        end

        def refuse_double_withholding!
          return unless on?(:defer) && on?(:optional)

          raise ArgumentError,
                'Cannot combine `defer` with `optional`: both omit the first load. ' \
                '`defer` also tells the client to fetch it.'
        end

        def refuse_reverse_spelling!
          delivery = MODIFIER_PRESETS.key?(@preset) && %i[defer optional].find { |name| on?(name) }
          return unless delivery

          raise ArgumentError,
                "Cannot combine `#{@preset}` with `#{delivery}` this way — " \
                "spell it `#{delivery}(#{MODIFIER_PRESETS[@preset]})`."
        end

        # A sub-option with nothing to belong to is a typo or a stale edit, and
        # quietly doing nothing is how it stays one.
        def refuse_orphans!
          refuse_orphan!(:merge, MERGE_PATHS) unless merges?
          refuse_orphan!(:once, ONCE_PARTS) unless onces?
          refuse_orphan!(:defer, DEFER_PARTS) unless defers?
        end

        def refuse_orphan!(owner, parts)
          orphan = parts.find { |name| @flags.key?(name) }
          return unless orphan

          raise ArgumentError, "`#{orphan}:` belongs to `#{owner}`, which this prop is not."
        end
      end
    end
  end
end
