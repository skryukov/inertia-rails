# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::PropsResolver do
  it 'resolves plain data, closures and prop types against a full load' do
    props, metadata = resolve({
                                plain: 1,
                                lazy: -> { 2 },
                                deferred: Inertia::Core::DeferProp.new { 3 },
                                optional: Inertia::Core::OptionalProp.new { 4 },
                                always: Inertia::Core::AlwaysProp.new { 5 },
                                'nested.a.b' => 6,
                              })

    expect(props).to eq(plain: 1, lazy: 2, always: 5, nested: { a: { b: 6 } })
    expect(metadata).to eq(deferredProps: { 'default' => ['deferred'] })
  end

  it 'answers a partial reload with what was asked for' do
    props, metadata = resolve(
      { a: 1, b: Inertia::Core::DeferProp.new { 2 }, c: Inertia::Core::AlwaysProp.new { 3 } },
      { partial: true, only: ['b'] }
    )

    expect(props).to eq(b: 2, c: 3)
    expect(metadata).to eq({})
  end

  it 'refuses one path written as a String and as a Symbol' do
    expect { resolve({ 'user' => { a: 1 }, user: { b: 2 } }) }
      .to raise_error(Inertia::Core::ResolutionError, /Props "user" and :user name the same path/)
  end

  it 'caches through the host store as JSON and instruments the fetch' do
    props = { stats: Inertia::Core::CachedProp.new('stats') { { count: 1 } } }

    expect(resolve(props).first[:stats].to_json).to eq '{"count":1}'
    expect(host.store['test/stats']).to eq '{"count":1}'
    expect(host.events).to eq [[:cache_fetch, { key: 'test/stats', hit: false }]]

    resolve(props)
    expect(host.events.last).to eq [:cache_fetch, { key: 'test/stats', hit: true }]
  end

  it 'drops a rescued prop, reports the error with its path, and announces it' do
    props, metadata = resolve({ stats: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' } },
                              { partial: true, only: ['stats'] })

    expect(props).to eq({})
    expect(metadata).to eq(rescuedProps: ['stats'])
    expect(host.reported.map { |error, context| [error.message, context] }).to eq [['boom', { prop: 'stats' }]]
  end

  describe 'observer' do
    let(:observer) do
      Class.new(Inertia::Core::Observer) do
        attr_reader :ledger

        def walked(ledger)
          @ledger = ledger
        end
      end.new
    end

    it 'sees every prop met and every rescue' do
      resolve({ a: Inertia::Core::AlwaysProp.new { 1 }, b: Inertia::Core::DeferProp.new(rescue: true) { raise 'x' } },
              { partial: true, only: ['b'] }, observer: observer)

      met = observer.ledger.map { |entry| [entry.path, entry.prop.class.name, entry.delivered?] }
      rescued = observer.ledger.rescues.map { |entry| [entry.path, entry.error.message] }
      expect(met).to eq [['a', 'Inertia::Core::AlwaysProp', true], ['b', 'Inertia::Core::DeferProp', true]]
      expect(rescued).to eq [%w[b x]]
    end
  end
end
