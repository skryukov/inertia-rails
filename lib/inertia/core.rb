# frozen_string_literal: true

require 'json'

require_relative 'core/version'
require_relative 'core/errors'
require_relative 'core/host'
require_relative 'core/configuration'
require_relative 'core/protocol'
require_relative 'core/page'
require_relative 'core/ssr/client'
require_relative 'core/rack'
require_relative 'core/rack/request'
require_relative 'core/rack/middleware'

module Inertia
  # The framework-agnostic half of the Inertia protocol: the decisions every
  # adapter makes the same way. A host supplies a Host and a Configuration.
  module Core
  end
end
