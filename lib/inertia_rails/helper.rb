# frozen_string_literal: true

module InertiaRails
  module Helper
    def inertia_ssr_head
      controller.instance_variable_get('@_inertia_ssr_head')
    end

    def inertia_headers
      InertiaRails.deprecator.warn(
        '`inertia_headers` is deprecated and will be removed in InertiaRails 4.0, use `inertia_ssr_head` instead.'
      )
      inertia_ssr_head
    end

    def inertia_rendering?
      controller.instance_variable_get('@_inertia_rendering')
    end

    def inertia_page
      controller.instance_variable_get('@_inertia_page')
    end

    # Under `server_head` the prop holds the markup the render printed, so it
    # is trusted; any other string is escaped like any view value.
    def inertia_meta_tags
      config = controller.send(:inertia_configuration)
      meta_tag_data = (inertia_page || {}).dig(:props, config.meta_prop) || []

      meta_tags = meta_tag_data.map do |meta_tag|
        if meta_tag.is_a?(String)
          config.server_head ? meta_tag.html_safe : meta_tag
        else
          meta_tag.to_html(inertia_attribute: config.head_attribute).html_safe
        end
      end

      safe_join(meta_tags, "\n")
    end

    def inertia_root(id: nil, page: inertia_page)
      config = controller.send(:inertia_configuration)
      nonce = content_security_policy_nonce if respond_to?(:content_security_policy_nonce, true)

      Inertia::Core::Protocol.root_element(
        page, id: id || config.root_dom_id, script: config.use_script_element_for_initial_page, nonce: nonce.presence
      ).html_safe
    end
  end
end
