# frozen_string_literal: true

# Serializers and prop types must resolve wherever a value is produced. Rather
# than enumerate the shapes one by one, generate them and assert that nothing
# unresolved reaches the response.
#
# Every serializer here carries a marker that only its unserialized form can
# expose, and the payload is checked for it. Looking for unresolved *types*
# alone was not enough: a serializer subclassing `Hash` passed the type check
# while handing over its raw contents.
#
# The check is one-sided — it proves nothing leaks, not that the right values
# came out. Dropping a prop entirely passes here; the concrete examples in
# `props_resolver_spec.rb` cover that half.
#
# A prop type used as a bare array element is refused (its semantics need a
# prop key), so no position here wraps the payload in one; the concrete
# refusals live in `props_resolver_spec.rb`.
RSpec.describe Inertia::Core::PropsResolver do
  describe 'serializer resolution across positions' do
    # An unwrapped serializer shows the marker through its ivar dump. A `Hash`
    # subclass shows it by carrying it as a key.
    marker = 'UNSERIALIZED'

    serializer_for = lambda do |value|
      object = Object.new
      object.instance_variable_set(:@marker, marker)
      object.define_singleton_method(:to_inertia) { value }
      object
    end

    hash_serializer_for = lambda do |value|
      klass = Class.new(Hash) do
        define_method(:to_inertia) { value }
      end
      klass.new.tap { |hash| hash[:marker] = marker }
    end

    payloads = {
      'a scalar' => -> { 'plain' },
      'a hash of values' => -> { { id: 1, name: 'n' } },
      'a hash with defer' => -> { { name: 'n', stats: Inertia::Core::DeferProp.new { 'D' } } },
      'a hash with optional' => -> { { name: 'n', secret: Inertia::Core::OptionalProp.new { 'S' } } },
      'a serializer' => -> { serializer_for.call(name: 'n', stats: Inertia::Core::DeferProp.new { 'D' }) },
      'a serializer subclassing Hash' => -> { hash_serializer_for.call(name: 'n') },
    }

    positions = {
      'placed literally' => ->(v) { { a: v } },
      'nested in a hash' => ->(v) { { a: { b: v } } },
      'returned from a closure' => ->(v) { { a: -> { v } } },
      'returned from always' => ->(v) { { a: Inertia::Core::AlwaysProp.new { v } } },
      'returned from defer' => ->(v) { { a: Inertia::Core::DeferProp.new { v } } },
      'used as an array element' => ->(v) { { a: [v] } },
      'returned from a closure inside an array' => ->(v) { { a: [-> { v }] } },
      'nested in an array inside an array' => ->(v) { { a: [[v]] } },
      'nested in a hash inside an array' => ->(v) { { a: [{ b: v }] } },
    }

    visits = {
      'an initial load' => {},
      'a partial for the parent' => { partial: true, only: ['a'] },
      'a partial excluding a child' => { partial: true, except: ['a.name'] },
    }

    positions.each do |position_name, place|
      payloads.each do |payload_name, build_payload|
        visits.each do |visit_name, visit|
          it "resolves #{payload_name} #{position_name} on #{visit_name}" do
            props = place.call(build_payload.call)
            resolved, = described_class.new(props, evaluator: evaluator, visit: visit).resolve

            expect(resolved.inspect).not_to match(/Inertia::Core::\w+Prop|#<Object/)
            expect(resolved.to_json).not_to include(marker)
          end
        end
      end
    end
  end

  # A cached value is resolved once and replayed verbatim, so a leak there is
  # written to the cache store and served until the entry expires. The stored
  # JSON is checked as well as the page: the two are the same bytes, and only
  # the stored one survives the request.
  describe 'serializer resolution inside a cached value' do
    marker = 'UNSERIALIZED'

    serializer_for = lambda do |value|
      object = Object.new
      object.instance_variable_set(:@marker, marker)
      object.define_singleton_method(:to_inertia) { value }
      object
    end

    hash_serializer_for = lambda do |value|
      klass = Class.new(Hash) do
        define_method(:to_inertia) { value }
      end
      klass.new.tap { |hash| hash[:marker] = marker }
    end

    payloads = {
      'a serializer' => -> { serializer_for.call(name: 'n') },
      'a serializer subclassing Hash' => -> { hash_serializer_for.call(name: 'n') },
      'a chain of serializers' => -> { serializer_for.call(serializer_for.call(name: 'n')) },
    }

    positions = {
      'as the whole value' => ->(v) { v },
      'nested in a hash' => ->(v) { { b: v } },
      'returned from a closure' => ->(v) { -> { v } },
      'as an array element' => ->(v) { [v] },
      'nested in an array inside an array' => ->(v) { [[v]] },
      'nested in a hash inside an array' => ->(v) { [{ b: v }] },
    }

    positions.each do |position_name, place|
      payloads.each do |payload_name, build_payload|
        it "resolves #{payload_name} #{position_name}" do
          value = place.call(build_payload.call)
          props = { a: Inertia::Core::CachedProp.new('invariant_key') { value } }
          resolved, = described_class.new(props, evaluator: evaluator).resolve

          expect(resolved.to_json).not_to include(marker)
          expect(host.store['test/invariant_key']).not_to include(marker)
        end
      end

      # Nothing that behaves differently per request may be stored, wherever it
      # sits in the value.
      it "refuses a prop type #{position_name}" do
        value = place.call(Inertia::Core::DeferProp.new { 'D' })
        props = { a: Inertia::Core::CachedProp.new('invariant_key') { value } }

        expect { described_class.new(props, evaluator: evaluator).resolve }
          .to raise_error(Inertia::Core::Error, /cannot be cached/)
        expect(host.store['test/invariant_key']).to be_nil
      end
    end
  end

  # The matrix above only proves nothing leaks. These assert the other half —
  # the exact payload and metadata — for the compositions where resolution used
  # to stop early.
  describe 'composed producers' do
    def resolve(props, visit: {})
      described_class.new(props, evaluator: evaluator, visit: visit).resolve
    end

    def serializer_for(value)
      Object.new.tap { |object| object.define_singleton_method(:to_inertia) { value } }
    end

    it 'resolves a serializer returned from a closure inside an array' do
      serializer = serializer_for({ name: 'n', stats: Inertia::Core::DeferProp.new { 'D' } })

      resolved, metadata = resolve({ users: [-> { serializer }] })

      expect(resolved).to eq(users: [{ name: 'n' }])
      expect(metadata).to eq(deferredProps: { 'default' => ['users.0.stats'] })
    end

    it 'resolves serializers nested in an array inside an array' do
      resolved, = resolve({ rows: [[serializer_for({ id: 1 })], [serializer_for({ id: 2 })]] })

      expect(resolved).to eq(rows: [[{ id: 1 }], [{ id: 2 }]])
    end

    it 'resolves combined prop options down to their value' do
      props = { locale: Inertia::Core::DeferProp.new(once: true, merge: true) { 'en' } }

      resolved, metadata = resolve(props, visit: { partial: true, only: ['locale'] })

      expect(resolved).to eq(locale: 'en')
      expect(metadata[:onceProps]).to eq('locale' => { prop: 'locale' })
      expect(metadata[:mergeProps]).to eq(['locale'])
    end

    it 'defers combined prop options on an initial load' do
      props = { locale: Inertia::Core::DeferProp.new(once: true, merge: true) { 'en' } }

      resolved, metadata = resolve(props)

      expect(resolved).to eq({})
      expect(metadata[:deferredProps]).to eq('default' => ['locale'])
    end

    it 'carries rescue behaviour from a prop type produced by a closure' do
      props = { x: -> { Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' } } }

      resolved, metadata = resolve(props, visit: { partial: true, only: ['x'] })

      expect(resolved).to eq({})
      expect(metadata[:rescuedProps]).to eq(['x'])
    end

    it 'keeps array positions so indexed metadata paths stay valid' do
      props = { rows: [nil, serializer_for({ id: 1 }), false, 2] }

      resolved, = resolve(props)

      expect(resolved).to eq(rows: [nil, { id: 1 }, false, 2])
    end

    it 'refuses a self-producing prop as stacking before it can loop' do
      prop = nil
      prop = Inertia::Core::DeferProp.new { prop }

      expect { resolve({ x: prop }, visit: { partial: true, only: ['x'] }) }
        .to raise_error(Inertia::Core::Error, /produces a prop type/)
    end
  end
end
