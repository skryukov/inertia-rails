# frozen_string_literal: true

# How a cached value resolves lives in the core suite
# (`gems/inertia-core/spec/prop_cacheable_to_inertia_spec.rb`). What stays here
# is the namespace `InertiaRails::CoreHost#expand_cache_key` writes under.
RSpec.describe 'the inertia_rails_v2 cache namespace' do
  let(:evaluator) { InertiaRails::PropEvaluator.new(Object.new, host: InertiaRails.host) }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(InertiaRails).to receive(:cache_store).and_return(cache_store) }

  def render_page(props)
    resolved, metadata = InertiaRails::PropsResolver.new(props, evaluator: evaluator).resolve
    JSON.parse({ props: resolved }.merge(metadata).to_json)
  end

  def build_serializer
    object = Object.new
    object.instance_variable_set(:@secret, 'LEAKED')
    object.define_singleton_method(:to_inertia) { { name: 'bob' } }
    object
  end

  # Values cached before serializers were resolved hold `as_json` output —
  # a serializer's raw ivars. Those entries live under the unversioned
  # `inertia_rails/` prefix and must never be served again.
  it 'ignores a warm entry under the previous namespace' do
    cache_store.write('inertia_rails/legacy_key', { secret: 'LEAKED' }.to_json)
    serializer = method(:build_serializer)

    props = { u: InertiaRails.cache('legacy_key') { serializer.call } }

    expect(render_page(props)['props']).to eq('u' => { 'name' => 'bob' })
    expect(cache_store.read('inertia_rails_v2/legacy_key')).to eq({ name: 'bob' }.to_json)
  end

  # An app caching under the key `v2/foo` wrote to `inertia_rails/v2/foo` in
  # the old format. Versioning inside the old prefix would serve that entry.
  it 'ignores an old entry whose key looks like the new namespace' do
    cache_store.write('inertia_rails/v2/foo', { secret: 'LEAKED' }.to_json)
    serializer = method(:build_serializer)

    props = { u: InertiaRails.cache('v2/foo') { serializer.call } }

    expect(render_page(props)['props']).to eq('u' => { 'name' => 'bob' })
  end
end
