# frozen_string_literal: true

module Inertia
  module Core
    # What may be done with a Hash or an Array. One that decides its own JSON,
    # or answers `to_inertia`, is not one to rebuild: a copy drops what it
    # decided and publishes its raw contents in place of it.
    module Container
      module_function

      def container?(value)
        value.is_a?(::Hash) || value.is_a?(::Array)
      end

      # One whose class or singleton answers `as_json` itself. The base's own
      # (ActiveSupport puts one on `Hash` and `Array`) is inherited, so a bare
      # subclass sends what its base would; plain Ruby gives the base none,
      # so there any answer is the value's own.
      def opaque?(value)
        base = base_of(value)
        return false unless base && value.respond_to?(:as_json)

        value.method(:as_json).owner != as_json_owner(base)
      end

      # The base's, or nil while it has none: the same for every value of a
      # base, so looked up once it exists. A racing write stores the same owner.
      def as_json_owner(base)
        (@as_json_owners ||= {})[base] ||= (base.instance_method(:as_json).owner if base.method_defined?(:as_json))
      end

      # A container the walk may reach into and hand back rebuilt.
      def plain?(value)
        !base_of(value).nil? && !value.respond_to?(:to_inertia) && !opaque?(value)
      end

      # Past the bound it answers true, so a container that contains itself
      # reaches the depth error instead of an endless scan.
      def holds_prop?(value, depth)
        return true if depth.zero? || value.is_a?(Prop)

        case value
        when ::Hash then value.any? { |_key, inner| holds_prop?(inner, depth - 1) }
        when ::Array then value.any? { |inner| holds_prop?(inner, depth - 1) }
        else false
        end
      end

      def base_of(value)
        return ::Hash if value.is_a?(::Hash)

        ::Array if value.is_a?(::Array)
      end
    end
  end
end
