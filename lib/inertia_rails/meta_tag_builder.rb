# frozen_string_literal: true

module InertiaRails
  class MetaTagBuilder < Inertia::Core::MetaTagBuilder
    def initialize
      super(tag_class: InertiaRails::MetaTag)
    end
  end
end
