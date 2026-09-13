# frozen_string_literal: true

RSpec.describe Inertia::Core::CachedProp do
  describe 'CachedProp.new(key) { block }' do
    it 'caches the block result and returns RawJson' do
      call_count = 0
      prop = described_class.new('stats') do
        call_count += 1
        { count: 42 }
      end

      result = shipped(prop)
      expect(result).to be_a(Inertia::Core::RawJson)
      expect(result.to_json).to eq({ count: 42 }.to_json)
      expect(call_count).to eq(1)

      result2 = shipped(prop)
      expect(result2).to be_a(Inertia::Core::RawJson)
      expect(result2.to_json).to eq({ count: 42 }.to_json)
      expect(call_count).to eq(1)
    end
  end

  describe 'CachedProp.new(key, **options) { block }' do
    it 'stores under the host-expanded key and hands the rest to the store' do
      prop = described_class.new('stats', expires_in: 60) { 'value' }
      shipped(prop)

      expect(host.store['test/stats']).to eq('"value"')
      expect(host.store.options['test/stats']).to eq(expires_in: 60)
    end
  end
end
