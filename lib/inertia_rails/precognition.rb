# frozen_string_literal: true

module InertiaRails
  module Precognition
    # Filtered errors for a precognition request, nil otherwise.
    def self.validate(model_or_errors)
      request = Current.request
      return unless request

      Inertia::Core::Precognition.validate(request.env, model_or_errors)
    end
  end

  def self.precognition!(model_or_errors)
    errors = Precognition.validate(model_or_errors)
    return false if errors.nil?

    raise PrecognitionResponse, errors, []
  end
end
