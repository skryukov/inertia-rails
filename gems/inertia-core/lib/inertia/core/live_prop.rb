# frozen_string_literal: true

module Inertia
  module Core
    # The page announces the channels and events that carry a new value, so the
    # server can push one instead of waiting to be asked.
    class LiveProp < Prop
      def self.preset
        :live
      end

      def initialize(on: nil, channel: nil, throttle: nil, **options, &block)
        super(live: { on: on, channel: channel, throttle: throttle }, **options, &block)
      end
    end
  end
end
