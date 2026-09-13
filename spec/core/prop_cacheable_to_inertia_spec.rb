# frozen_string_literal: true

require_relative 'spec_helper'

# Regression context: `PropCacheable#call` used to encode the raw block return
# value with `to_json`, bypassing the `to_inertia` protocol and the nested
# prop-type resolution `PropsResolver` applies everywhere else. Adding `cache:`
# to a prop changed what it serialized to — and the wrong bytes were persisted
# in the cache store. These examples pin the resolved behaviour.
RSpec.describe 'PropCacheable and prop resolution' do
  # Mirrors `Renderer#build_page` + `Renderer#render`: resolve, then encode.
  def render_page(props, visit: {})
    resolved, metadata = Inertia::Core::PropsResolver.new(props, evaluator: evaluator, visit: visit).resolve
    JSON.parse({ props: resolved }.merge(metadata).to_json)
  end

  # A serializer object: responds to `to_inertia`, holds a secret in an ivar.
  # A host that teaches `Object#as_json` to dump `instance_values` (Rails does)
  # leaks every one of them when `to_inertia` is skipped.
  def build_serializer
    object = Object.new
    object.instance_variable_set(:@secret, 'LEAKED')
    object.define_singleton_method(:to_inertia) { { name: 'bob' } }
    object
  end

  let(:partial) { { partial: true, only: ['u'] } }

  describe 'a block returning a `to_inertia` serializer' do
    it 'serializes through `to_inertia` without the cache option' do
      serializer = method(:build_serializer)
      props = { u: Inertia::Core::OptionalProp.new { serializer.call } }

      expect(render_page(props, visit: partial)['props']).to eq('u' => { 'name' => 'bob' })
    end

    it 'serializes through `to_inertia` with the cache option' do
      serializer = method(:build_serializer)
      props = { u: Inertia::Core::OptionalProp.new(cache: 'serializer_key') { serializer.call } }

      expect(render_page(props, visit: partial)['props']).to eq('u' => { 'name' => 'bob' })
    end

    it 'stores the `to_inertia` value in the cache store, not the object' do
      serializer = method(:build_serializer)
      props = { u: Inertia::Core::OptionalProp.new(cache: 'serializer_key') { serializer.call } }
      render_page(props, visit: partial)

      expect(host.store['test/serializer_key']).to eq({ name: 'bob' }.to_json)
    end

    it 'returns the same payload on a warm cache' do
      serializer = method(:build_serializer)
      props = { u: Inertia::Core::OptionalProp.new(cache: 'serializer_key') { serializer.call } }
      render_page(props, visit: partial) # warm

      expect(render_page(props, visit: partial)['props']).to eq('u' => { 'name' => 'bob' })
    end

    it 'applies `to_inertia` to serializers nested inside the cached value' do
      serializer = method(:build_serializer)
      props = { u: Inertia::Core::OptionalProp.new(cache: 'nested_serializer_key') { { author: serializer.call } } }

      expect(render_page(props, visit: partial)['props']).to eq('u' => { 'author' => { 'name' => 'bob' } })
    end
  end

  describe 'a block returning a hash containing a prop type' do
    # Without the cache option the nested `defer` is dropped from the payload
    # and announced in `deferredProps` so the client can request it.
    it 'defers the nested prop without the cache option' do
      props = { u: -> { { name: 'bob', stats: Inertia::Core::DeferProp.new { 'D' } } } }

      page = render_page(props)
      expect(page['props']).to eq('u' => { 'name' => 'bob' })
      expect(page['deferredProps']).to eq('default' => ['u.stats'])
    end

    # A single cache entry cannot carry both payload shapes (with and without
    # the deferred child) nor the visit-dependent metadata, so caching a value
    # that contains a prop type is refused rather than silently mis-serialized.
    it 'raises instead of dumping the prop object into the cache' do
      deferred = Inertia::Core::DeferProp.new { 'D' }
      props = { u: Inertia::Core::CachedProp.new('nested_key') { { name: 'bob', stats: deferred } } }

      expect { render_page(props) }
        .to raise_error(Inertia::Core::Error, /DeferProp at `stats` cannot be cached/)
      expect(host.store['test/nested_key']).to be_nil
    end

    it 'raises for a prop type nested inside an array' do
      deferred = Inertia::Core::DeferProp.new { 'D' }
      props = { u: Inertia::Core::CachedProp.new('array_key') { { rows: [{ stats: deferred }] } } }

      expect { render_page(props) }.to raise_error(Inertia::Core::Error)
    end

    it 'raises for a prop type returned by a nested serializer' do
      serializer = Object.new
      serializer.define_singleton_method(:to_inertia) { { stats: Inertia::Core::DeferProp.new { 'D' } } }
      wrapped = -> { serializer }

      props = { u: Inertia::Core::CachedProp.new('serializer_defer_key') { wrapped.call } }

      expect { render_page(props) }.to raise_error(Inertia::Core::Error)
    end
  end

  describe 'plain values' do
    it 'still caches and serves scalars, hashes and arrays' do
      props = { u: Inertia::Core::CachedProp.new('plain_key') { { rows: [1, 2], name: 'bob' } } }

      expect(render_page(props)['props']).to eq('u' => { 'rows' => [1, 2], 'name' => 'bob' })
      expect(host.store['test/plain_key']).to eq({ rows: [1, 2], name: 'bob' }.to_json)
    end

    it 'preserves nil, empty containers and array positions' do
      props = { u: Inertia::Core::CachedProp.new('shapes_key') { { a: nil, b: {}, c: [nil, -> { 1 }] } } }

      expect(render_page(props)['props']).to eq('u' => { 'a' => nil, 'b' => {}, 'c' => [nil, 1] })
    end
  end

  # A cached value is resolved by the same walk a request uses, so closures
  # resolve to a fixed point and prop types are refused wherever they appear.
  describe 'resolution rules shared with the request resolver' do
    it 'resolves a chain of closures' do
      props = { u: Inertia::Core::CachedProp.new('chain_key') { { a: -> { -> { 'deep' } } } } }

      expect(render_page(props)['props']).to eq('u' => { 'a' => 'deep' })
    end

    it 'raises for a prop type at the root of the cached value' do
      props = { u: Inertia::Core::CachedProp.new('root_prop_key') { Inertia::Core::DeferProp.new { 'D' } } }

      expect { render_page(props) }.to raise_error(Inertia::Core::Error, /DeferProp cannot be cached/)
    end

    it 'raises for a prop type used as a bare array element' do
      props = { u: Inertia::Core::CachedProp.new('bare_array_key') { [Inertia::Core::DeferProp.new { 'D' }] } }

      expect { render_page(props) }.to raise_error(Inertia::Core::Error, /at `0` cannot be cached/)
    end

    # `rescue: true` must not swallow the refusal: the prop would silently
    # vanish from the entry instead of failing loudly.
    it 'raises for a rescue-enabled prop type returned by a nested closure' do
      inner = -> { Inertia::Core::DeferProp.new(rescue: true) { 'D' } }
      props = { u: Inertia::Core::CachedProp.new('inner_rescue_key') { { a: inner } } }

      expect { render_page(props) }.to raise_error(Inertia::Core::Error, /at `a` cannot be cached/)
    end

    # A `Hash` subclass implementing the protocol was scanned as a plain hash,
    # so its raw contents were written into the entry instead of `to_inertia`.
    it 'resolves a serializer that subclasses Hash' do
      leaky = Class.new(Hash) do
        def to_inertia = { safe: true }
      end
      row = leaky.new.tap { |hash| hash[:secret] = 'exposed' }

      props = { u: Inertia::Core::CachedProp.new('hash_subclass_key') { { row: row } } }

      expect(render_page(props)['props']).to eq('u' => { 'row' => { 'safe' => true } })
      expect(host.store['test/hash_subclass_key']).to eq({ row: { safe: true } }.to_json)
    end

    it 'resolves an exact Hash carrying a singleton to_inertia' do
      row = { secret: 'exposed' }
      def row.to_inertia = { safe: true }

      props = { u: Inertia::Core::CachedProp.new('hash_singleton_key') { { row: row } } }

      expect(render_page(props)['props']).to eq('u' => { 'row' => { 'safe' => true } })
      expect(host.store['test/hash_singleton_key']).to eq({ row: { safe: true } }.to_json)
    end

    it 'resolves a serializer that returns another serializer' do
      serializer = method(:build_serializer)
      outer = Object.new
      outer.define_singleton_method(:to_inertia) { serializer.call }

      props = { u: Inertia::Core::CachedProp.new('serializer_chain_key') { outer } }

      expect(render_page(props)['props']).to eq('u' => { 'name' => 'bob' })
      expect(host.store['test/serializer_chain_key']).to eq({ name: 'bob' }.to_json)
    end
  end
end
