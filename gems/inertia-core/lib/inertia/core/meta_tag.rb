# frozen_string_literal: true

require 'cgi'
require 'digest'
require 'json'

module Inertia
  module Core
    # One head tag: what the client receives (`as_json`, camelCased) and what a
    # server-rendered head prints (`to_html`). A tag is addressed by its head
    # key, so the client can replace it when the page changes.
    class MetaTag
      # https://html.spec.whatwg.org/#void-elements
      UNARY_TAGS = %i[
        area base br col embed hr img input keygen link meta source track wbr
      ].freeze

      LD_JSON_TYPE = 'application/ld+json'
      # Any other script type is neutered: the browser must not run head data.
      DEFAULT_SCRIPT_TYPE = 'text/plain'

      GENERATABLE_HEAD_KEY_PROPERTIES = %i[name property http_equiv].freeze

      # What JSON inside a `<script>` must not carry literally: the HTML
      # delimiters, and the two separators JavaScript reads as line breaks.
      JSON_UNSAFE = /[&<>\u2028\u2029]/

      def initialize(tag_name: nil, head_key: nil, allow_duplicates: false, type: nil, **tag_data)
        if tag_name.nil? && tag_data.keys == [:title]
          @tag_name = :title
          @tag_data = { inner_content: tag_data[:title] }
        else
          @tag_name = tag_name.nil? ? :meta : tag_name.to_sym
          @tag_data = tag_data.transform_keys(&:to_sym)
        end
        @tag_type = determine_tag_type(type)
        @allow_duplicates = allow_duplicates
        @head_key = @tag_name == :title ? 'title' : (head_key || generate_head_key)
      end

      def as_json(_options = nil)
        { tagName: @tag_name, headKey: @head_key, type: @tag_type }
          .merge(@tag_data.transform_keys { |key| camelize(key) })
          .reject { |_, value| blank?(value) }
      end

      def to_json(*args)
        as_json.to_json(*args)
      end

      def to_html(inertia_attribute:)
        data = @tag_data.merge(type: @tag_type, inertia_attribute.to_sym => @head_key)
        content = data.delete(:inner_content)
        open = "<#{@tag_name}#{attributes(data)}>"
        return open if UNARY_TAGS.include?(@tag_name)

        "#{open}#{inner_html(content)}</#{@tag_name}>"
      end

      def [](key)
        key = key.to_sym
        return @tag_name if key == :tag_name
        return @head_key if key == :head_key
        return @tag_type if key == :type

        @tag_data[key]
      end

      private

      # A boolean attribute (`async: true`) prints bare; `false` and `nil`
      # leave it out.
      def attributes(data)
        data.filter_map do |name, value|
          next if value.nil? || value == false

          name = name.to_s.tr('_', '-')
          value == true ? " #{name}" : %( #{name}="#{escape(value)}")
        end.join
      end

      def inner_html(content)
        return json_escape(content.to_json) if @tag_name == :script && (content.is_a?(Hash) || content.is_a?(Array))

        escape(content)
      end

      # A string a framework already marked safe is printed as it is.
      def escape(value)
        value = value.join(' ') if value.is_a?(Array)
        return value.to_s if value.respond_to?(:html_safe?) && value.html_safe?

        CGI.escapeHTML(value.to_s)
      end

      def json_escape(json)
        json.gsub(JSON_UNSAFE) { |char| format('\u%04x', char.ord) }
      end

      def determine_tag_type(type)
        return type unless @tag_name == :script

        type == LD_JSON_TYPE ? LD_JSON_TYPE : DEFAULT_SCRIPT_TYPE
      end

      def generate_head_key
        generate_meta_head_key || "#{@tag_name}-#{tag_digest}"
      end

      def tag_digest
        signature = @tag_data.sort.map { |key, value| "#{key}=#{value}" }.join('&')
        Digest::SHA256.hexdigest(signature)[0, 8]
      end

      def generate_meta_head_key
        return unless @tag_name == :meta
        return 'meta-charset' if @tag_data.key?(:charset)

        GENERATABLE_HEAD_KEY_PROPERTIES.each do |key|
          next unless @tag_data.key?(key)

          return ['meta', key, slug(@tag_data[key]), (tag_digest if @allow_duplicates)].compact.join('-')
        end

        nil
      end

      def slug(value)
        value.to_s.gsub(/[^a-z0-9\-_]+/i, '-').gsub(/-{2,}/, '-').gsub(/\A-|-\z/, '').downcase
      end

      def camelize(key)
        key.to_s.gsub(/_([a-z\d])/) { Regexp.last_match(1).upcase }.to_sym
      end

      def blank?(value)
        return value.strip.empty? if value.is_a?(String)

        value.nil? || value == false || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
