# frozen_string_literal: true

require_relative 'devtools/headers'
require_relative 'devtools/ulid'
require_relative 'devtools/request_type'
require_relative 'devtools/key_filter'
require_relative 'devtools/redactor'
require_relative 'devtools/sources'
require_relative 'devtools/script_tag'
require_relative 'devtools/prop_classifier'
require_relative 'devtools/collector'
require_relative 'devtools/exchange'
require_relative 'devtools/entry_builder'
require_relative 'devtools/entries_repository'
require_relative 'devtools/closing_body'
require_relative 'devtools/recorder'
require_relative 'devtools/middleware'

module Inertia
  module Core
    # The server half of the Inertia DevTools protocol: every request becomes
    # one JSON entry the browser extension reads back. The contract it serves
    # is written down in DEVTOOLS_CONTRACT.md. A host adds the read endpoint,
    # its source locators, and what only its framework knows about a request.
    module Devtools
    end
  end
end
