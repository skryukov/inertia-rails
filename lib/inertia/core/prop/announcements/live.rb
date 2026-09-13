# frozen_string_literal: true

module Inertia
  module Core
    class Prop
      module Announcements
        # `liveProps`: the channels and events the client subscribes to so the
        # server can push a new value instead of waiting to be asked.
        class Live
          CHANNEL_TYPES = %w[public private presence encrypted-private].freeze

          # `live:` takes one listener or several; a listener names its events
          # and one or more channels.
          def self.parse(spec)
            Array(spec.is_a?(::Hash) ? [spec] : spec).flat_map { |listener| listeners_in(listener) }
          end

          def self.listeners_in(listener)
            raise ArgumentError, '`live:` takes `on:` (one or more event names) and `channel:`.' unless listener[:on]

            events = Array(listener[:on]).map { |event| WireName.check!(:on, event) }
            raise ArgumentError, '`live:` needs at least one event to listen for.' if events.empty?

            channels(listener[:channel]).map do |channel|
              { channel: channel, events: events, throttle: throttle(listener[:throttle]) }
            end
          end

          def self.channels(channel)
            list = channel.is_a?(::Hash) ? [channel] : Array(channel)
            list = [nil] if list.empty?
            list.map { |entry| named_channel(entry) }
          end

          def self.named_channel(entry)
            return { name: WireName.check!(:channel, entry), type: 'public' } unless entry.is_a?(::Hash)

            type = (entry[:type] || 'public').to_s
            unless CHANNEL_TYPES.include?(type)
              raise ArgumentError, "Unknown channel type `#{type}` — use #{CHANNEL_TYPES.join(', ')}."
            end

            { name: WireName.check!(:channel, entry[:name]), type: type }
          end

          def self.throttle(value)
            return value if value.nil? || value.is_a?(Numeric)

            raise ArgumentError, "`throttle:` is a number of milliseconds — got #{value.inspect}."
          end

          private_class_method :listeners_in, :channels, :named_channel, :throttle

          # Live listeners ignore the verdict, as in inertia-laravel: the
          # client subscribes before a deferred value arrives and keeps the
          # entry across partial reloads.
          def self.contribute(ledger, _visit)
            listeners = {}
            ledger.each do |entry|
              live = entry.prop.live
              listeners[entry.path] = live.to_h if live
            end
            { liveProps: listeners }
          end

          attr_reader :to_h

          def initialize(spec)
            listeners = self.class.parse(spec)
            @to_h = { listeners: listeners.map { |listener| listener.except(:throttle) } }
            throttle = one_throttle(listeners)
            @to_h[:throttle] = throttle if throttle
            @to_h.freeze
          end

          private

          # The client throttles the prop, not each listener, so a listener
          # that names none goes along with the one that does.
          def one_throttle(listeners)
            throttles = listeners.filter_map { |listener| listener[:throttle] }.uniq
            return throttles.first if throttles.size <= 1

            raise ArgumentError,
                  "Live listeners name different throttles (#{throttles.join(', ')}); " \
                  'the client throttles the prop as a whole.'
          end
        end
      end
    end
  end
end
