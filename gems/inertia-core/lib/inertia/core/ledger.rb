# frozen_string_literal: true

module Inertia
  module Core
    # The record of one walk: every prop it met with the verdict it was given,
    # in the order it met them, and every error a `rescue:` prop swallowed.
    # Only the walk writes it; the page metadata and DevTools read it once the
    # walk is done.
    class Ledger
      include Enumerable

      attr_reader :rescues

      def initialize
        @entries = []
        @rescues = []
      end

      EMPTY = new.freeze

      def met(path, prop, verdict, reset: false)
        entry = Entry.new(path, prop, verdict, reset: reset)
        @entries << entry
        entry
      end

      def rescued(path, prop, error)
        @rescues << Entry.new(path, prop, :rescued, error: error)
      end

      def each(&block)
        @entries.each(&block)
      end

      def rescued?(path)
        @rescues.any? { |entry| entry.path == path }
      end
    end
  end
end
