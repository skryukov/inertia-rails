# frozen_string_literal: true

module Inertia
  module Core
    class Prop
      module Announcements
        # `deferredProps`: the groups the client fetches right after the page
        # lands, one request per group.
        class Defer
          DEFAULT_GROUP = 'default'

          # A partial reload is the fetch itself, and a client that already
          # holds the value is not told to fetch it.
          def self.contribute(ledger, visit)
            groups = {}
            unless visit.partial?
              ledger.each do |entry|
                defer = entry.prop.defer
                next unless defer && !entry.silenced? && !entry.held?

                (groups[defer.group] ||= []) << entry.path
              end
            end
            { deferredProps: groups }
          end

          attr_reader :group

          def initialize(group: nil)
            @group = group.nil? ? DEFAULT_GROUP : WireName.check!(:group, group).dup.freeze
          end
        end
      end
    end
  end
end
