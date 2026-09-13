# frozen_string_literal: true

# The `cache:` option's own behaviour lives in the core suite
# (`gems/inertia-core/spec/prop_cacheable_spec.rb`). What stays here is what
# `InertiaRails::CoreHost` contributes: Rails' cache-key expansion and a store
# that honours an `ActiveSupport::Duration`.
RSpec.describe InertiaRails::Prop, 'the cache option under Rails' do
  let(:controller) { ApplicationController.new }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:prop_class) { InertiaRails::DeferProp }

  before do
    allow(InertiaRails).to receive(:cache_store).and_return(cache_store)
  end

  it 'passes an ActiveSupport::Duration expiry through to the store' do
    prop = prop_class.new(cache: { key: 'test_key', expires_in: 1.second }) { 'value' }
    shipped(prop, controller)

    expect(cache_store.read('inertia_rails_v2/test_key')).to eq('"value"')

    travel 2.seconds
    expect(cache_store.read('inertia_rails_v2/test_key')).to be_nil
  end

  it 'derives the key from cache_key_with_version' do
    ar_object = double('ARObject')
    allow(ar_object).to receive(:cache_key_with_version).and_return('users/1-20260410')

    prop = prop_class.new(cache: ar_object) { { name: 'Bob' } }
    shipped(prop, controller)

    expect(cache_store.read('inertia_rails_v2/users/1-20260410')).to eq({ name: 'Bob' }.to_json)
  end
end
