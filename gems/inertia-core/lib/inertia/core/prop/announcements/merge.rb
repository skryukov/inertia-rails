# frozen_string_literal: true

module Inertia
  module Core
    class Prop
      module Announcements
        # `mergeProps` / `prependProps` / `deepMergeProps` / `matchPropsOn`:
        # where inside the prop the client appends or prepends, and which field
        # identifies a row it already holds. Everything is a suffix of the
        # prop's own path, decided once at construction — except an infinite
        # scroll's direction, which the client picks per request.
        class Merge
          ROOT = nil

          def self.contribute(ledger, visit)
            lists = { mergeProps: [], prependProps: [], deepMergeProps: [], matchPropsOn: [] }
            ledger.each do |entry|
              merge = entry.prop.merge
              merge.add_to(lists, entry.path, visit) if merge && announces?(entry)
            end
            lists
          end

          # A merge describes the value however it arrives, so a prop this
          # response held back still announces it; an infinite scroll's
          # direction belongs to the page that delivered it. A reset cancels
          # either.
          def self.announces?(entry)
            return false if entry.silenced? || entry.reset?

            entry.delivered? || entry.prop.scroll.nil?
          end

          def initialize(append: nil, prepend: nil, match_on: nil, deep_merge: false, intent: false)
            @deep = deep_merge
            @intent = intent
            appended, append_fields = paths(:append, append)
            prepended, prepend_fields = paths(:prepend, prepend)
            refuse_deep_directions!(append, prepend)
            refuse_impossible_directions!(appended, prepended)
            appended = [ROOT] if appended.empty? && prepended.empty?
            @append = order(appended).freeze
            @prepend = order(prepended).freeze
            @match_on = (fields(match_on) + append_fields + prepend_fields).freeze
          end

          def add_to(lists, path, visit)
            append, prepend = directions(visit)
            if @deep
              lists[:deepMergeProps].concat(expand(path, append + prepend))
            else
              lists[:mergeProps].concat(expand(path, append))
              lists[:prependProps].concat(expand(path, prepend))
            end
            lists[:matchPropsOn].concat(expand(path, @match_on))
          end

          private

          def directions(visit)
            return [@append, @prepend] unless @intent

            visit.scroll_intent.to_s == 'prepend' ? [[], @append] : [@append, []]
          end

          def expand(path, suffixes)
            suffixes.map { |suffix| suffix.nil? ? path : "#{path}.#{suffix}" }
          end

          # A direction reads as `true` (the whole prop), one path, several
          # paths, or paths each with the field rows are matched on.
          def paths(option, value)
            case value
            when nil then [[], []]
            when true then [[ROOT], []]
            when String, Symbol then [[WireName.check!(option, value)], []]
            when ::Array then [value.map { |entry| WireName.check!(option, entry) }.uniq, []]
            when ::Hash then hash_paths(option, value)
            else
              raise ArgumentError,
                    "`#{option}:` accepts true, a String path, an Array of paths, or a Hash of " \
                    "path => match field — got #{value.inspect}."
            end
          end

          def hash_paths(option, value)
            named = value.map { |path, field| [WireName.check!(option, path), field] }
            [named.map(&:first).uniq,
             named.filter_map { |path, field| "#{path}.#{WireName.check!(:match_on, field)}" if field }]
          end

          def fields(match_on)
            return [] if match_on.nil?

            Array(match_on).map { |entry| WireName.check!(:match_on, entry) }
          end

          def order(list)
            list.include?(ROOT) ? list : list.sort
          end

          def refuse_deep_directions!(append, prepend)
            return unless @deep

            named = { append: append, prepend: prepend }.find { |_option, value| !value.nil? }
            return unless named

            raise ArgumentError,
                  "Cannot combine `deep_merge` with `#{named.first}`: a deep merge already " \
                  'reaches every array inside the prop.'
          end

          def refuse_impossible_directions!(appended, prepended)
            if appended == [ROOT] && prepended == [ROOT]
              raise ArgumentError, 'Cannot combine both `append: true` and `prepend: true`.'
            end

            refuse_root_with_paths!(:append, appended, prepended)
            refuse_root_with_paths!(:prepend, prepended, appended)
            refuse_both_directions!(appended, prepended)
          end

          def refuse_root_with_paths!(option, rooted, others)
            return unless rooted == [ROOT] && !others.empty?

            raise ArgumentError,
                  "Cannot combine `#{option}: true` with per-path directions: " \
                  'the whole prop merges one way, or each path does.'
          end

          def refuse_both_directions!(appended, prepended)
            both = appended & prepended
            return if both.empty?

            raise ArgumentError, "Cannot both append and prepend at `#{both.first}`."
          end
        end
      end
    end
  end
end
