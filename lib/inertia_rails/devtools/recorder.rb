# frozen_string_literal: true

module InertiaRails
  module Devtools
    # The core recorder with what only Rails has: the parsed exchange, the CSP
    # nonce, ActionDispatch's body handling, the share-site refinement, and
    # the configured store.
    class Recorder < Inertia::Core::Devtools::Recorder
      def initialize(env)
        config = InertiaRails.configuration
        super(env, repository: Devtools.repository, host: InertiaRails.host, redactor: Redaction.redactor,
                   sources: Sources.new,
                   limits: { limit: config.devtools_limit.to_i, max_entries: config.devtools_max_entries.to_i })
      end

      protected

      def exchange(status, headers, body)
        Exchange.new(env, status: status, headers: headers, body: body)
      end

      def nonce
        request = ActionDispatch::Request.new(env)
        request.content_security_policy_nonce if request.respond_to?(:content_security_policy_nonce)
      end

      def buffered_body(body)
        Devtools.buffered_body(env, body)
      end

      def refine_source(source, key)
        SourceLocator.refine(source, key)
      end
    end
  end
end
