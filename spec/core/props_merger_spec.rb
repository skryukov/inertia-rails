# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::PropsMerger do
  it 'canonicalizes string and symbol spellings to one key' do
    expect(described_class.merge({ 'user' => 1 }, { user: 2 })).to eq(user: 2)
    expect(described_class.merge({ 'user' => { 'name' => 'a' } }, { user: { role: 'b' } }, deep: true))
      .to eq(user: { name: 'a', role: 'b' })
  end

  it 'keeps keys that have no symbol form' do
    expect(described_class.merge({ 1 => 'shared' }, { 'b' => 2 })).to eq(1 => 'shared', b: 2)
    expect(described_class.merge({ 1 => { 'x' => 1 } }, {}, deep: true)).to eq(1 => { x: 1 })
  end
end
