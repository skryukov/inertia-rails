# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # The outermost DevTools frame, mounted above the framework's exception
      # handling: a request that raised gets its entry finished here, with the
      # response the framework rendered for the exception.
      class Middleware
        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, body = @app.call(env)
          recorder = env[Recorder::ENV_KEY]

          return [status, headers, body] unless recorder&.exception

          recorder.finish(status, headers, body, error: recorder.exception)
        end
      end
    end
  end
end
