# frozen_string_literal: true

module InertiaRails
  module Devtools
    # The core frame, mounted above Rails::Rack::Logger as well so read API
    # polling can be kept out of the log.
    class Middleware < Inertia::Core::Devtools::Middleware
      def call(env)
        return super unless silence_logs?(env)

        Rails.logger.silence { super }
      end

      private

      def silence_logs?(env)
        return false unless env['PATH_INFO'].to_s.start_with?(ROUTE_PREFIX)
        return false unless Rails.logger.respond_to?(:silence)

        Devtools.swallow { Devtools.enabled? && InertiaRails.configuration.devtools_silence_logs } || false
      end
    end
  end
end
