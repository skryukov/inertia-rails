# frozen_string_literal: true

RSpec.describe Inertia::Core::Prop, 'the cache option' do
  # DeferProp accepts every prop option, so it stands in for all of them.
  let(:prop_class) { Inertia::Core::DeferProp }

  describe 'cache option forms' do
    it 'does not cache without a cache option' do
      prop = prop_class.new { 'value' }
      expect(shipped(prop)).not_to be_a(Inertia::Core::RawJson)
    end

    it 'caches under a string key' do
      prop = prop_class.new(cache: 'my_key') { 'value' }
      expect(shipped(prop)).to be_a(Inertia::Core::RawJson)
      expect(host.store['test/my_key']).to eq('"value"')
    end

    it 'caches under a hash key' do
      prop = prop_class.new(cache: { key: 'my_key', expires_in: 5 }) { 'value' }
      expect(shipped(prop)).to be_a(Inertia::Core::RawJson)
      expect(host.store['test/my_key']).to eq('"value"')
    end

    it 'raises ArgumentError when cache is a hash without :key' do
      expect { prop_class.new(cache: { expires_in: 5 }) { 'value' } }
        .to raise_error(ArgumentError, /requires a :key/)
    end
  end

  describe '#call' do
    context 'without cache' do
      it 'evaluates the block normally' do
        prop = prop_class.new { 'computed' }
        expect(shipped(prop)).to eq('computed')
      end
    end

    context 'with cache: string key' do
      it 'evaluates block on cache miss, caches, and returns RawJson' do
        call_count = 0
        prop = prop_class.new(cache: 'test_key') do
          call_count += 1
          { items: [1, 2, 3] }
        end

        result = shipped(prop)
        expect(result).to be_a(Inertia::Core::RawJson)
        expect(result.to_json).to eq({ items: [1, 2, 3] }.to_json)
        expect(call_count).to eq(1)
        expect(host.store['test/test_key']).to eq({ items: [1, 2, 3] }.to_json)
      end

      it 'returns RawJson on cache hit without evaluating block' do
        host.store['test/test_key'] = '{"items":[1,2,3]}'

        call_count = 0
        prop = prop_class.new(cache: 'test_key') do
          call_count += 1
          'should not run'
        end

        result = shipped(prop)
        expect(result).to be_a(Inertia::Core::RawJson)
        expect(result.to_json).to eq('{"items":[1,2,3]}')
        expect(call_count).to eq(0)
      end
    end

    context 'with cache: array key' do
      it 'derives cache key from array' do
        prop = prop_class.new(cache: %w[stats user_1]) { { count: 42 } }
        shipped(prop)

        expect(host.store['test/stats/user_1']).to eq({ count: 42 }.to_json)
      end
    end

    context 'with cache: hash (extended format)' do
      it 'extracts key and passes options to cache store' do
        prop = prop_class.new(cache: { key: 'test_key', expires_in: 60 }) { 'value' }
        shipped(prop)

        expect(host.store['test/test_key']).to eq('"value"')
        expect(host.store.options['test/test_key']).to eq(expires_in: 60)
      end
    end

    context 'cache does not interfere with other prop options' do
      it 'preserves group option on DeferProp' do
        prop = prop_class.new(cache: 'key', group: 'sidebar') { 'value' }
        expect(announced(prop)).to include(deferredProps: { 'sidebar' => ['key'] })
        expect(shipped(prop)).to be_a(Inertia::Core::RawJson)
      end

      it 'preserves once option on DeferProp' do
        prop = prop_class.new(cache: 'key', once: true) { 'value' }
        expect(announced(prop)).to have_key(:onceProps)
        expect(shipped(prop)).to be_a(Inertia::Core::RawJson)
      end
    end
  end
end
