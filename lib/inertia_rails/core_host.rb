# frozen_string_literal: true

module InertiaRails
  # Wires Inertia::Core to Rails. Built with a configuration, so a controller's
  # `inertia_config(cache_store:)` can reach cached props and SSR alike.
  class CoreHost < Inertia::Core::Host
    def initialize(configuration = nil)
      super()
      @configuration = configuration
    end

    def cache_store
      InertiaRails.cache_store(@configuration || InertiaRails.configuration)
    end

    def expand_cache_key(key)
      "inertia_rails/#{ActiveSupport::Cache.expand_cache_key(key)}"
    end

    def instrument(event, payload = {}, &block)
      ActiveSupport::Notifications.instrument("#{event}.inertia_rails", payload, &block)
    end

    def dev_server_url
      InertiaRails::SSR.vite_dev_server_url
    end

    # Rails < 7.0 has no Error Reporter, so log instead of losing the error.
    def report_error(error, **context)
      Rails.logger&.error("[inertia-rails] SSR render failed: #{error.message}") if context[:ssr]

      if Rails.respond_to?(:error)
        Rails.error.report(error, handled: true, context: context)
      elsif !context[:ssr]
        Rails.logger&.error("[inertia-rails] Rescued deferred prop error: #{error.class}: #{error.message}")
      end
    end
  end
end
