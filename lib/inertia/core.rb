# frozen_string_literal: true

require 'json'

require_relative 'core/version'
require_relative 'core/errors'
require_relative 'core/resolution_error'
require_relative 'core/double_precognition_error'
require_relative 'core/host'
require_relative 'core/xsrf_cookie'
require_relative 'core/configuration'
require_relative 'core/protocol'
require_relative 'core/page'
require_relative 'core/raw_json'
require_relative 'core/container'
require_relative 'core/scroll_metadata'
require_relative 'core/prop_evaluator'
require_relative 'core/observer'
require_relative 'core/ledger/entry'
require_relative 'core/ledger'
require_relative 'core/reload'
require_relative 'core/visit'
require_relative 'core/cursor'
require_relative 'core/slot'
require_relative 'core/metadata'
require_relative 'core/props_merger'
require_relative 'core/prop/cache'
require_relative 'core/prop/wire_name'
require_relative 'core/prop/options'
require_relative 'core/prop/announcements/defer'
require_relative 'core/prop/announcements/merge'
require_relative 'core/prop/announcements/once'
require_relative 'core/prop/announcements/live'
require_relative 'core/prop/announcements/scroll'
require_relative 'core/prop'
require_relative 'core/always_prop'
require_relative 'core/ignore_on_first_load_prop'
require_relative 'core/optional_prop'
require_relative 'core/defer_prop'
require_relative 'core/merge_prop'
require_relative 'core/once_prop'
require_relative 'core/cached_prop'
require_relative 'core/scroll_prop'
require_relative 'core/live_prop'
require_relative 'core/props_resolver'
require_relative 'core/broadcast'
require_relative 'core/ssr/client'
require_relative 'core/rack'
require_relative 'core/rack/request'
require_relative 'core/rack/middleware'
require_relative 'core/precognition'

module Inertia
  # The framework-agnostic half of the Inertia protocol: prop types, their
  # resolution against a visit, and the request/response decisions every adapter
  # makes the same way. A host supplies a Host, a Configuration, and the
  # per-request context prop blocks run in (see PropEvaluator).
  module Core
    class << self
      # Prop type names in error messages: users type `defer`, not the class.
      def type_name(klass)
        (klass.name || klass.to_s).split('::').last
      end
    end
  end
end
