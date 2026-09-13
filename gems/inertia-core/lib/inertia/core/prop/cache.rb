# frozen_string_literal: true

module Inertia
  module Core
    class Prop
      # Where a `cache:` prop's value is stored: the key the host expands and
      # the options it hands the store. A Hash spells both out; anything else
      # is the key on its own.
      class Cache
        attr_reader :key, :options

        def self.build(spec)
          spec.nil? || spec == false ? nil : new(spec)
        end

        def initialize(spec)
          if spec.is_a?(::Hash)
            @key = spec[:key] || raise(ArgumentError, '`cache:` as a Hash requires a :key.')
            @options = spec.except(:key)
          else
            @key = spec
            @options = {}
          end
        end
      end
    end
  end
end
