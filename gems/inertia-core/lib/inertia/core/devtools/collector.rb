# frozen_string_literal: true

require 'json'

module Inertia
  module Core
    module Devtools
      # Watches one render's walk and, once the host hands over the page it
      # built from it, assembles the entry's page half: a badge row per prop
      # and the value each row points at.
      class Collector < Observer
        MISSING = Object.new.freeze

        attr_reader :component

        def initialize(component:, deferred_request: false, render_source: nil, share_sources: {},
                       shared_keys: [], sources: Sources::NULL, host: Host.new, redactor: Redactor.new)
          super()
          @component = component
          @deferred_request = deferred_request
          @render_source = render_source
          @share_sources = share_sources
          @shared_keys = shared_keys
          @sources = sources
          @host = host
          @redactor = redactor
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
          rows = badge_rows

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

        # Every top-level page prop gets a row; a nested one only when badged.
        # A rescued prop has no value on the page but keeps its row.
        def badge_rows
          classifier = PropClassifier.new(@metadata, deferred_request: @deferred_request)
          rows = {}

          @ledger.each do |entry|
            next unless entry.delivered?

            path = entry.path
            rescued = @ledger.rescued?(path)
            next unless rescued || !dig(page_props, path).equal?(MISSING)

            badge = classifier.classify(path, entry.prop, reset: entry.reset?, rescued: rescued)
            next if path.include?('.') && badge == PropClassifier::PLAIN

            rows[path] = row(path, badge)
          end

          page_props.each_key { |key| rows[key.to_s] ||= row(key.to_s, PropClassifier::PLAIN) }
          rows
        end

        def row(path, badge)
          row = { shared: @shared_keys.include?(path) }.merge(badge)
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
          redacted = @redactor.redact(page_props)

          paths.each_with_object({}) do |path, values|
            value = dig(redacted, path)
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
