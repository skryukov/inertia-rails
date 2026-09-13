# frozen_string_literal: true

module InertiaRails
  module Devtools
    # The core store, wired to DevTools' error reporting.
    class EntriesRepository < Inertia::Core::Devtools::EntriesRepository
      protected

      def report(error)
        Devtools.report(error)
      end
    end
  end
end
