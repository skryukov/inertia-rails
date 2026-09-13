# frozen_string_literal: true

module Inertia
  module Core
    # One request, as the props layer needs to see it: which paths it asked for,
    # which `once` keys the client already holds, which way it is scrolling.
    class Visit
      PARTIAL_COMPONENT = 'X-Inertia-Partial-Component'
      ONLY = 'X-Inertia-Partial-Data'
      EXCEPT = 'X-Inertia-Partial-Except'
      RESET = 'X-Inertia-Reset'
      EXCEPT_ONCE = 'X-Inertia-Except-Once-Props'
      SCROLL_INTENT = 'X-Inertia-Infinite-Scroll-Merge-Intent'

      # Rack spells headers into `env`; the protocol names them the HTTP way.
      class EnvHeaders
        def initialize(env)
          @env = env
        end

        def [](name)
          @env["HTTP_#{name.upcase.tr('-', '_')}"]
        end
      end

      class << self
        # A partial reload only applies to the component it was asked of.
        def from_headers(headers, component:)
          new(
            partial: headers[PARTIAL_COMPONENT] == component,
            only: list(headers[ONLY]),
            except: list(headers[EXCEPT]),
            reset: list(headers[RESET]),
            except_once: list(headers[EXCEPT_ONCE]),
            scroll_intent: headers[SCROLL_INTENT]
          )
        end

        def from_env(env, component:)
          from_headers(EnvHeaders.new(env), component: component)
        end

        private

        def list(value)
          value.to_s.split(',').map(&:strip).reject(&:empty?)
        end
      end

      attr_reader :scroll_intent, :reload

      def initialize(options = {})
        @partial = options[:partial] ? true : false
        @only = paths(options[:only])
        @reset = paths(options[:reset])
        @except_once = paths(options[:except_once])
        @scroll_intent = options[:scroll_intent]
        @reload = @partial ? Reload.new(only: @only, except: paths(options[:except])) : Reload::NONE
      end

      def partial?
        @partial
      end

      def reset?(path)
        @reset.include?(path)
      end

      def holds_once?(key)
        @except_once.include?(key)
      end

      # A `once` prop the client already holds ships again when the reload
      # asks for it: by name, through a parent, or for a path inside it.
      def asked_for?(path)
        @reload.asks_for?(path)
      end

      private

      def paths(value)
        Array(value).map(&:to_s)
      end
    end
  end
end
