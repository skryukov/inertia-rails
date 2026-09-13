# frozen_string_literal: true

# What only a Rails host supplies: `ActiveSupport::Cache.expand_cache_key`
# reading `cache_key_with_version` off a record, and a store that honours an
# `ActiveSupport::Duration` expiry. The prop's own behaviour lives in the core
# suite (`gems/inertia-core/spec/cached_prop_spec.rb`).
RSpec.describe InertiaRails::CachedProp do
  let(:controller) { ApplicationController.new }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(InertiaRails).to receive(:cache_store).and_return(cache_store)
  end

  describe 'InertiaRails.cache(ar_object) { block }' do
    it 'derives key from cache_key_with_version' do
      ar_object = double('ARObject')
      allow(ar_object).to receive(:cache_key_with_version).and_return('posts/1-20260410')

      prop = InertiaRails.cache(ar_object) { { title: 'Hello' } }
      shipped(prop, controller)

      expect(cache_store.read('inertia_rails_v2/posts/1-20260410')).to eq({ title: 'Hello' }.to_json)
    end
  end

  describe 'InertiaRails.cache(ar_object, expires_in: ...) { block }' do
    it 'accepts AR object with keyword options' do
      ar_object = double('ARObject')
      allow(ar_object).to receive(:cache_key_with_version).and_return('posts/1-20260410')

      prop = InertiaRails.cache(ar_object, expires_in: 1.second) { 'value' }
      shipped(prop, controller)

      expect(cache_store.read('inertia_rails_v2/posts/1-20260410')).to eq('"value"')

      travel 2.seconds
      expect(cache_store.read('inertia_rails_v2/posts/1-20260410')).to be_nil
    end
  end
end
