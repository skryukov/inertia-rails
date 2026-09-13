# frozen_string_literal: true

module Inertia
  module Core
    # The page object the client receives: the envelope every adapter builds the
    # same way, the resolver's metadata, and an adapter's own `extensions`.
    class Page
      def initialize(component:, props:, url:, version: nil, encrypt_history: false, clear_history: false,
                     flash: nil, shared_keys: nil, preserve_fragment: false, metadata: {}, extensions: {})
        @component = component
        @props = props
        @url = url
        @version = version
        @encrypt_history = encrypt_history
        @clear_history = clear_history
        @flash = flash
        @shared_keys = shared_keys
        @preserve_fragment = preserve_fragment
        @metadata = metadata
        @extensions = extensions
      end

      def to_h
        page = {
          component: @component,
          props: @props,
          url: @url,
          version: @version,
          encryptHistory: @encrypt_history,
          clearHistory: @clear_history,
        }
        page[:flash] = @flash if @flash && !@flash.empty?
        page[:sharedProps] = @shared_keys if @shared_keys && !@shared_keys.empty?
        page[:preserveFragment] = true if @preserve_fragment
        page.merge!(@metadata)
        refuse_collisions!(page)
        page.merge!(@extensions)
      end

      private

      # An extension naming an envelope or metadata key would replace what the
      # client reads there.
      def refuse_collisions!(page)
        taken = @extensions.keys & page.keys
        return if taken.empty?

        raise ResolutionError,
              "Page extension key(s) #{taken.join(', ')} already belong to the page object. " \
              'Nest what the extension adds under a key of its own.'
      end
    end
  end
end
