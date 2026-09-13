# frozen_string_literal: true

module InertiaRails
  module InertiaRequest
    def inertia?
      key? 'HTTP_X_INERTIA'
    end

    def inertia_partial?
      key?('HTTP_X_INERTIA_PARTIAL_COMPONENT')
    end

    def inertia_precognitive?
      Inertia::Core::Precognition.request?(env)
    end

    def inertia_precognitive_validate_only
      Inertia::Core::Precognition.validate_only(env)
    end
  end
end
