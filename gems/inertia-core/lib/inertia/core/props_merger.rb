# frozen_string_literal: true

module Inertia
  module Core
    # Shared props and a render's own props into one hash. A key written as a
    # String and as a Symbol is one prop to the client, so both spellings
    # canonicalize to the Symbol before the two hashes meet. A dotted key stays
    # a String: that is how dot notation is spelled.
    module PropsMerger
      module_function

      def merge(shared, props, deep: false)
        return canonical(shared).merge(canonical(props)) unless deep

        deep_merge(canonical(shared, deep: true), canonical(props, deep: true))
      end

      def canonical(hash, deep: false)
        hash.to_h do |key, value|
          value = canonical(value, deep: true) if deep && plain_hash?(value)
          [canonical_key(key), value]
        end
      end

      def canonical_key(key)
        key.is_a?(String) && !key.include?('.') ? key.to_sym : key
      end

      def deep_merge(left, right)
        left.merge(right) do |_key, ours, theirs|
          plain_hash?(ours) && plain_hash?(theirs) ? deep_merge(ours, theirs) : theirs
        end
      end

      # A serializer, or a container that decides its own JSON, is left alone —
      # keys and all.
      def plain_hash?(value)
        value.is_a?(::Hash) && Container.plain?(value)
      end
    end
  end
end
