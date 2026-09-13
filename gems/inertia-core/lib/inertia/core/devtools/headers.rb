# frozen_string_literal: true

module Inertia
  module Core
    module Devtools
      # The protocol's headers: the ones the server stamps on a response,
      # and the ones the extension sends, as the Rack env spells them.
      module Headers
        ID = 'X-Inertia-Devtools-Id'
        PARENT_OUT = 'X-Inertia-Devtools-Parent-Out'
        # The prefix the app is mounted under; the extension puts it before
        # the entries path it fetches. Absent when the app is at the root.
        BASE_PATH = 'X-Inertia-Devtools-Base-Path'
        PARENT = 'HTTP_X_INERTIA_DEVTOOLS_PARENT'
        TAB = 'HTTP_X_INERTIA_DEVTOOLS_TAB'
        VISIT = 'HTTP_X_INERTIA_DEVTOOLS_VISIT'
        DEFERRED = 'HTTP_X_INERTIA_DEVTOOLS_DEFERRED'
        POLL = 'HTTP_X_INERTIA_DEVTOOLS_POLL'

        module_function

        # An empty header is one the client did not send.
        def read(env, key)
          value = env[key]
          value if value.is_a?(String) && !value.empty?
        end

        def response_keys
          [ID, PARENT_OUT, BASE_PATH].map { |name| Core::Rack.header_name(name) }
        end
      end
    end
  end
end
