# frozen_string_literal: true

module Inertia
  module Core
    # A prop key: the value written at it, plus the dotted keys written
    # underneath it. `'user.name' => 'Jon'` is a branch of the `user` slot, so
    # whatever `user` resolves to gets `name` grafted on afterwards — however
    # the two were ordered in the props hash.
    class Slot
      MISSING = Object.new.freeze

      # Expands a props hash into slots. Only a String key carries dot notation;
      # a Symbol is the literal path the client addresses.
      def self.tree(props)
        props.each_with_object({}) do |(key, value), slots|
          segments = key.is_a?(String) ? key.split('.').map(&:to_sym) : [key]
          branches = slots
          slot = nil
          segments.each do |segment|
            slot = (branches[segment] ||= new)
            branches = slot.branches
          end
          slot.write(value, key)
        end
      end

      attr_reader :value, :branches

      def initialize
        @value = MISSING
        @branches = {}
      end

      # `'user'` and `:user` are one path the client addresses; two values for
      # it would take turns winning.
      def write(value, key)
        raise ResolutionError, "Props #{@key.inspect} and #{key.inspect} name the same path; keep one." if value?

        @value = value
        @key = key
      end

      def value?
        !@value.equal?(MISSING)
      end

      def branches?
        !@branches.empty?
      end
    end
  end
end
