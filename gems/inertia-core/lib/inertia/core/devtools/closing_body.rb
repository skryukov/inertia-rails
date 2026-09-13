# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # Wraps a Rack body so `on_close` runs once the server has closed it —
      # after the bytes went out. Everything else is the body's own, and a
      # `to_ary` closes, as Rack asks of a body that offers both.
      class ClosingBody
        def initialize(body, &on_close)
          @body = body
          @on_close = on_close
          @closed = false
        end

        def each(&block)
          @body.each(&block)
        end

        def close
          return if @closed

          @closed = true
          begin
            @body.close if @body.respond_to?(:close)
          ensure
            @on_close.call
          end
        end

        def respond_to_missing?(name, include_all = false)
          name != :to_str && @body.respond_to?(name, include_all)
        end

        def method_missing(name, ...)
          return super if name == :to_str
          return @body.public_send(name, ...) unless name == :to_ary

          begin
            @body.to_ary(...)
          ensure
            close
          end
        end
      end
    end
  end
end
