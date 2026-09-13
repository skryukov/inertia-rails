# frozen_string_literal: true

module InertiaRails
  # Halts the action with the precognition answer: `precognition!` raises it,
  # the controller's `rescue_from` renders it.
  class PrecognitionResponse < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super('Precognition response')
    end
  end
end
