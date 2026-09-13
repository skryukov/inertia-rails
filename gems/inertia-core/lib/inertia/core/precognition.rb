# frozen_string_literal: true

module Inertia
  module Core
    # The Precognition protocol: a request carrying `Precognition: true` asks
    # for validation only, of the fields `Precognition-Validate-Only` names
    # when it is sent. The answer is 204 with `Precognition-Success` when they
    # pass, 422 with the errors when they do not; both echo `Precognition`.
    module Precognition
      HEADER = 'Precognition'
      SUCCESS_HEADER = 'Precognition-Success'
      VALIDATE_ONLY_HEADER = 'Precognition-Validate-Only'

      ENV_KEY = 'HTTP_PRECOGNITION'
      VALIDATE_ONLY_ENV_KEY = 'HTTP_PRECOGNITION_VALIDATE_ONLY'
      CALLED_KEY = 'inertia.precognition_called'

      class << self
        def request?(env)
          env[ENV_KEY] == 'true'
        end

        def validate_only(env)
          env[VALIDATE_ONLY_ENV_KEY]&.split(',')&.map(&:strip)
        end

        # The errors the answer carries, or nil when the request is not
        # precognitive. Runs once per request, precognitive or not, so the
        # second call surfaces before a precognition request ever arrives.
        def validate(env, model_or_errors)
          once!(env)
          return unless request?(env)

          filter(normalize(model_or_errors), validate_only(env))
        end

        def status(errors)
          errors.empty? ? 204 : 422
        end

        def headers(errors)
          headers = { HEADER => 'true' }
          headers[SUCCESS_HEADER] = 'true' if errors.empty?
          headers
        end

        # nil for a 204.
        def body(errors)
          { errors: errors } unless errors.empty?
        end

        private

        def once!(env)
          raise DoublePrecognitionError if env[CALLED_KEY]

          env[CALLED_KEY] = true
        end

        def normalize(errors)
          return errors if errors.is_a?(Hash)

          if errors.respond_to?(:valid?) && errors.respond_to?(:errors)
            errors.valid?
            return errors.errors.to_hash
          end

          return errors.to_hash if errors.respond_to?(:to_hash)
          return errors.to_h if errors.respond_to?(:to_h)

          raise ArgumentError, 'Expected a Hash or an object responding to :valid? and :errors, ' \
                               ":to_hash, or :to_h, got #{errors.class}"
        end

        def filter(errors, only_keys)
          return errors unless only_keys&.any?

          errors.slice(*only_keys, *only_keys.map(&:to_sym))
        end
      end
    end
  end
end
