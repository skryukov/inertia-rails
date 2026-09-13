# frozen_string_literal: true

module Inertia
  module Core
    class Prop
      module Announcements
        # `onceProps`: the key the client files the value under, and when it
        # goes stale. The client sends the keys it holds back in
        # `X-Inertia-Except-Once-Props`, and those props stay home.
        class Once
          # The expiry clock is read once per page, so every claim on it
          # agrees on the time.
          def self.contribute(ledger, _visit)
            now = Time.now.to_f
            claims = {}
            ledger.each do |entry|
              once = entry.prop.once
              next unless once && !entry.silenced?

              key = once.key_for(entry.path)
              refuse_shared_key!(key, claims[key], entry.path) if claims.key?(key)
              claims[key] = once.claim(entry.path, now)
            end
            { onceProps: claims }
          end

          # The client stores one value per key, so a second claim would
          # overwrite the first and the two props would take turns winning.
          def self.refuse_shared_key!(key, first, second)
            raise ResolutionError,
                  "Props `#{first[:prop]}` and `#{second}` share the `once` key `#{key}`. " \
                  'Give one of them a `key:` of its own.'
          end

          def initialize(key: nil, fresh: false, expires_in: nil)
            @key = key.nil? ? nil : header_safe(key).dup.freeze
            @fresh = fresh
            @expires_in = seconds(expires_in)
          end

          # Asking for the prop by name is asking for it again.
          def held?(visit, path)
            !@fresh && visit.holds_once?(key_for(path)) && !visit.asked_for?(path)
          end

          def key_for(path)
            @key || path
          end

          def claim(path, now)
            entry = { prop: path }
            entry[:expiresAt] = ((now + @expires_in.to_f) * 1000).to_i if @expires_in
            entry
          end

          private

          # The core runs without ActiveSupport, but takes its durations
          # (`1.hour`) when the host loaded it.
          def seconds(value)
            return value if value.nil? || value.is_a?(Numeric)
            return value if defined?(ActiveSupport::Duration) && value.is_a?(ActiveSupport::Duration)

            raise ArgumentError, "`expires_in:` is a number of seconds — got #{value.inspect}."
          end

          def header_safe(key)
            name = WireName.check!(:key, key)
            return name unless name.match?(/[,[:cntrl:]]/) || name.strip.empty?

            raise ArgumentError,
                  "`key:` #{key.inspect} must survive the `X-Inertia-Except-Once-Props` header, " \
                  'which is a comma-separated list of trimmed names.'
          end
        end
      end
    end
  end
end
