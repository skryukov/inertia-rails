# frozen_string_literal: true

require_relative 'devtools/exchange'
require_relative 'devtools/entries_repository'
require_relative 'devtools/recorder'
require_relative 'devtools/middleware'

module InertiaRails
  # The Rails half of the Inertia DevTools protocol: every request is recorded as
  # an entry the Chrome extension reads back through `/_inertia/devtools/entries`.
  # Recording never alters the response; anything that raises inside it is
  # reported and dropped.
  module Devtools
    Headers = Inertia::Core::Devtools::Headers
    Ulid = Inertia::Core::Devtools::Ulid
    RequestType = Inertia::Core::Devtools::RequestType
    ScriptTag = Inertia::Core::Devtools::ScriptTag
    Collector = Inertia::Core::Devtools::Collector
    EntryBuilder = Inertia::Core::Devtools::EntryBuilder

    ROUTE_PREFIX = '/_inertia/devtools'
    REPOSITORY_MUTEX = Mutex.new

    class << self
      def enabled?
        InertiaRails.configuration.devtools_enabled?
      end

      def start(env)
        swallow do
          next unless enabled?
          next if skip?(env['PATH_INFO'].to_s)

          env[Recorder::ENV_KEY] = Recorder.new(env)
        end
      end

      def recorder(request)
        request.env[Recorder::ENV_KEY] if request.respond_to?(:env)
      end

      def repository
        config = InertiaRails.configuration

        key = [
          config.devtools_storage_path || Rails.root.join('tmp/inertia-devtools').to_s,
          config.devtools_ttl.to_f,
          config.devtools_prune_interval.to_i
        ]

        REPOSITORY_MUTEX.synchronize do
          unless @repository && @repository_key == key
            @repository = EntriesRepository.new(path: key[0], ttl_hours: key[1], prune_interval: key[2])
            @repository_key = key
          end

          @repository
        end
      end

      def comma_list(value)
        value.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      # #body and #to_ary read an already buffered body without draining it, but a
      # file-backed or live streaming body would block. ActionDispatch::Response#body
      # also hands back the raw stream under `render stream:`, so only a String or
      # Array is really a body.
      def buffered_body(env, body)
        return if body.respond_to?(:to_path) || live_stream?(env)

        parts = if body.respond_to?(:body)
                  body.body
                elsif body.respond_to?(:to_ary)
                  body.to_ary
                end

        case parts
        when String then parts
        when Array then parts.join
        end
      end

      def live_stream?(env)
        defined?(ActionController::Live) &&
          env['action_controller.instance'].is_a?(ActionController::Live)
      end

      def swallow
        yield
      rescue StandardError => e
        report(e)
        nil
      end

      def report(error)
        InertiaRails.host.report_error(error, devtools: true)
      end

      private

      def skip?(path)
        return true if path.start_with?(ROUTE_PREFIX)

        relative_path = path.delete_prefix('/')

        Array(InertiaRails.configuration.devtools_except).any? do |pattern|
          pattern.is_a?(Regexp) ? pattern.match?(path) : File.fnmatch?(pattern.to_s, relative_path)
        end
      end
    end
  end
end
