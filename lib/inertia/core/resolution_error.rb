# frozen_string_literal: true

module Inertia
  module Core
    # A mistake in the props themselves — a producer that never settles, a
    # prop inside a cached value. `rescue: true` re-raises these instead of
    # eating them. Every shape the walk refuses is spelled out here, so the
    # walk itself only says where and why.
    class ResolutionError < Error
      class << self
        def endless(path, bound)
          new("Prop `#{path}` is still unresolved after #{bound} producers: " \
              'a value that produces itself never settles.')
        end

        def too_deep(path, bound)
          new("Prop `#{path}` produces itself: the walk nested deeper than #{bound} levels.")
        end

        def stacked(path, outer, inner)
          new("Prop `#{path}` (#{Core.type_name(outer)}) produces a prop type " \
              "(#{Core.type_name(inner)}). Prop types combine as options on one prop — " \
              '`defer(merge: true)` — never by nesting one in another.')
        end

        def keyless(path, prop_class)
          new("Prop `#{path}` places a #{Core.type_name(prop_class)} in an array, where it has no " \
              'key for the client to ask for or the page to announce. Give it a key of its own.')
        end

        # The path is inside the cached value, not the page: the cached entry
        # has to be the same bytes for every visit, and a prop type is not.
        def uncacheable(path, prop_class)
          where = path.empty? ? '' : " at `#{path}`"
          new("#{Core.type_name(prop_class)}#{where} cannot be cached: a cached value is resolved " \
              'once and replayed for every visit.')
        end

        def opaque_producer(path, container_class)
          new("Prop `#{path}` (#{container_class}) defines its own `as_json`, so the walk never " \
              'reaches inside it — and it holds a closure, a serializer or a prop type that would ' \
              'ship unresolved. Resolve the contents before handing the container over.')
        end

        # Writing into it means copying it, and the copy is a plain Hash.
        def dotted_opaque(path, container_class)
          new("Prop `#{path}` (#{container_class}) defines its own `as_json`, so a dotted key " \
              'cannot be written into it: what ships would be the raw contents it serializes away.')
        end

        def dotted_prop(path, prop_class)
          new("Prop `#{path}` (#{Core.type_name(prop_class)}) cannot take dotted keys: " \
              "the visit decides `#{path}` as a whole. Return the nested keys from the prop's block.")
        end

        def ungraftable(path, base_class)
          new("Prop `#{path}` (#{base_class}) has nothing to merge into — `#{path}.…` needs a Hash there.")
        end
      end
    end
  end
end
