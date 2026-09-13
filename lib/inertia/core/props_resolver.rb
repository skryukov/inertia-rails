# frozen_string_literal: true

module Inertia
  module Core
    # Walks a props hash into the props the page ships and the metadata that
    # describes them. One recursive walk over positions: a position is a dotted
    # path plus the reload filter in force there, and everything — presets, dot
    # notation, caching, rescuing — is a decision made at one.
    class PropsResolver
      # A value that produces a value produces one of these at every step; a
      # chain longer than this is a producer that never settles.
      MAX_PRODUCERS = 128

      # A container that contains itself nests forever; this is where the walk
      # stops believing it will end.
      MAX_DEPTH = 128

      # Nothing ships at this position.
      DROPPED = Object.new.freeze

      def initialize(props, evaluator:, visit: {}, observer: Observer::NULL, eager: false)
        @props = props
        @evaluator = evaluator
        @visit = visit.is_a?(Visit) ? visit : Visit.new(visit)
        @observer = observer
        @eager = eager
        @producing = {}.compare_by_identity
      end

      # What the walk met and what the visit decided about each; the page
      # metadata is derived from it after the walk, and DevTools reads the same.
      attr_reader :ledger

      def resolve
        @ledger = Ledger.new
        props = walk_slots(Slot.tree(@props), Cursor.root(@visit.reload))
        metadata = Metadata.derive(@ledger, @visit)
        @observer.walked(@ledger)
        [props, metadata]
      end

      private

      def host
        @evaluator.host
      end

      def dropped?(value)
        value.equal?(DROPPED)
      end

      # Prop keys, each with the dotted keys written underneath it.
      def walk_slots(slots, cursor)
        resolved = {}
        slots.each do |key, slot|
          value = walk_slot(slot, Slot::MISSING, cursor.at(key))
          resolved[key] = value unless dropped?(value)
        end
        resolved
      end

      def walk_slot(slot, existing, cursor)
        base = slot.value? ? walk(slot.value, cursor) : existing
        return base unless slot.branches?

        graft(slot, base, cursor)
      end

      # Dot notation: `'user.name'` is written into whatever `user` resolved to,
      # whichever of the two the props hash listed first.
      def graft(slot, base, cursor)
        refuse_ungraftable!(slot, base, cursor)
        target = base.is_a?(::Hash) ? base : {}
        grafted = {}
        slot.branches.each do |key, branch|
          value = walk_slot(branch, target.fetch(key, Slot::MISSING), cursor.at(key))
          grafted[key] = value unless dropped?(value)
        end
        return target.merge(grafted) unless grafted.empty?

        base.equal?(Slot::MISSING) ? DROPPED : base
      end

      # One position: a prop is always met, because only the prop knows it
      # outranks the visit; anything else is produced, then walked.
      def walk(value, cursor)
        return walk_prop(value, cursor) if value.is_a?(Prop)
        return walk_excluded(value, cursor) if cursor.excludes?

        settled = settle(value, cursor)
        settled.is_a?(Prop) ? walk_prop(settled, cursor) : walk_container(settled, cursor)
      end

      # An excluded position is never evaluated: a closure or serializer stays
      # unrun and plain data is dropped. A literal container is still looked
      # through for the props written inside it, so the ledger records every
      # prop the page carries — an observer sees what was silenced, not only
      # what shipped.
      def walk_excluded(value, cursor)
        silence(value, cursor) if Container.holds_prop?(value, MAX_DEPTH)
        DROPPED
      end

      def silence(value, cursor)
        refuse_depth!(cursor)
        return @ledger.met(cursor.path, value, :silenced) if value.is_a?(Prop)
        return unless Container.plain?(value)

        if value.is_a?(::Hash)
          value.each { |key, inner| silence(inner, cursor.at(key)) }
        else
          value.each_with_index { |inner, index| silence(inner, cursor.at(index)) }
        end
      end

      # Runs closures and serializers until a prop or a plain value is left.
      def settle(value, cursor)
        steps = 0
        while value.is_a?(Proc) || value.respond_to?(:to_inertia)
          raise ResolutionError.endless(cursor.path, MAX_PRODUCERS) if steps == MAX_PRODUCERS

          value = value.is_a?(Proc) ? @evaluator.run(value) : value.to_inertia
          steps += 1
        end
        value
      end

      def walk_prop(prop, cursor)
        raise ResolutionError.uncacheable(cursor.path, prop.class) if cursor.cached?
        raise ResolutionError.keyless(cursor.path, prop.class) if cursor.in_array? && prop.requires_key?

        verdict = prop.decide(@visit, cursor.path, eager: @eager, excluded: cursor.excludes?)
        @ledger.met(cursor.path, prop, verdict, reset: @visit.reset?(cursor.path))
        return DROPPED unless verdict == :delivered

        cursor = cursor.unfiltered if prop.overrides_exclusion? && cursor.excludes?
        return deliver(prop, cursor) unless prop.rescue?

        rescuing(prop, cursor) do
          value = deliver(prop, cursor)
          dropped?(value) ? value : host.serialize(value)
        end
      end

      def deliver(prop, cursor)
        value = settle(produce(prop), cursor)
        raise ResolutionError.stacked(cursor.path, prop.class, value.class) if value.is_a?(Prop)

        walk_container(value, cursor)
      end

      def produce(prop)
        return prop.produce(@evaluator) unless prop.cache

        cached(prop.cache) { prop.produce(@evaluator) }
      end

      # What a `cache:` prop stores: the value resolved to data once and
      # replayed for every visit, so nothing per-request may be inside it.
      def cached(cache)
        key = host.expand_cache_key(cache.key)
        json = host.instrument(:cache_fetch, key: key) do |payload|
          payload[:hit] = true
          host.cache_store.fetch(key, **cache.options) do
            payload[:hit] = false
            JSON.generate(host.serialize(walk(yield, Cursor.cached)))
          end
        end
        RawJson.new(json)
      end

      # `rescue:` covers a failing data source. A shape the library itself
      # refuses is a mistake in the props, and stays one.
      def rescuing(prop, cursor)
        yield
      rescue Error
        raise
      rescue StandardError => e
        host.report_error(e, prop: cursor.path)
        @ledger.rescued(cursor.path, prop, e)
        DROPPED
      end

      # A container is handed back as it is, refused, walked with the filter,
      # or walked without one.
      def walk_container(value, cursor)
        return value unless value.is_a?(::Hash) || value.is_a?(::Array)
        return opaque(value, cursor) if Container.opaque?(value)
        return walk_inside(value, cursor) if cursor.names_below?

        walk_unfiltered(value, cursor)
      end

      # The reload names nothing under this path, so no descendant can be
      # excluded: plain data is the same value rebuilt and is handed over, and
      # a container with a producer inside is walked with no filter to apply.
      def walk_unfiltered(value, cursor)
        return value unless holds_producer?(value, MAX_DEPTH)

        walk_inside(value, cursor.unfiltered)
      end

      # Every container on the way down to a producer is remembered by
      # identity once a scan has found it, so walking into it is not a rescan
      # of what an ancestor's scan went through: a chain nested 60 deep is
      # scanned once, not once per level. A container found plain is handed
      # over whole and never asked again.
      def holds_producer?(value, depth)
        @producing[value] || scan(value, depth)
      end

      def scan(value, depth)
        return true if depth.zero? || value.is_a?(Prop) || value.is_a?(Proc) || value.respond_to?(:to_inertia)
        return false unless value.is_a?(::Hash) || value.is_a?(::Array)

        found = if value.is_a?(::Hash)
                  value.any? { |_key, inner| scan(inner, depth - 1) }
                else
                  value.any? { |inner| scan(inner, depth - 1) }
                end
        @producing[value] = true if found
        found
      end

      def walk_inside(value, cursor)
        refuse_depth!(cursor)
        value.is_a?(::Hash) ? walk_hash(value, cursor) : walk_array(value, cursor)
      end

      # A hash whose every key was excluded has nothing left to say, so it goes
      # along with its own key.
      def walk_hash(hash, cursor)
        resolved = {}
        hash.each do |key, value|
          result = walk(value, cursor.at(key))
          resolved[key] = result unless dropped?(result)
        end
        resolved.empty? && !hash.empty? ? DROPPED : resolved
      end

      # An array slot keeps its place whatever happens to it: indexes are part
      # of every path the metadata announces.
      def walk_array(array, cursor)
        array.each_with_index.map do |element, index|
          slot = cursor.at(index, in_array: true)
          result = walk(element, slot)
          dropped?(result) ? placeholder(element, slot) : result
        end
      end

      # An excluded element was never evaluated, so what marks its slot is the
      # shape it was written in: `{}` for a Hash, `nil` for anything else. A
      # value that was evaluated and emptied keeps the `{}` it had.
      def placeholder(element, slot)
        slot.excludes? && !literal_hash?(element) ? nil : {}
      end

      def opaque(value, cursor)
        return value unless holds_producer?(value, MAX_DEPTH)

        raise ResolutionError.opaque_producer(cursor.path, value.class)
      end

      def literal_hash?(value)
        value.is_a?(::Hash) && Container.plain?(value)
      end

      def refuse_ungraftable!(slot, base, cursor)
        raise ResolutionError.dotted_prop(cursor.path, slot.value.class) if slot.value.is_a?(Prop)
        return if base.equal?(Slot::MISSING) || dropped?(base)

        raise ResolutionError.dotted_opaque(cursor.path, base.class) if Container.opaque?(base)
        raise ResolutionError.ungraftable(cursor.path, base.class) unless base.is_a?(::Hash)
      end

      def refuse_depth!(cursor)
        raise ResolutionError.too_deep(cursor.path, MAX_DEPTH) if cursor.depth > MAX_DEPTH
      end
    end
  end
end
