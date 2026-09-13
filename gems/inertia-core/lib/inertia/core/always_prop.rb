# frozen_string_literal: true

module Inertia
  module Core
    # Sent on every request. A partial reload that leaves out its own path is
    # overruled and the value ships whole; a reload that names paths inside it
    # (`only: ['user.name']`, `except: ['user.email']`) is still honoured there.
    class AlwaysProp < Prop
      def self.preset
        :always
      end
    end
  end
end
