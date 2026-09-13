# frozen_string_literal: true

module InertiaRails
  module Devtools
    # What Rails knows about the exchange that the protocol does not: the method a
    # form override renamed, the parameters ActionDispatch parsed, the body it buffered.
    class Exchange < Inertia::Core::Devtools::Exchange
      def initialize(env, **response)
        super
        @request = ActionDispatch::Request.new(env)
      end

      def request_method
        @request.request_method
      end

      def url
        @request.original_url
      end

      def request_parameters
        summarize_uploads(@request.request_parameters)
      end

      def raw_request_body
        @request.raw_post
      end

      def response_content
        Devtools.buffered_body(env, body)
      end

      private

      def summarize_uploads(parameters)
        parameters.deep_transform_values do |value|
          if value.is_a?(ActionDispatch::Http::UploadedFile)
            { name: value.original_filename, size: value.size, mimeType: value.content_type }
          else
            value
          end
        end
      end
    end
  end
end
