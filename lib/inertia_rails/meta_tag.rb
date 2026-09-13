# frozen_string_literal: true

module InertiaRails
  class MetaTag < Inertia::Core::MetaTag
    # The markup is the core's; `tag_helper` stays for callers of the old
    # signature. The attribute falls back to the global configuration — pass
    # it to honor per-controller settings.
    def to_tag(_tag_helper = nil, inertia_attribute: nil)
      to_html(inertia_attribute: inertia_attribute || InertiaRails.configuration.head_attribute).html_safe
    end
  end
end
