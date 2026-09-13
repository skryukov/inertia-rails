# frozen_string_literal: true

module Inertia
  module Core
    class Ledger
      # One prop the walk met: where, which, and what the visit decided — its
      # value ships (`delivered`), the client already holds it (`held`), the
      # first load leaves it out (`omitted`), the partial reload never asked
      # for it (`silenced`) — or one error a `rescue:` prop swallowed there.
      class Entry
        attr_reader :path, :prop, :verdict, :error

        def initialize(path, prop, verdict, reset: false, error: nil)
          @path = path
          @prop = prop
          @verdict = verdict
          @reset = reset
          @error = error
        end

        def delivered?
          @verdict == :delivered
        end

        def held?
          @verdict == :held
        end

        def omitted?
          @verdict == :omitted
        end

        def silenced?
          @verdict == :silenced
        end

        def rescued?
          @verdict == :rescued
        end

        def reset?
          @reset
        end
      end
    end
  end
end
