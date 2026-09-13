# frozen_string_literal: true

module InertiaRails
  module Devtools
    # The editor links only Rails can resolve.
    class Sources < Inertia::Core::Devtools::Sources
      def component_path(component)
        ComponentPathLocator.resolve(component)
      end

      def prop_line(file, line, key)
        SourceLocator.prop_key_line(file, line, key)
      end
    end
  end
end
