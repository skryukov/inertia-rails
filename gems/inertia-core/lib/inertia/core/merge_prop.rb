# frozen_string_literal: true

module Inertia
  module Core
    # The client merges the value into what it already holds instead of
    # replacing it.
    class MergeProp < Prop
      def self.preset
        :merge
      end
    end
  end
end
