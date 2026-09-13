# frozen_string_literal: true

RSpec.describe InertiaRails::BaseProp do
  # The alias survives for `is_a?` checks; construction takes finished parts
  # like any Prop — the old block-swallowing constructor is gone.
  it 'is Prop under its historical name' do
    expect(described_class).to equal(InertiaRails::Prop)
  end

  it 'calls the producer it is built with' do
    prop = described_class.new(producer: ->(_production) { 'value' })

    expect(evaluate(prop, Object.new)).to eq('value')
  end
end
