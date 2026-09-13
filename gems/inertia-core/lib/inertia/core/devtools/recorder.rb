# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # One request's recording, from the middleware in to the persisted
      # entry: the id every response carries, the collector the render
      # reports to, the discovery tag on an HTML page load, and the entry
      # written once the body has gone out. A host subclasses for what only
      # its framework has.
      class Recorder
        ENV_KEY = 'inertia.devtools'
        VALIDATOR_HEADERS = %w[etag last-modified].freeze

        attr_reader :env, :id, :collector, :exception

        def initialize(env, repository:, host: Host.new, redactor: Redactor.new, sources: Sources::NULL, limits: {})
          @env = env
          @repository = repository
          @host = host
          @redactor = redactor
          @sources = sources
          @limits = limits
          @id = Ulid.generate
          @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @collector = nil
          @share_sources = {}
        end

        def batch_id
          return unless inertia_request?

          Headers.read(@env, Headers::PARENT)
        end

        def outgoing_parent_id
          return @id if prefetch?

          batch_id || @id
        end

        def prefetch?
          RequestType.prefetch?(@env)
        end

        def elapsed_ms
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round(3)
        end

        def render_started(component:, render_source:, shared_keys:)
          swallow do
            @collector = Collector.new(
              component: component,
              deferred_request: !Headers.read(@env, Headers::DEFERRED).nil?,
              render_source: render_source,
              share_sources: @share_sources,
              shared_keys: shared_keys,
              sources: @sources,
              host: @host,
              redactor: @redactor
            )
          end
        end

        def share_source(keys, source)
          return unless source

          swallow do
            keys.each { |key| @share_sources[key.to_s] ||= refine_source(source, key) }
          end
        end

        # The page carries the values the client receives; the metadata carries the badges.
        def page_rendered(page, metadata = nil)
          @collector&.page_rendered(page, metadata)
        end

        def finish(status, headers, body, error: nil)
          swallow do
            id_key, parent_key, base_path_key = Headers.response_keys
            headers[id_key] = @id
            headers[parent_key] = outgoing_parent_id
            headers[base_path_key] = base_path if base_path
          end

          body = inject_tag(status, headers, body)

          entry = swallow { build_entry(status, headers, body, error) }

          return [status, headers, body] unless entry

          [status, headers, ClosingBody.new(body) { persist(entry) }]
        end

        # Without exception handling above, the raise is the only response there is:
        # keep a synthetic 500 so the request is not lost.
        def record_exception(error)
          @exception = error

          entry = swallow { build_entry(500, {}, nil, error) }

          persist(entry) if entry
        end

        protected

        # What the framework knows about the exchange that the env does not.
        def exchange(status, headers, body)
          Exchange.new(@env, status: status, headers: headers, body: body)
        end

        # The CSP nonce the discovery tag carries, when the page has one.
        def nonce
          nil
        end

        # The body as a String when it is already in memory; nil for a file or
        # a stream, which must not be drained.
        def buffered_body(body)
          body.to_ary.join if body.respond_to?(:to_ary)
        end

        # A share site narrowed to the line that defines `key`.
        def refine_source(source, _key)
          source
        end

        private

        def build_entry(status, headers, body, error)
          EntryBuilder.new(exchange(status, headers, body),
                           id: @id, batch_id: batch_id, elapsed_ms: elapsed_ms, prefetch: prefetch?,
                           collector: @collector, redactor: @redactor, error: error).build
        end

        def inertia_request?
          Core::Rack::Request.new(@env).inertia?
        end

        # The prefix the app is mounted under, as Rack hands it over
        # (`map '/sub'`, a proxy's mount point); nil at the root. The
        # extension builds the entries URL from it, so it must be the prefix
        # the browser sees, which is what the server put in `SCRIPT_NAME`.
        def base_path
          Headers.read(@env, 'SCRIPT_NAME')
        end

        def inject_tag(status, headers, body)
          swallow do
            next body unless status == 200 && @collector
            next body if inertia_request?
            next body unless header_value(headers, 'content-type').to_s.include?('text/html')
            next body if validated?(headers)

            content = buffered_body(body)
            next body unless content

            content = ScriptTag.insert(content, id: @id, nonce: nonce, base_path: base_path)

            replace_content_length(headers, content)
            body.close if body.respond_to?(:close)
            [content]
          end || body
        end

        def header_value(headers, name)
          key = headers.keys.find { |candidate| candidate.to_s.casecmp(name).zero? }
          key && headers[key]
        end

        # Rack::ETag will not recompute a digest the app set itself (`fresh_when`), so a
        # mutated body would ship under a stale validator and revalidate to a 304 without
        # the tag. Leave it alone; the id is still on the response header.
        def validated?(headers)
          VALIDATOR_HEADERS.any? { |name| !header_value(headers, name).to_s.empty? }
        end

        def replace_content_length(headers, content)
          key = headers.keys.find { |candidate| candidate.to_s.casecmp('content-length').zero? }
          headers[key] = content.bytesize.to_s if key
        end

        def persist(entry)
          swallow do
            @repository.record(@id, @redactor.redact_payload(entry),
                               tab_uuid: Headers.read(@env, Headers::TAB), **@limits)
            @repository.prune_if_due
          end
        end

        # Recording never alters the response: anything that raises inside it
        # is reported and dropped.
        def swallow
          yield
        rescue StandardError => e
          @host.report_error(e, devtools: true)
          nil
        end
      end
    end
  end
end
