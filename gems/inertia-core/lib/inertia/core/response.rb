# frozen_string_literal: true

module Inertia
  module Core
    # One render for one request: the page, in the form the client asked for.
    # An Inertia request gets the page as JSON; a first load gets the markup
    # the client boots from, server-rendered when SSR is on and answers. The
    # page resolves once, on first use, so a host reads what it needs in any
    # order.
    class Response
      JSON_CONTENT_TYPE = 'application/json'
      HTML_CONTENT_TYPE = 'text/html'

      attr_reader :component

      def initialize(component, props, env:, configuration:, evaluator:, url: nil, head: MetaTagBuilder.new,
                     flash: nil, shared_keys: nil, encrypt_history: nil, clear_history: false,
                     preserve_fragment: false, ssr_cache: nil, observer: Observer::NULL, eager: false)
        @component = component
        @props = props
        @env = env
        @configuration = configuration
        @evaluator = evaluator
        @url = url
        @head = head
        @flash = flash
        @shared_keys = shared_keys
        @encrypt_history = encrypt_history.nil? ? configuration.encrypt_history : encrypt_history
        @clear_history = clear_history
        @preserve_fragment = preserve_fragment
        @ssr_cache = ssr_cache
        @observer = observer
        @eager = eager
      end

      def json?
        request.inertia?
      end

      def partial?
        visit.partial?
      end

      def content_type
        json? ? JSON_CONTENT_TYPE : HTML_CONTENT_TYPE
      end

      # The headers a host adds to its response; `vary` is what it already sends.
      def headers(vary = nil)
        headers = { Rack.header_name('Vary') => Protocol.vary(vary) }
        headers[Rack.header_name(Protocol::HEADER)] = 'true' if json?
        headers
      end

      def page
        @page ||= build_page
      end

      def metadata
        page
        @metadata
      end

      def json
        @json ||= page.to_json
      end

      def ssr?
        !ssr.nil?
      end

      # What the SSR server adds to `<head>`, joined; nil without SSR.
      def head
        ssr && ssr['head'].join
      end

      # The markup a first load boots from: the server-rendered body, or the
      # root element the client mounts into.
      def html(nonce: nil)
        return ssr['body'] if ssr

        Protocol.root_element(page, id: @configuration.root_dom_id,
                                    script: @configuration.use_script_element_for_initial_page, nonce: nonce)
      end

      private

      def request
        @request ||= Rack::Request.new(@env)
      end

      def visit
        @visit ||= Visit.from_env(@env, component: @component)
      end

      def host
        @evaluator.host
      end

      def ssr
        return @ssr if defined?(@ssr)

        @ssr = @configuration.ssr_enabled && !json? ? render_ssr : nil
      end

      def render_ssr
        SSR::Client.new(@configuration, page: page, host: host, cache: @ssr_cache).render
      end

      def build_page
        refuse_head_prop!
        resolved, @metadata = resolve_props
        resolved = @configuration.prop_transformer(props: resolved)
        add_head!(resolved)

        Page.new(
          component: @component, props: resolved, url: @url || request.fullpath, version: @configuration.version,
          encrypt_history: @encrypt_history, clear_history: @clear_history, flash: @flash,
          shared_keys: @shared_keys, preserve_fragment: @preserve_fragment, metadata: @metadata
        ).to_h
      end

      # The span where prop blocks run — nothing else.
      def resolve_props
        host.instrument(:resolve_props, component: @component, partial: partial?) do
          PropsResolver.new(props, evaluator: @evaluator, visit: visit, observer: @observer, eager: @eager).resolve
        end
      end

      # Validation errors ride along on every reload, partial ones included.
      def props
        errors = @props[:errors]
        return @props unless @props.key?(:errors) && !errors.is_a?(Prop)

        @props.merge(errors: AlwaysProp.new { errors })
      end

      def refuse_head_prop!
        return unless @configuration.server_head

        prop = @configuration.meta_prop
        return unless @props.key?(prop)

        raise Error, "The `#{prop}` prop is reserved by `config.server_head`. " \
                     'Rename the conflicting prop, or set `config.server_head` to a custom prop name.'
      end

      # After the prop transformer, which never sees the head.
      def add_head!(props)
        apply_title_template
        tags = @head.meta_tags
        return if tags.empty?

        props[@configuration.meta_prop] = @configuration.server_head ? head_html(tags) : tags
      end

      def head_html(tags)
        attribute = @configuration.head_attribute
        tags.map { |tag| tag.to_html(inertia_attribute: attribute) }
      end

      def apply_title_template
        return unless (template = @configuration.meta_title_template)

        title = @evaluator.run(template, @head.title)
        @head.add(title: title) unless title.nil? || title.to_s.strip.empty?
      end
    end
  end
end
