# frozen_string_literal: true

module Inertia
  module Core
    module Rack
      module_function

      # Rack 3 wants lowercase response header names; Rack 2 and Rails accept
      # them as written.
      def header_name(name)
        defined?(::Rack::Headers) ? name.downcase : name
      end
    end
  end
end
