# frozen_string_literal: true

# stdlib
require 'json'

# the framework-agnostic core
require_relative 'inertia/core'
require_relative 'inertia_rails/core_aliases'

# modules
require_relative 'inertia_rails/version'
require_relative 'inertia_rails/configuration'
require_relative 'inertia_rails/core_host'
require_relative 'inertia_rails/current'
require_relative 'inertia_rails/errors'

# rails-side props
require_relative 'inertia_rails/lazy_prop'

# pagination adapters for scroll props: they belong to the gems that define
# the pagination objects, so the core ships none of them
require_relative 'inertia_rails/scroll_adapters/kaminari_adapter'
require_relative 'inertia_rails/scroll_adapters/pagy_adapter'
Inertia::Core::ScrollMetadata.register_adapter(InertiaRails::ScrollAdapters::PagyAdapter)
Inertia::Core::ScrollMetadata.register_adapter(InertiaRails::ScrollAdapters::KaminariAdapter)

# ssr
require_relative 'inertia_rails/ssr'

# rendering
require_relative 'inertia_rails/meta_tag'
require_relative 'inertia_rails/meta_tag_builder'
require_relative 'inertia_rails/renderer'

# rails integration
require_relative 'inertia_rails/flash_extension'
require_relative 'inertia_rails/helper'
require_relative 'inertia_rails/precognition_response'
require_relative 'inertia_rails/precognition'
require_relative 'inertia_rails/xsrf_cookie_refresh_policy'
require_relative 'inertia_rails/controller'
require_relative 'inertia_rails/protocol_request'
require_relative 'inertia_rails/middleware'
require_relative 'inertia_rails/engine'

module InertiaRails
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.default
    end

    # The core's view of Rails: one per process, handed to every resolution.
    def host
      @host ||= CoreHost.new
    end

    # The store a configuration names, `Rails.cache` by default. A render
    # passes its own, so `inertia_config(cache_store:)` reaches cached props.
    def cache_store(configuration = self.configuration)
      configuration.cache_store
    end

    def deprecator # :nodoc:
      @deprecator ||= ActiveSupport::Deprecation.new
    end

    def lazy(value = nil, &block)
      LazyProp.new(value, &block)
    end

    def optional(...)
      OptionalProp.new(...)
    end

    def always(...)
      AlwaysProp.new(...)
    end

    def once(...)
      OnceProp.new(...)
    end

    def merge(...)
      MergeProp.new(...)
    end

    def deep_merge(match_on: nil, &block)
      MergeProp.new(deep_merge: true, match_on: match_on, &block)
    end

    def cache(...)
      CachedProp.new(...)
    end

    def defer(...)
      DeferProp.new(...)
    end

    def scroll(metadata = nil, **options, &block)
      ScrollProp.new(metadata: metadata, **options, &block)
    end

    def live(...)
      LiveProp.new(...)
    end

    # The `__inertia` envelope a broadcast carries so the client writes the
    # props straight into the page instead of reloading them. Blocks run in
    # `context` (a controller-like object) when given.
    def broadcast_props(props, context: Object.new)
      Inertia::Core::Broadcast.props(props, evaluator: PropEvaluator.new(context, host: host))
    end
  end
end
