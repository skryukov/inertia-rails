# frozen_string_literal: true

module InertiaRails
  # The core knobs plus the Rails-only ones; a callable value is evaluated inside
  # the bound controller.
  class Configuration < Inertia::Core::Configuration
    DEFAULT_SSR_URL = Inertia::Core::SSR::Client::DEFAULT_URL
    XSRF_COOKIE_REFRESH_OPTIONS = Inertia::Core::XsrfCookie::REFRESH_POLICIES

    # Overrides Rails default rendering behavior to render using Inertia by default.
    option :default_render, false

    # DEPRECATED: Let Rails decide which layout should be used based on the
    # controller configuration.
    option :layout, true

    # Allows configuring the base controller for StaticController.
    option :parent_controller, '::ApplicationController'

    # Flash keys from Rails flash to expose to frontend.
    # Set to nil to disable Rails flash integration (use only flash.inertia).
    option :flash_keys, %i[notice alert].freeze

    # Whether to prevent database writes during precognition requests.
    # When enabled, any ActiveRecord write during a precognition request
    # will raise ActiveRecord::ReadOnlyError.
    option :precognition_prevent_writes, false

    # Cache store for prop-level caching and SSR response caching; `Rails.cache` when nil.
    option :cache_store, nil, evaluate: false

    DEFAULTS = options.freeze
    OPTION_NAMES = option_names.freeze

    def initialize(controller: nil, context: controller, **attrs)
      super(context: context, **attrs)
    end

    def bind_controller(controller)
      bind(controller)
    end

    def cache_store
      super || Rails.cache
    end

    protected

    def controller
      context
    end
  end
end
