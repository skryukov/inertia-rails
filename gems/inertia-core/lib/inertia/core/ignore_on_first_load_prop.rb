# frozen_string_literal: true

module Inertia
  module Core
    # Left out of the first load: its block runs only when a partial reload
    # asks for it by name.
    class IgnoreOnFirstLoadProp < Prop
      def self.preset
        :optional
      end
    end
  end
end
