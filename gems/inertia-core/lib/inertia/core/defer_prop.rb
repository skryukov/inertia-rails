# frozen_string_literal: true

module Inertia
  module Core
    # Left out of the first load, but announced: the client fetches it right
    # after, one request per `group:`.
    class DeferProp < IgnoreOnFirstLoadProp
      DEFAULT_GROUP = Prop::Announcements::Defer::DEFAULT_GROUP

      def self.preset
        :defer
      end
    end
  end
end
