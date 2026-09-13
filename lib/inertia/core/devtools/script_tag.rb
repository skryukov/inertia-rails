# frozen_string_literal: true

require 'json'

module Inertia
  module Core
    module Devtools
      # The discovery tag on an HTML page load: the entry id in a `<script>`
      # the extension reads to pair the page with the entry the server kept.
      # The host decides which responses get one.
      module ScriptTag
        BODY_END = %r{</body\s*>}i
        ESCAPES = { '&' => '&amp;', '"' => '&quot;', '<' => '&lt;', '>' => '&gt;' }.freeze

        module_function

        # A new String; the html handed in is left alone.
        def insert(html, id:, nonce: nil, base_path: nil)
          html.dup.insert(html.rindex(BODY_END) || html.length, build(id, nonce: nonce, base_path: base_path))
        end

        # `base_path` is the prefix the app is mounted under; the extension
        # fetches the entries API beneath it. Left off the tag at the root.
        def build(id, nonce: nil, base_path: nil)
          attributes = +'data-inertia-devtools-id="" type="application/json"'
          attributes << %( data-inertia-devtools-base-path="#{escape(base_path)}") unless base_path.to_s.empty?
          attributes << %( nonce="#{escape(nonce)}") if nonce

          %(<script #{attributes}>#{Protocol.script_json(JSON.generate(id))}</script>)
        end

        # The id and nonce are the server's own, but they land in markup.
        def escape(value)
          value.to_s.gsub(/[&"<>]/, ESCAPES)
        end
      end
    end
  end
end
