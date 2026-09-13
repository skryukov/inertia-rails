# frozen_string_literal: true

module Inertia
  module Core
    # Where the walk is: the key under its parent, how deep it has nested, the
    # reload filter in force here, and whether this position is an array slot
    # or sits inside a cached value. Immutable — every move makes a new one.
    class Cursor
      attr_reader :depth, :reload

      class << self
        def root(reload)
          new(nil, nil, reload, in_array: false, cached: false)
        end

        # A cached value is resolved once for every visit, so no filter applies
        # and paths are counted from inside it.
        def cached
          new(nil, nil, Reload::NONE, in_array: false, cached: true)
        end
      end

      def initialize(parent, key, reload, in_array:, cached:)
        @parent = parent
        @key = key
        @depth = parent ? parent.depth + 1 : 0
        @reload = reload
        @in_array = in_array
        @cached = cached
      end

      def at(key, in_array: false)
        Cursor.new(self, key, @reload, in_array: in_array, cached: @cached)
      end

      # Spelled only when something asks — an error, an announcement, a partial
      # reload — so a full load never builds one.
      def path
        @path ||= if @parent.nil? then ''
                  elsif @parent.path.empty? then key_name
                  else "#{@parent.path}.#{key_name}"
                  end
      end

      # What an `always` prop won: the visit excluded this path, so nothing it
      # says about the paths below applies either.
      def unfiltered
        Cursor.new(@parent, @key, Reload::NONE, in_array: @in_array, cached: @cached)
      end

      # Asked more than once at a position — by the walk, by the prop met
      # there, by an array's placeholder — and answered once.
      def excludes?
        return @excludes unless @excludes.nil?

        @excludes = !@reload.empty? && @reload.excludes?(path)
      end

      def names_below?
        !@reload.empty? && @reload.names_below?(path)
      end

      def in_array?
        @in_array
      end

      def cached?
        @cached
      end

      private

      def key_name
        @key.is_a?(Symbol) ? @key.name : @key.to_s
      end
    end
  end
end
