# frozen_string_literal: true

module InertiaRails
  # What the protocol middleware asks about a request, with what only Rails
  # knows answered by `ActionDispatch::Request`: the session, the flash, the
  # controller the router resolved, and the path before routing rewrote it.
  # The origin stays the core's, read from the proxy headers the app builds
  # its own redirect URLs from.
  class ProtocolRequest < Inertia::Core::Rack::Request
    def initialize(env)
      super
      @request = ActionDispatch::Request.new(env)
    end

    delegate :session, :flash, to: :@request

    # The path `original_url` reads, not the one an engine mount rewrote.
    def fullpath
      @request.original_fullpath
    end

    # nil until the router has resolved one.
    def controller
      @env['action_controller.instance']
    end
  end
end
