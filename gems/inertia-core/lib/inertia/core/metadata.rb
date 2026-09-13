# frozen_string_literal: true

module Inertia
  module Core
    # The second half of the page, derived from the ledger once the walk is
    # done: one contributor per page key, in wire order. Everything is keyed
    # by dotted path, and an empty list never ships.
    module Metadata
      module_function

      def derive(ledger, visit)
        {
          **Prop::Announcements::Defer.contribute(ledger, visit),
          **Prop::Announcements::Merge.contribute(ledger, visit),
          **Prop::Announcements::Once.contribute(ledger, visit),
          **Prop::Announcements::Scroll.contribute(ledger, visit),
          **Prop::Announcements::Live.contribute(ledger, visit),
          rescuedProps: ledger.rescues.map(&:path),
        }.reject { |_key, announced| announced.empty? }
      end
    end
  end
end
