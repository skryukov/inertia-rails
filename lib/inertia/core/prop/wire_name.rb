# frozen_string_literal: true

module Inertia
  module Core
    class Prop
      # Paths, keys, groups and wrappers all end up as JSON keys or as entries
      # in a comma-separated header, so they are all the same kind of name.
      module WireName
        module_function

        # The name is copied: an announcement keeps what it was built with, even
        # when the caller goes on mutating the String it passed.
        def check!(option, value)
          name = value.to_s.dup.freeze if value.is_a?(String) || value.is_a?(Symbol)
          return name unless name.nil? || name.empty?

          raise ArgumentError, "`#{option}:` entries must be non-empty strings — got #{value.inspect}."
        end
      end
    end
  end
end
