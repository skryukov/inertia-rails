# frozen_string_literal: true

module Inertia
  module Core
    # What a partial reload asked for, as one question: is this path excluded?
    # `only` and `except` hold dotted paths. A path survives `only` when it, an
    # ancestor or a descendant was named — the walk has to pass through a
    # container to reach what sits below it.
    class Reload
      # Each name with the prefix its descendants start with, spelled once.
      def initialize(only: [], except: [])
        @only = only.map { |named| [named, "#{named}."] }
        @except = except.map { |named| [named, "#{named}."] }
      end

      # A full load, or the subtree an `always` prop won.
      NONE = new.freeze

      def empty?
        @only.empty? && @except.empty?
      end

      def excludes?(path)
        return true if covers?(@except, path)
        return false if @only.empty?

        !covers?(@only, path) && !names_under?(@only, "#{path}.")
      end

      # Whether `only` names this path, an ancestor (`user` brings
      # `user.avatar`) or a descendant (`user.avatar` is reached through `user`).
      def asks_for?(path)
        covers?(@only, path) || names_under?(@only, "#{path}.")
      end

      # Whether `only` or `except` names a path under this one.
      def names_below?(path)
        below = "#{path}."
        names_under?(@only, below) || names_under?(@except, below)
      end

      private

      # The path is one of the names, or sits under one.
      def covers?(names, path)
        names.any? { |named, below| named == path || path.start_with?(below) }
      end

      def names_under?(names, below)
        names.any? { |named, _| named.start_with?(below) }
      end
    end
  end
end
