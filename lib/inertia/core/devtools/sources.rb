# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # Where the extension's editor links come from. Reading an app's source
      # is the host's business, so this links nothing and a host subclasses.
      class Sources
        # The page file behind a component name, absolute.
        def component_path(_component)
          nil
        end

        # The line a prop key sits on, at or below `line` in `file`.
        def prop_line(_file, _line, _key)
          nil
        end

        NULL = new.freeze
      end
    end
  end
end
