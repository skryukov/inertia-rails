# frozen_string_literal: true

module Inertia
  module Core
    # The client remembers the value under a key and sends the key back, so the
    # server can leave the prop out of every later response.
    class OnceProp < Prop
      def self.preset
        :once
      end
    end
  end
end
