# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # The badge for one prop the walk delivered: its own kind, what the page
      # metadata says about how it merges, and whether this request is the
      # deferred follow-up fetch. The metadata is read rather than the prop
      # because it is what shipped: a reset prop announces no merge.
      class PropClassifier
        TYPES = { always: 'always', defer: 'defer', optional: 'optional',
                  merge: 'merge', scroll: 'scroll', once: 'once', }.freeze
        PLAIN = { inertiaType: nil }.freeze

        def initialize(metadata, deferred_request: false)
          metadata ||= {}
          @deferred_request = deferred_request
          @append = metadata[:mergeProps] || []
          @prepend = metadata[:prependProps] || []
          @deep = metadata[:deepMergeProps] || []
          @match_on = metadata[:matchPropsOn] || []
          @once = (metadata[:onceProps] || {}).values.map { |claim| claim[:prop] }
          @live = (metadata[:liveProps] || {}).keys
        end

        def classify(path, prop, reset: false, rescued: false)
          badge = { inertiaType: type(prop) }
          badge[:deferGroup] = prop.group if grouped?(prop)
          badge[:reset] = true if reset
          badge[:once] = true if @once.include?(path)
          direction = merge_direction(path)
          badge[:mergeDirection] = direction if direction
          badge[:deepMerge] = true if @deep.include?(path) || inside?(@match_on, path)
          badge[:live] = true if @live.include?(path)
          badge[:rescued] = true if rescued
          badge
        end

        private

        # Reloaded by a manual partial request, a deferred prop is a plain prop.
        def type(prop)
          return if prop.kind == :defer && !@deferred_request

          TYPES[prop.kind]
        end

        # A scroll prop keeps its group; a deferred one only on the fetch that
        # delivers it.
        def grouped?(prop)
          prop.group && (prop.kind == :scroll || (prop.kind == :defer && @deferred_request))
        end

        # A prop merging inside itself in one direction only reads as that
        # direction; both ways reads as append.
        def merge_direction(path)
          return 'prepend' if @prepend.include?(path)
          return 'append' if @append.include?(path) || @deep.include?(path)

          prepends = inside?(@prepend, path)
          appends = inside?(@append, path)
          return unless prepends || appends

          prepends && !appends ? 'prepend' : 'append'
        end

        def inside?(paths, path)
          paths.any? { |inner| inner.start_with?("#{path}.") }
        end
      end
    end
  end
end
