# frozen_string_literal: true

module Inertia
  module Core
    # The knobs an application sets, as opposed to the behaviour a host supplies
    # (see Host). A callable value is evaluated at read time inside the bound
    # context, so `version: -> { assets_hash }` sees the request.
    class Configuration
      ENV_PREFIX = 'INERTIA_'
      TRUTHY_ENV = %w[true 1 yes on].freeze
      FALSEY_ENV = %w[false 0 no off].freeze

      class << self
        def options
          @options ||= superclass.respond_to?(:options) ? superclass.options.dup : {}
        end

        def option_names
          options.keys
        end

        # The accessors live in a module of their own, so a class may redefine
        # a reader and reach the generated one through `super`.
        def option(name, default = nil, evaluate: true)
          options[name] = default
          accessors.define_method(name) { evaluate ? evaluate_option(raw(name)) : raw(name) }
          accessors.define_method(:"#{name}=") { |value| @options[name] = value }
        end

        # The defaults overlaid with `INERTIA_<OPTION>` environment values.
        def default(env = ENV)
          new(**options, **env_options(env))
        end

        private

        def accessors
          @accessors ||= Module.new.tap { |accessors| include accessors }
        end

        def env_options(env)
          option_names.each_with_object({}) do |key, hash|
            value = env.fetch("#{ENV_PREFIX}#{key.to_s.upcase}", nil)
            next if value.nil?

            hash[key] = coerce_env(value, options[key])
          end
        end

        # Environment values arrive as strings; the declared default says what
        # the option means, so a boolean one reads `0` and `off` as false.
        def coerce_env(value, default)
          case default
          when true, false then boolean_env(value)
          when Integer then Integer(value, exception: false) || value
          when Float then Float(value, exception: false) || value
          else %w[true false].include?(value) ? value == 'true' : value
          end
        end

        def boolean_env(value)
          return true if TRUTHY_ENV.include?(value.downcase)
          return false if FALSEY_ENV.include?(value.downcase)

          value
        end
      end

      # Whether to combine hashes with the same keys instead of replacing them.
      option :deep_merge_shared_data, false

      # Resolves the component name of a render that names none.
      option :component_path_resolver, ->(path:, action:) { "#{path}/#{action}" }

      # Transforms the resolved props before they are sent to the client.
      option :prop_transformer, ->(props:) { props }

      # Whether to encrypt the history state in the client.
      option :encrypt_history, false

      # SSR options.
      option :ssr_enabled, false
      # URL of the SSR server. When nil, the host's default applies.
      option :ssr_url, nil
      option :ssr_raise_on_error, false
      # Called with (error, page) on an SSR failure, so it is not evaluated when read.
      option :on_ssr_error, nil, evaluate: false
      # Path(s) checked before attempting SSR; nil skips bundle detection.
      option :ssr_bundle, nil
      # true, false/nil, or a Hash of cache store fetch options.
      option :ssr_cache, nil
      # JavaScript runtime used to run the SSR bundle (e.g. "node", "bun", "deno").
      option :ssr_runtime, nil

      # Used to detect version drift between server and client.
      option :version, nil

      # Whether to include an empty `errors` hash in the props when no errors are present.
      option :always_include_errors_hash, nil

      # Whether to convert cross-origin redirects into Inertia location responses.
      option :convert_external_redirects, true

      # Whether the initial page ships in a `<script>` element instead of the `data-page` attribute.
      option :use_script_element_for_initial_page, false

      # DOM id of the root Inertia.js element.
      option :root_dom_id, 'app'

      # Whether to include shared prop keys in the page response metadata.
      option :expose_shared_prop_keys, true

      # Whether head tags are marked `data-inertia` instead of `inertia`.
      option :use_data_inertia_head_attribute, false

      # Whether head tags ship as HTML strings for the client's `serverHead`
      # option (Inertia.js v3.5+). A String sets a custom prop name.
      option :server_head, false

      # Callable applied to the page `<title>`: receives the current title (nil
      # when none is set) and returns the full one, so it can also supply a
      # default. The render calls it, so it is not evaluated when read.
      option :meta_title_template, nil, evaluate: false

      # When a protected response rewrites the XSRF-TOKEN cookie: `:always`,
      # or `:lazy` (only when the one the request carried no longer validates).
      option :xsrf_cookie_refresh, :always

      protected attr_reader :context
      protected attr_reader :options

      def initialize(context: nil, **attrs)
        @context = context
        @options = attrs.slice(*self.class.option_names)
        unknown = attrs.keys - self.class.option_names
        return if unknown.empty?

        raise ArgumentError, "Unknown options for #{self.class}: #{unknown}"
      end

      # The same options, evaluated inside `context` from now on.
      def bind(context)
        self.class.new(**@options, context: context)
      end

      def freeze
        @options.freeze
        super
      end

      def merge!(config)
        @options.merge!(config.options)
        self
      end

      def merge(config)
        self.class.new(**@options, **config.options)
      end

      # Internal: finalizes a layered configuration against its parent.
      def with_defaults(config)
        @options = config.options.merge(@options)
        freeze
      end

      def component_path_resolver(path:, action:)
        raw(:component_path_resolver).call(path: path, action: action)
      end

      def prop_transformer(props:)
        raw(:prop_transformer).call(props: props)
      end

      # Inertia.js v3's `serverHead` only recognizes `data-inertia`.
      def head_attribute
        server_head || use_data_inertia_head_attribute ? :'data-inertia' : :inertia
      end

      # `head` is the prop the client reads for `serverHead: true`.
      def meta_prop
        value = server_head
        return :_inertia_meta unless value

        value == true ? :head : value.to_sym
      end

      def meta_title_template
        value = super
        return value if value.nil? || value.respond_to?(:call)

        raise ArgumentError, "meta_title_template must be callable, got #{value.inspect}"
      end

      # Normalized and validated at read time: ENV values arrive as strings,
      # and callables are only evaluated here.
      def xsrf_cookie_refresh
        value = super
        value = value.to_sym if value.respond_to?(:to_sym)
        return value if XsrfCookie::REFRESH_POLICIES.include?(value)

        raise ArgumentError, "Invalid xsrf_cookie_refresh: #{value.inspect}. " \
                             "Expected one of: #{XsrfCookie::REFRESH_POLICIES.map(&:inspect).join(', ')}"
      end

      private

      # The value set here, or the declared default. Options stay sparse so
      # layering (`with_defaults`) only carries what was set.
      def raw(name)
        @options.key?(name) ? @options[name] : self.class.options[name]
      end

      def evaluate_option(value)
        return value unless value.respond_to?(:call)
        return value.call unless context

        context.instance_exec(&value)
      end
    end
  end
end
