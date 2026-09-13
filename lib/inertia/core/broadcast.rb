# frozen_string_literal: true

module Inertia
  module Core
    # Props pushed over a broadcast instead of fetched: the client writes the
    # values into the page when the event carries them under `__inertia`.
    module Broadcast
      ENVELOPE_KEY = '__inertia'

      module_function

      # Resolves `props` as a full load would — deferred and optional included,
      # rescued dropped — into `{ '__inertia' => { 'props' => {...} } }`.
      def props(props, evaluator:)
        # Symbol keys are never expanded by dot notation, so `'a.b' => 1` stays
        # the prop path the client addresses.
        literal = props.transform_keys(&:to_sym)
        if literal.size != props.size
          raise ResolutionError,
                'Broadcast props name the same path twice as a String and a Symbol; ' \
                'the client addresses one path, so one of the values would be dropped.'
        end

        resolved, = PropsResolver.new(literal, evaluator: evaluator, eager: true).resolve
        { ENVELOPE_KEY => { 'props' => resolved.transform_keys(&:to_s) } }
      end
    end
  end
end
