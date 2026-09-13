# frozen_string_literal: true

module Inertia
  module Core
    class Error < StandardError; end

    # A mistake in the props or the page themselves, as opposed to a failure
    # while producing a value.
    class ResolutionError < Error; end

    # The SSR server failed to render, or could not be reached.
    class SSRError < Error
      attr_reader :type, :hint, :browser_api, :stack, :source_location

      def initialize(message = nil, type: nil, hint: nil, browser_api: nil, stack: nil, source_location: nil)
        @type = type
        @hint = hint
        @browser_api = browser_api
        @stack = stack
        @source_location = source_location
        super(message)
      end

      def self.from_response(body)
        new(
          body['error'] || 'Unknown SSR error',
          type: body['type'],
          hint: body['hint'],
          browser_api: body['browserApi'],
          stack: body['stack'],
          source_location: body['sourceLocation']
        )
      end

      def self.from_exception(exception)
        error = new(exception.message, type: 'connection')
        error.set_backtrace(exception.backtrace)
        error
      end
    end
  end
end
