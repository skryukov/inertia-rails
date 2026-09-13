# frozen_string_literal: true

module InertiaRails
  # What only Rails knows about a render — shared data, view assigns, the
  # session's history flags, the flash, the layout, the meta DSL — handed to
  # the core's Response, whose answer Rails' `render` writes out.
  class Renderer
    %i[component configuration controller props view_data encrypt_history
       clear_history].each do |method_name|
      define_method(method_name) do
        InertiaRails.deprecator.warn(
          "[DEPRECATION] Accessing `InertiaRails::Renderer##{method_name}` is deprecated and will be removed in v4.0"
        )
        instance_variable_get("@#{method_name}")
      end
    end

    def initialize(component, controller, request, response, render_method, **options)
      if component.is_a?(Hash) && options.key?(:props)
        raise ArgumentError,
              'Parameter `props` is not allowed when passing a Hash as the first argument'
      end

      @controller = controller
      @configuration = controller.__send__(:inertia_configuration)
      @host = CoreHost.new(@configuration)
      @request = request
      @response = response
      @render_method = render_method
      @view_data = options.fetch(:view_data, {})
      @encrypt_history = options.fetch(:encrypt_history, @configuration.encrypt_history)
      @clear_history = options.fetch(:clear_history, controller.session[:inertia_clear_history] || false)
      @preserve_fragment = options.fetch(:preserve_fragment, controller.session[:inertia_preserve_fragment] || false)
      @layout_override = options.fetch(:layout) { @configuration.layout }
      @ssr_cache = options[:ssr_cache]

      deep_merge = options.fetch(:deep_merge, @configuration.deep_merge_shared_data)
      passed_props = options.fetch(:props,
                                   component.is_a?(Hash) ? component : @controller.__send__(:inertia_view_assigns))
      shared = shared_data
      @shared_keys = @configuration.expose_shared_prop_keys ? extract_shared_keys(shared) : nil
      @props = Inertia::Core::PropsMerger.merge(shared, passed_props, deep: deep_merge)

      @component = resolve_component(component)

      @controller.instance_variable_set('@_inertia_rendering', true)
      controller.inertia_meta.add(options[:meta]) if options[:meta]
    end

    def render
      ActiveSupport::Notifications.instrument('render.inertia_rails',
                                              component: @component, partial: inertia.partial?, ssr: false) do |payload|
        @response.headers.merge!(inertia.headers(@response.headers['Vary']))
        if inertia.json?
          @render_method.call json: inertia.json, status: @response.status, content_type: Mime[:json]
        elsif inertia.ssr?
          payload[:ssr] = true
          @controller.instance_variable_set('@_inertia_ssr_head', inertia.head.html_safe)
          @render_method.call(html: inertia.html.html_safe, layout: layout, locals: locals, formats: :html)
        else
          @controller.instance_variable_set('@_inertia_page', page)
          @render_method.call(template: 'inertia', layout: layout, locals: locals, formats: :html)
        end
      end
    end

    private

    def inertia
      @inertia ||= Inertia::Core::Response.new(
        @component, @props,
        env: @request.env,
        configuration: @configuration,
        evaluator: Inertia::Core::PropEvaluator.new(@controller, host: @host),
        url: @request.original_fullpath,
        head: @controller.inertia_meta,
        flash: @controller.__send__(:inertia_collect_flash_data),
        shared_keys: @shared_keys,
        encrypt_history: @encrypt_history,
        clear_history: @clear_history,
        preserve_fragment: @preserve_fragment,
        ssr_cache: @ssr_cache,
        **resolver_options
      )
    end

    def page
      inertia.page
    end

    def locals
      @view_data.merge(page: page)
    end

    # The adapter's say over resolution: the testing helpers turn on `eager:` here.
    def resolver_options
      {}
    end

    def layout
      layout = @layout_override
      layout.nil? || layout
    end

    def shared_data
      @controller.__send__(:inertia_shared_data)
    end

    def extract_shared_keys(shared_props)
      shared_props.keys.map { |key| key.to_s.split('.', 2).first }.uniq
    end

    def resolve_component(component)
      if component == true || component.is_a?(Hash)
        @configuration.component_path_resolver(path: @controller.controller_path, action: @controller.action_name)
      else
        component
      end
    end
  end
end
