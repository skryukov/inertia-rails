# frozen_string_literal: true

RSpec.describe Inertia::Core::Devtools::Collector do
  # One render as DevTools sees it: the collector watches the walk, then is
  # handed the page and the metadata the response was built from.
  def collect(props, visit = {}, component: 'Page', **options)
    collector = described_class.new(component: component, host: host, **options)
    resolved, metadata = Inertia::Core::PropsResolver.new(
      props, evaluator: evaluator, visit: visit, observer: collector
    ).resolve

    collector.page_rendered({ component: component, props: resolved }.merge(metadata), metadata)
    collector.build
  end

  let(:pagination) { { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 } }

  let(:props) do
    {
      plain: 'p',
      always: Inertia::Core::AlwaysProp.new { 'a' },
      optional: Inertia::Core::OptionalProp.new { 'o' },
      deferred: Inertia::Core::DeferProp.new(group: 'stats') { 'd' },
      items: Inertia::Core::MergeProp.new { [1] },
      prepended: Inertia::Core::MergeProp.new(prepend: true) { [0] },
      matched: Inertia::Core::MergeProp.new(match_on: 'id') { [{ id: 1 }] },
      deep: Inertia::Core::MergeProp.new(deep_merge: true) { { count: 1 } },
      settings: Inertia::Core::OnceProp.new(key: 'settings') { 's' },
      users: Inertia::Core::ScrollProp.new(metadata: pagination) { [{ id: 1 }] },
      feed: Inertia::Core::LiveProp.new(on: 'updated', channel: 'feed') { 'l' },
      cached: Inertia::Core::CachedProp.new('k') { 'c' },
    }
  end

  it 'badges every prop kind from what the prop and the metadata say' do
    badges = collect(props)[:props]

    expect(badges['always']).to include(inertiaType: 'always', shared: false)
    expect(badges['items']).to include(inertiaType: 'merge', mergeDirection: 'append')
    expect(badges['prepended']).to include(inertiaType: 'merge', mergeDirection: 'prepend')
    expect(badges['matched']).to include(inertiaType: 'merge', mergeDirection: 'append', deepMerge: true)
    expect(badges['deep']).to include(inertiaType: 'merge', mergeDirection: 'append', deepMerge: true)
    expect(badges['settings']).to include(inertiaType: 'once', once: true)
    expect(badges['users']).to include(inertiaType: 'scroll', mergeDirection: 'append')
    expect(badges['feed']).to include(inertiaType: nil, live: true)
    expect(badges['cached']).to include(inertiaType: nil)
    expect(badges['plain']).to include(inertiaType: nil)
  end

  it 'leaves the props omitted from a first load to the request that delivers them' do
    expect(collect(props)[:props].keys).not_to include('optional', 'deferred')
  end

  it 'badges a deferred prop only on the fetch the client says is the deferred one' do
    visit = { partial: true, only: %w[deferred] }

    deferred = collect(props, visit, deferred_request: true)[:props]['deferred']
    expect(deferred).to include(inertiaType: 'defer', deferGroup: 'stats')

    manual = collect(props, visit)[:props]['deferred']
    expect(manual[:inertiaType]).to be_nil
    expect(manual).not_to have_key(:deferGroup)
  end

  it 'keeps the group of a deferred scroll prop' do
    props = { users: Inertia::Core::ScrollProp.new(defer: true, group: 'custom', metadata: pagination) { [] } }

    badge = collect(props, { partial: true, only: %w[users] }, deferred_request: true)[:props]['users']
    expect(badge).to include(inertiaType: 'scroll', deferGroup: 'custom')
  end

  it 'follows the direction an infinite scroll visit asked for' do
    props = { users: Inertia::Core::ScrollProp.new(metadata: pagination) { [] } }

    badge = collect(props, { partial: true, only: %w[users], scroll_intent: 'prepend' })[:props]['users']
    expect(badge).to include(mergeDirection: 'prepend')
  end

  it 'flags a reset prop and drops the merge direction it no longer has' do
    badge = collect(props, { partial: true, only: %w[items], reset: %w[items] })[:props]['items']

    expect(badge).to include(inertiaType: 'merge', reset: true)
    expect(badge).not_to have_key(:mergeDirection)
  end

  it 'flags a rescued prop and records no value for it' do
    props = { permissions: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' } }

    entry = collect(props, { partial: true, only: %w[permissions] }, deferred_request: true)

    expect(entry[:props]['permissions']).to include(inertiaType: 'defer', rescued: true)
    expect(entry[:propValues]).not_to have_key('permissions')
  end

  it 'keeps one row per top-level prop, and a nested one only when it is badged' do
    props = {
      auth: { badge: Inertia::Core::AlwaysProp.new { 'A' }, user: { id: 1 } },
      plain_nested: { a: { b: 1 } },
    }

    entry = collect(props)

    expect(entry[:props].keys).to contain_exactly('auth', 'auth.badge', 'plain_nested')
    expect(entry[:propValues]['auth']).to eq('badge' => 'A', 'user' => { 'id' => 1 })
    expect(entry[:propValues]['auth.badge']).to eq 'A'
  end

  it 'keys an array path by the index the value sits at' do
    props = { rows: [{ tag: Inertia::Core::AlwaysProp.new { 'A' } }, { tag: Inertia::Core::AlwaysProp.new { 'B' } }] }

    expect(collect(props)[:propValues]).to include('rows.0.tag' => 'A', 'rows.1.tag' => 'B')
  end

  it 'flags shared props and links the rest to the line they are rendered on' do
    entry = collect(
      { name: 'Brandon', app: 'Dummy' },
      shared_keys: %w[app],
      share_sources: { 'app' => { file: 'app/controllers/app_controller.rb', line: 3 } },
      render_source: { file: 'app/controllers/pages_controller.rb', line: 10 },
      sources: instance_double(Inertia::Core::Devtools::Sources, component_path: nil, prop_line: 12)
    )

    expect(entry[:props]['app']).to include(shared: true,
                                            shareSource: { file: 'app/controllers/app_controller.rb', line: 3 })
    expect(entry[:props]['name']).to include(shared: false,
                                             renderSource: { file: 'app/controllers/pages_controller.rb', line: 12 })
  end

  it 'records the values the page ships, redacted, and the page as the response body' do
    redactor = Inertia::Core::Devtools::Redactor.new(
      filter: Inertia::Core::Devtools::KeyFilter.new(%w[password])
    )

    entry = collect({ name: 'Brandon', password: 'hunter2' }, redactor: redactor)

    expect(entry[:propValues]).to eq('name' => 'Brandon', 'password' => '[REDACTED]')
    expect(entry[:props]['password']).to include(shared: false)
    expect(entry[:responseBody]).to include('component' => 'Page')
    expect(entry[:component]).to eq 'Page'
  end
end
