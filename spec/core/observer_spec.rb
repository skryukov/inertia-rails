# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::Observer do
  let(:recorder) do
    Class.new(described_class) do
      attr_reader :ledger

      def walked(ledger)
        @ledger = ledger
      end
    end.new
  end

  def resolve(props, visit = {})
    Inertia::Core::PropsResolver.new(props, evaluator: evaluator, visit: visit, observer: recorder).resolve
  end

  def met_props
    recorder.ledger.map do |entry|
      [entry.path, Inertia::Core.type_name(entry.prop.class), entry.delivered?, entry.held?]
    end
  end

  it 'sees every prop the walk met, with its verdict' do
    resolve(
      plain: 1,
      always: Inertia::Core::AlwaysProp.new { 1 },
      deferred: Inertia::Core::DeferProp.new { 1 },
      nested: { optional: Inertia::Core::OptionalProp.new { 1 } }
    )

    expect(met_props).to eq [
      ['always', 'AlwaysProp', true, false],
      ['deferred', 'DeferProp', false, false],
      ['nested.optional', 'OptionalProp', false, false]
    ]
  end

  it 'sees a once prop held for a client that has it' do
    resolve({ settings: Inertia::Core::OnceProp.new(key: 'k') { 1 } }, partial: true, except_once: ['k'])

    expect(met_props).to eq [['settings', 'OnceProp', false, true]]
  end

  it 'sees rescued errors by path' do
    resolve({ stats: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' } }, partial: true, only: ['stats'])

    expect(recorder.ledger.rescues.map { |entry| [entry.path, entry.error.message] }).to eq [%w[stats boom]]
  end

  it 'is silent by default' do
    expect(Inertia::Core::Observer::NULL).to be_frozen
    expect(Inertia::Core::Observer::NULL.walked(nil)).to be_nil
  end
end
