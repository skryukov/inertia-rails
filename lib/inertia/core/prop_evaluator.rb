# frozen_string_literal: true

module Inertia
  module Core
    # The environment a resolution runs in: the context prop blocks run inside
    # (the controller, in Rails) and the host the framework wired.
    class PropEvaluator
      attr_reader :host

      def initialize(context, host:)
        @context = context
        @host = host
      end

      def run(block, *args)
        @context.instance_exec(*args, &block)
      end
    end
  end
end
