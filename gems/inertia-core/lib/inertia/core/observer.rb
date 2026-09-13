# frozen_string_literal: true

module Inertia
  module Core
    # Reads the ledger once the walk is done. DevTools is one; it can see
    # every verdict and every rescue, and alter none of them.
    class Observer
      def walked(ledger); end

      NULL = new.freeze
    end
  end
end
