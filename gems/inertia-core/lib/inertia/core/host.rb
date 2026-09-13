# frozen_string_literal: true

module Inertia
  module Core
    # What the core asks of its host framework: the behaviour only the framework
    # can supply. The defaults suit a plain Ruby host — reported errors go to
    # stderr, and `cache:` props refuse to run until the host names a store.
    class Host
      def cache_store
        raise NotImplementedError,
              '`cache:` props need a cache store. Override ' \
              "`#{self.class}#cache_store` on the host."
      end

      def expand_cache_key(_key)
        raise NotImplementedError,
              '`cache:` props need a cache key scheme. Override ' \
              "`#{self.class}#expand_cache_key` on the host."
      end

      # A handled error: a `rescue: true` prop's failure (`prop:` names its
      # path), an SSR render that fell back to the client (`ssr: true`).
      def report_error(error, **context)
        detail = context.map { |key, value| "#{key}=#{value}" }.join(' ')
        warn("[inertia-core] #{error.class}: #{error.message}#{" (#{detail})" unless detail.empty?}")
      end

      # The boundary `rescue:` widens to, and the one a cached value crosses
      # before storage: what survives here survives the response.
      def serialize(value)
        return value.as_json if value.respond_to?(:as_json)

        JSON.parse(JSON.generate(value))
      end

      # Core emits `:cache_fetch` (`key:`, with `hit:` settling inside the
      # block) and `:ssr` (`url:`, `component:`). Call the block with the
      # payload hash.
      def instrument(_event, payload = {})
        yield(payload)
      end

      # The dev server the framework integration runs (Vite's, say): SSR
      # renders through its `/__inertia_ssr` endpoint, uncached.
      def dev_server_url
        nil
      end
    end
  end
end
