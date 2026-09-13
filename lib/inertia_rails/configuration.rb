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

    # DevTools recording: nil records in development only; true/false force it.
    option :devtools, nil
    # Request paths never recorded (`File.fnmatch` strings or regexps).
    option :devtools_except, [].freeze

    option :devtools_storage_path, nil
    option :devtools_ttl, 24
    option :devtools_prune_interval, 300
    option :devtools_limit, 100
    option :devtools_max_entries, 0

    # Read API authorization outside development, and its request logging.
    # The controller runs the callable, so it is not evaluated when read.
    option :devtools_authorize, nil, evaluate: false
    option :devtools_silence_logs, true

    DEFAULTS = options.freeze
    OPTION_NAMES = option_names.freeze

    # Recording runs in middleware and the read API outside any controller,
    # so these are read from the global configuration only.
    GLOBAL_OPTION_NAMES = OPTION_NAMES.select { |name| name.to_s.start_with?('devtools') }.freeze

    def initialize(controller: nil, context: controller, **attrs)
      super(context: context, **attrs)
    end

    def bind_controller(controller)
      bind(controller)
    end

    def cache_store
      super || Rails.cache
    end

    # `nil` (or an empty ENV value) follows the environment; any other value
    # is read as a boolean-ish flag.
    def devtools_enabled?
      value = devtools
      value = value.strip if value.is_a?(String)
      return Rails.env.development? if value.nil? || value == ''

      !%w[false 0 off no].include?(value.to_s.downcase)
    end

    protected

    def controller
      context
    end
  end
end
