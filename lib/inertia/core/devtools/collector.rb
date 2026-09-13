# frozen_string_literal: true

require 'json'

module Inertia
  module Core
    module Devtools
      # Watches one render's walk and, once the host hands over the page it
      # built from it, assembles the entry's page half: a row per prop with
      # what the ledger said about it, and the value each row points at.
      class Collector < Observer
        MISSING = Object.new.freeze
        # A row the ledger had nothing to add to. `inertiaType` is the
        # extension's badge slot; it stays empty until a classifier reads
        # the prop's kind and the page metadata into it.
        PLAIN = { inertiaType: nil }.freeze

        attr_reader :component

        def initialize(component:, render_source: nil, share_sources: {}, shared_keys: [],
                       sources: Sources::NULL, host: Host.new)
          super()
          @component = component
          @render_source = render_source
          @share_sources = share_sources
          @shared_keys = shared_keys
          @sources = sources
          @host = host
          @ledger = Ledger::EMPTY
          @page = nil
          @metadata = nil
        end

        def walked(ledger)
          @ledger = ledger
        end

        # The walk alone cannot say which keys ship: the host's prop
        # transformer runs after it.
        def page_rendered(page, metadata)
          @page = normalize(page)
          @metadata = metadata
        end

        def build
          rows = verdict_rows

          {
            component: @component,
            props: rows,
            propValues: values(rows.keys),
            renderSource: @render_source,
            componentPath: @sources.component_path(@component),
            responseBody: @page,
          }
        end

        private

        # Every top-level page prop gets a row; a nested one only when the
        # ledger has something to say about it. A rescued prop has no value
        # on the page but keeps its row.
        def verdict_rows
          rows = {}

          @ledger.each do |entry|
            next unless entry.delivered?

            path = entry.path
            rescued = @ledger.rescued?(path)
            next unless rescued || !dig(page_props, path).equal?(MISSING)

            verdict = verdict(entry, rescued: rescued)
            next if path.include?('.') && verdict == PLAIN

            rows[path] = row(path, verdict)
          end

          page_props.each_key { |key| rows[key.to_s] ||= row(key.to_s, PLAIN) }
          rows
        end

        # What the walk decided about the prop. Its badge — the kind, the
        # defer group, how the metadata says it merges — is not read here.
        def verdict(entry, rescued:)
          verdict = PLAIN.dup
          verdict[:reset] = true if entry.reset?
          verdict[:rescued] = true if rescued
          verdict
        end

        def row(path, verdict)
          row = { shared: @shared_keys.include?(path) }.merge(verdict)
          if (source = @share_sources[path])
            row[:shareSource] = source
          elsif !row[:shared] && (line = render_line(path))
            row[:renderSource] = { file: @render_source[:file], line: line }
          end
          row
        end

        def render_line(path)
          @render_source && @sources.prop_line(@render_source[:file], @render_source[:line], path)
        end

        def values(paths)
          paths.each_with_object({}) do |path, values|
            value = dig(page_props, path)
            values[path] = value unless value.equal?(MISSING)
          end
        end

        def page_props
          props = @page && @page['props']
          props.is_a?(Hash) ? props : {}
        end

        # The page as it goes over the wire: the host's serialization, as JSON.
        def normalize(page)
          JSON.parse(JSON.generate(@host.serialize(page)))
        rescue StandardError
          nil
        end

        def dig(value, path)
          path.split('.').reduce(value) do |current, segment|
            case current
            when Hash
              return MISSING unless current.key?(segment)

              current[segment]
            when Array
              index = Integer(segment, exception: false)
              return MISSING unless index && index < current.length

              current[index]
            else
              return MISSING
            end
          end
        end
      end
    end
  end
end
