# frozen_string_literal: true

RSpec.describe Inertia::Core::PropsResolver do
  let(:component) { 'TestComponent' }

  def resolve(props, visit: {})
    resolver = described_class.new(props, evaluator: evaluator, visit: visit)
    resolved_props, metadata = resolver.resolve
    { props: resolved_props }.merge(metadata)
  end

  def resolve_partial(props, *only, **visit_opts)
    resolve(props, visit: { partial: true, only: only.map(&:to_s), **visit_opts })
  end

  it 'resolves the same props twice with the same result' do
    resolver = described_class.new({ stats: Inertia::Core::DeferProp.new(once: true) { 1 }, name: -> { 'n' } },
                                   evaluator: evaluator)

    expect(resolver.resolve).to eq(resolver.resolve)
    expect(resolver.resolve.last).to eq(deferredProps: { 'default' => ['stats'] },
                                        onceProps: { 'stats' => { prop: 'stats' } })
  end

  describe 'closure resolution' do
    it 'resolves a top-level closure' do
      page = resolve({ auth: -> { { user: 'Jonathan' } } })

      expect(page[:props][:auth]).to eq({ user: 'Jonathan' })
    end

    it 'resolves a closure inside a hash' do
      page = resolve({ auth: { user: -> { 'Jonathan' } } })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
    end
  end

  describe 'AlwaysProp' do
    it 'resolves nested always prop' do
      page = resolve({ auth: { user: Inertia::Core::AlwaysProp.new { 'Jonathan' } } })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
    end

    it 'includes top-level always prop even when not requested in partial' do
      page = resolve_partial(
        { other: 'value', errors: Inertia::Core::AlwaysProp.new { { name: 'required' } } },
        'other'
      )

      expect(page[:props][:other]).to eq('value')
      expect(page[:props][:errors]).to eq({ name: 'required' })
    end

    # Stacking prop types is refused wholesale; each contradictory option
    # form is refused at construction.
    it 'refuses a merge prop produced by an always prop' do
      merged = Inertia::Core::MergeProp.new { { email: 'required' } }
      props = { name: 'Jon', errors: Inertia::Core::AlwaysProp.new { merged } }

      expect { resolve(props) }
        .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
      expect { resolve_partial(props, 'name') }
        .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
    end

    it 'refuses an always prop produced by a merge prop' do
      props = { errors: Inertia::Core::MergeProp.new { Inertia::Core::AlwaysProp.new { { email: 'required' } } } }

      expect { resolve(props) }
        .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
    end

    it 'refuses a withholding prop produced by an always prop' do
      withholding = [Inertia::Core::DeferProp.new { 1 }, Inertia::Core::OptionalProp.new { 1 },
                     Inertia::Core::OnceProp.new { 1 }]
      withholding.each do |inner|
        expect { resolve({ stats: Inertia::Core::AlwaysProp.new { inner } }) }
          .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
      end
    end

    # A full load never runs a deferred producer, so the stacking inside is
    # met on the deferred fetch instead.
    it 'refuses an always prop produced by a deferred prop at fetch time' do
      props = { stats: Inertia::Core::DeferProp.new { Inertia::Core::AlwaysProp.new { 1 } } }

      expect(resolve(props)[:deferredProps]).to eq({ 'default' => ['stats'] })
      expect { resolve_partial(props, 'stats') }
        .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
    end

    # The visit excluded `user`; `always` won, so nothing the visit says
    # applies below it — a prop inside is met as on a full load.
    it 'delivers a prop nested inside an always prop the visit excluded' do
      props = { user: Inertia::Core::AlwaysProp.new { { info: Inertia::Core::MergeProp.new { 'x' } } }, other: 1 }
      page = resolve_partial(props, 'other')

      expect(page[:props]).to eq({ user: { info: 'x' }, other: 1 })
      expect(page[:mergeProps]).to eq(['user.info'])
    end

    it 'includes nested always prop on partial request for sibling' do
      page = resolve_partial(
        { auth: { user: 'Jonathan', errors: Inertia::Core::AlwaysProp.new { { name: 'required' } } } },
        'auth.user'
      )

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth][:errors]).to eq({ name: 'required' })
    end
  end

  describe 'nested scroll props' do
    it 'refuses a scroll prop produced by a scroll prop' do
      meta = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }
      inner = Inertia::Core::ScrollProp.new(metadata: meta) { { data: [1] } }
      props = { posts: Inertia::Core::ScrollProp.new(metadata: meta) { inner } }

      expect { resolve(props) }
        .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
    end
  end

  describe 'MergeProp' do
    it 'resolves top-level merge prop with metadata' do
      page = resolve({ posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } })

      expect(page[:props][:posts]).to eq([{ id: 1 }])
      expect(page[:mergeProps]).to include('posts')
    end

    it 'includes nested merge prop on partial request with metadata' do
      page = resolve_partial(
        { feed: { posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } } },
        'feed.posts'
      )

      expect(page[:props][:feed][:posts]).to eq([{ id: 1 }])
      expect(page[:mergeProps]).to include('feed.posts')
    end

    it 'resolves nested merge prop with dot-path metadata' do
      page = resolve({ feed: { posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } } })

      expect(page[:props][:feed][:posts]).to eq([{ id: 1 }])
      expect(page[:mergeProps]).to include('feed.posts')
    end

    # An optional scroll prop is not delivered on the initial load, so there
    # is nothing for the client to paginate yet — same rule as a deferred one.
    it 'omits scroll pagination metadata for an optional scroll prop on the initial load' do
      page_meta = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }
      props = { posts: Inertia::Core::ScrollProp.new(metadata: page_meta, optional: true) { { data: [1] } } }

      page = resolve(props)

      expect(page[:props]).not_to have_key(:posts)
      expect(page).not_to have_key(:scrollProps)

      partial = resolve(props, visit: { partial: true, only: ['posts'] })

      expect(partial[:props][:posts]).to eq({ data: [1] })
      expect(partial[:scrollProps]).to have_key('posts')
    end

    # The client picks the direction per request. It used to be applied while
    # the prop ran, after its metadata had already been collected, so a
    # prepend request was still told to append.
    it 'announces the scroll direction the visit asks for' do
      page_meta = { page_name: 'page', previous_page: 1, next_page: 3, current_page: 2 }
      props = { posts: Inertia::Core::ScrollProp.new(metadata: page_meta, wrapper: 'data') { { data: [1] } } }

      page = resolve(props, visit: { partial: true, only: ['posts'], scroll_intent: 'prepend' })

      expect(page[:prependProps]).to eq(['posts.data'])
      expect(page).not_to have_key(:mergeProps)
    end

    it 'collects prepend metadata' do
      page = resolve({ posts: Inertia::Core::MergeProp.new(prepend: true) { %w[a b] } })

      expect(page[:prependProps]).to include('posts')
    end

    it 'collects nested prepend metadata with dot-path' do
      page = resolve({ feed: { posts: Inertia::Core::MergeProp.new(prepend: true) { %w[a b] } } })

      expect(page[:prependProps]).to include('feed.posts')
    end

    it 'collects nested deep merge metadata with dot-path' do
      deep = Inertia::Core::MergeProp.new(deep_merge: true) { { theme: 'dark' } }
      page = resolve({ settings: { preferences: deep } })

      expect(page[:deepMergeProps]).to include('settings.preferences')
    end

    it 'collects nested merge prop with nested append path' do
      page = resolve({ feed: { posts: Inertia::Core::MergeProp.new(append: 'data') { { data: [{ id: 1 }] } } } })

      expect(page[:mergeProps]).to include('feed.posts.data')
    end

    it 'collects nested merge prop with match_on metadata' do
      deep = Inertia::Core::MergeProp.new(deep_merge: true, match_on: 'id') { [{ id: 1 }] }
      page = resolve({ feed: { posts: deep } })

      expect(page[:deepMergeProps]).to include('feed.posts')
      expect(page[:matchPropsOn]).to include('feed.posts.id')
    end

    it 'suppresses nested merge metadata on reset' do
      page = resolve(
        { feed: { posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } } },
        visit: { partial: true, only: ['feed.posts'], reset: ['feed.posts'] }
      )

      expect(page[:props][:feed][:posts]).to eq([{ id: 1 }])
      expect(page).not_to have_key(:mergeProps)
    end

    it 'collects nested merge metadata on exact partial request' do
      page = resolve_partial(
        { feed: { posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } } },
        'feed.posts'
      )

      expect(page[:props][:feed][:posts]).to eq([{ id: 1 }])
      expect(page[:mergeProps]).to include('feed.posts')
    end

    it 'collects nested merge metadata when parent is requested' do
      page = resolve_partial(
        { feed: { posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } } },
        'feed'
      )

      expect(page[:props][:feed][:posts]).to eq([{ id: 1 }])
      expect(page[:mergeProps]).to include('feed.posts')
    end
  end

  describe 'OptionalProp' do
    it 'excludes optional prop from initial load' do
      resolved = false
      page = resolve({
                       user: 'Jonathan',
                       permissions: Inertia::Core::OptionalProp.new do
                         resolved = true
                         ['admin']
                       end,
                     })

      expect(page[:props][:user]).to eq('Jonathan')
      expect(page[:props]).not_to have_key(:permissions)
      expect(resolved).to be false
    end

    it 'includes optional prop on partial request' do
      page = resolve_partial(
        { user: 'Jonathan', permissions: Inertia::Core::OptionalProp.new { ['admin'] } },
        'permissions'
      )

      expect(page[:props][:permissions]).to eq(['admin'])
    end

    it 'excludes nested optional prop from initial load without resolving' do
      resolved = false
      page = resolve({
                       auth: {
                         user: 'Jonathan',
                         permissions: Inertia::Core::OptionalProp.new do
                           resolved = true
                           ['admin']
                         end,
                       },
                     })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:permissions)
      expect(resolved).to be false
    end

    it 'includes nested optional prop on partial request' do
      page = resolve_partial(
        { auth: { user: 'Jonathan', permissions: Inertia::Core::OptionalProp.new { ['admin'] } } },
        'auth.permissions'
      )

      expect(page[:props][:auth][:permissions]).to eq(['admin'])
    end

    it 'deeply nested optional prop is included on partial request' do
      page = resolve_partial(
        { app: { auth: { permissions: Inertia::Core::OptionalProp.new { ['admin'] } } } },
        'app.auth.permissions'
      )

      expect(page[:props][:app][:auth][:permissions]).to eq(['admin'])
    end

    it 'dot-notation optional prop is excluded from initial load' do
      page = resolve({
                       'auth.user.permissions' => Inertia::Core::OptionalProp.new { ['edit-posts'] },
                       'auth.user.name' => 'Jonathan',
                     })

      # Dot-notation keys should be expanded into nested hash
      expect(page[:props][:auth][:user][:name]).to eq('Jonathan')
      expect(page[:props][:auth][:user]).not_to have_key(:permissions)
    end

    it 'dot-notation optional prop is included on partial request' do
      page = resolve_partial(
        {
          'auth.user.permissions' => Inertia::Core::OptionalProp.new { %w[edit-posts delete-posts] },
          'auth.user.name' => 'Jonathan',
        },
        'auth.user.permissions'
      )

      expect(page[:props][:auth][:user][:permissions]).to eq(%w[edit-posts delete-posts])
    end

    it 'optional props inside indexed arrays are excluded from initial load' do
      resolved = false
      page = resolve({
                       foos: [
                         { foo: 'bar-1', bar: Inertia::Core::OptionalProp.new do
                           resolved = true
                           'expensive-data-1'
                         end, },
                         { foo: 'bar-2', bar: Inertia::Core::OptionalProp.new { 'expensive-data-2' } }
                       ],
                     })

      expect(page[:props][:foos][0][:foo]).to eq('bar-1')
      expect(page[:props][:foos][0]).not_to have_key(:bar)
      expect(resolved).to be false
    end

    it 'optional props inside indexed arrays are resolved on partial request' do
      page = resolve_partial(
        {
          foos: [
            { foo: 'bar-1', bar: Inertia::Core::OptionalProp.new { 'expensive-data-1' } },
            { foo: 'bar-2', bar: Inertia::Core::OptionalProp.new { 'expensive-data-2' } }
          ],
        },
        'foos'
      )

      expect(page[:props][:foos][0][:bar]).to eq('expensive-data-1')
      expect(page[:props][:foos][1][:bar]).to eq('expensive-data-2')
    end

    it 'deferred prop inside indexed array uses indexed path in metadata' do
      page = resolve({
                       foos: [
                         { name: 'First', notifications: Inertia::Core::DeferProp.new { ['msg'] } }
                       ],
                     })

      expect(page[:props][:foos][0][:name]).to eq('First')
      expect(page[:props][:foos][0]).not_to have_key(:notifications)
      expect(page[:deferredProps]).to eq({ 'default' => ['foos.0.notifications'] })
    end

    it 'merge prop inside indexed array uses indexed path in metadata' do
      page = resolve({
                       foos: [
                         { name: 'First', posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } }
                       ],
                     })

      expect(page[:props][:foos][0][:posts]).to eq([{ id: 1 }])
      expect(page[:mergeProps]).to eq(['foos.0.posts'])
    end

    it 'deferred prop inside indexed array is resolved on partial request for parent' do
      page = resolve_partial(
        {
          foos: [
            { name: 'First', notifications: Inertia::Core::DeferProp.new { ['msg'] } }
          ],
        },
        'foos'
      )

      expect(page[:props][:foos][0][:name]).to eq('First')
      expect(page[:props][:foos][0][:notifications]).to eq(['msg'])
    end

    it 'optional prop inside indexed array is resolved by indexed path' do
      page = resolve_partial(
        {
          foos: [
            { name: 'First', bar: Inertia::Core::OptionalProp.new { 'expensive-1' } },
            { name: 'Second', bar: Inertia::Core::OptionalProp.new { 'expensive-2' } }
          ],
        },
        'foos.0.bar'
      )

      expect(page[:props][:foos].length).to eq(2)
      expect(page[:props][:foos][0][:bar]).to eq('expensive-1')
      expect(page[:props][:foos][0]).not_to have_key(:name)
      # The unrequested element keeps its slot: metadata paths are indexed, so
      # dropping it would shift every later element onto the wrong path.
      expect(page[:props][:foos][1]).to eq({})
    end

    it 'non-indexed field path does not match inside indexed array' do
      page = resolve_partial(
        {
          foos: [
            { name: 'First', bar: Inertia::Core::OptionalProp.new { 'expensive-1' } }
          ],
        },
        'foos.bar'
      )

      expect(page[:props][:foos]).to eq([{}])
    end

    it 'closure returning array with optional prop excludes it on initial load' do
      resolved = false
      page = resolve({
                       foos: lambda {
                         [
                           { name: 'First', bar: Inertia::Core::OptionalProp.new do
                             resolved = true
                             'expensive'
                           end, }
                         ]
                       },
                     })

      expect(page[:props][:foos][0][:name]).to eq('First')
      expect(page[:props][:foos][0]).not_to have_key(:bar)
      expect(resolved).to be false
    end

    it 'closure returning array with optional prop resolves on partial request' do
      page = resolve_partial(
        {
          foos: -> { [{ name: 'First', bar: Inertia::Core::OptionalProp.new { 'expensive' } }] },
        },
        'foos'
      )

      expect(page[:props][:foos][0][:name]).to eq('First')
      expect(page[:props][:foos][0][:bar]).to eq('expensive')
    end

    it 'closure returning array with deferred prop collects indexed metadata' do
      page = resolve({
                       foos: lambda {
                         [{ name: 'First', notifications: Inertia::Core::DeferProp.new { ['msg'] } }]
                       },
                     })

      expect(page[:props][:foos][0][:name]).to eq('First')
      expect(page[:props][:foos][0]).not_to have_key(:notifications)
      expect(page[:deferredProps]).to eq({ 'default' => ['foos.0.notifications'] })
    end

    it 'dot-notation with indexed array excludes optional on initial load' do
      page = resolve({
                       'foos.items' => [
                         { name: 'First', bar: Inertia::Core::OptionalProp.new { 'expensive' } }
                       ],
                     })

      expect(page[:props][:foos][:items][0][:name]).to eq('First')
      expect(page[:props][:foos][:items][0]).not_to have_key(:bar)
    end

    it 'dot-notation with indexed array resolves optional on partial request' do
      page = resolve_partial(
        {
          'foos.items' => [
            { name: 'First', bar: Inertia::Core::OptionalProp.new { 'expensive' } }
          ],
        },
        'foos.items'
      )

      expect(page[:props][:foos][:items][0][:name]).to eq('First')
      expect(page[:props][:foos][:items][0][:bar]).to eq('expensive')
    end
  end

  describe 'DeferProp' do
    it 'excludes deferred prop from initial load without resolving' do
      resolved = false
      page = resolve({
                       name: 'Jonathan',
                       notifications: Inertia::Core::DeferProp.new do
                         resolved = true
                         []
                       end,
                     })

      expect(page[:props][:name]).to eq('Jonathan')
      expect(page[:props]).not_to have_key(:notifications)
      expect(page[:deferredProps]).to eq({ 'default' => ['notifications'] })
      expect(resolved).to be false
    end

    it 'includes deferred prop on partial request' do
      page = resolve_partial(
        { name: 'Jonathan', notifications: Inertia::Core::DeferProp.new { ['msg'] } },
        'notifications'
      )

      expect(page[:props][:notifications]).to eq(['msg'])
    end

    it 'preserves deferred group' do
      page = resolve({
                       sport: Inertia::Core::DeferProp.new(group: 'sidebar') { 'hockey' },
                       level: Inertia::Core::DeferProp.new { 'pro' },
                     })

      expect(page[:deferredProps]).to eq({
                                           'sidebar' => ['sport'],
                                           'default' => ['level'],
                                         })
    end

    it 'excludes nested deferred prop from initial load with dot-path metadata' do
      resolved = false
      page = resolve({
                       auth: {
                         user: 'Jonathan',
                         notifications: Inertia::Core::DeferProp.new do
                           resolved = true
                           []
                         end,
                       },
                     })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:notifications)
      expect(page[:deferredProps]).to eq({ 'default' => ['auth.notifications'] })
      expect(resolved).to be false
    end

    it 'nested deferred prop preserves group' do
      page = resolve({
                       auth: {
                         notifications: Inertia::Core::DeferProp.new(group: 'sidebar') { [] },
                         messages: Inertia::Core::DeferProp.new(group: 'sidebar') { [] },
                       },
                     })

      expect(page[:deferredProps]).to eq({ 'sidebar' => ['auth.notifications', 'auth.messages'] })
    end

    it 'includes nested deferred prop on partial request' do
      page = resolve_partial(
        { auth: { user: 'Jonathan', notifications: Inertia::Core::DeferProp.new { ['msg'] } } },
        'auth.notifications'
      )

      expect(page[:props][:auth][:notifications]).to eq(['msg'])
    end

    it 'deeply nested deferred prop is excluded with dot-path metadata' do
      page = resolve({
                       app: { auth: { notifications: Inertia::Core::DeferProp.new(group: 'alerts') { [] } } },
                     })

      # Parent hashes become empty when all children are deferred, so they're excluded too
      expect(page[:props]).not_to have_key(:app)
      expect(page[:deferredProps]).to eq({ 'alerts' => ['app.auth.notifications'] })
    end

    it 'deferred props at mixed depths collect correct metadata' do
      page = resolve({
                       foo: Inertia::Core::DeferProp.new { 'bar' },
                       nested: { a: 'b', c: Inertia::Core::DeferProp.new { 'd' } },
                     })

      expect(page[:props]).not_to have_key(:foo)
      expect(page[:props][:nested][:a]).to eq('b')
      expect(page[:props][:nested]).not_to have_key(:c)
      expect(page[:deferredProps]).to eq({ 'default' => ['foo', 'nested.c'] })
    end

    it 'deferred props at mixed depths resolve on partial request' do
      page = resolve_partial(
        { foo: Inertia::Core::DeferProp.new { 'bar' }, nested: { a: 'b', c: Inertia::Core::DeferProp.new { 'd' } } },
        'foo', 'nested.c'
      )

      expect(page[:props][:foo]).to eq('bar')
      expect(page[:props][:nested][:c]).to eq('d')
      expect(page[:props][:nested]).not_to have_key(:a)
      expect(page).not_to have_key(:deferredProps)
    end

    it 'collects deferred + merge metadata together' do
      page = resolve({ posts: Inertia::Core::DeferProp.new(merge: true) { [{ id: 1 }] } })

      expect(page[:props]).not_to have_key(:posts)
      expect(page[:deferredProps]).to eq({ 'default' => ['posts'] })
      expect(page[:mergeProps]).to include('posts')
    end

    it 'collects nested deferred + merge metadata together' do
      page = resolve({ feed: { posts: Inertia::Core::DeferProp.new(merge: true) { [{ id: 1 }] } } })

      # Parent hash becomes empty when all children are deferred
      expect(page[:props]).not_to have_key(:feed)
      expect(page[:deferredProps]).to eq({ 'default' => ['feed.posts'] })
      expect(page[:mergeProps]).to include('feed.posts')
    end

    it 'multiple deferred props inside closure are excluded from initial load' do
      notifications_resolved = false
      roles_resolved = false
      page = resolve({
                       auth: lambda {
                         {
                           user: 'Jonathan',
                           notifications: Inertia::Core::DeferProp.new do
                             notifications_resolved = true
                             ['msg']
                           end,
                           roles: Inertia::Core::DeferProp.new do
                             roles_resolved = true
                             ['admin']
                           end,
                         }
                       },
                     })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:notifications)
      expect(page[:props][:auth]).not_to have_key(:roles)
      expect(notifications_resolved).to be false
      expect(roles_resolved).to be false
    end

    it 'multiple deferred props inside closure are resolved on partial request' do
      page = resolve_partial(
        {
          auth: lambda {
            {
              user: 'Jonathan',
              notifications: Inertia::Core::DeferProp.new { ['msg'] },
              roles: Inertia::Core::DeferProp.new { ['admin'] },
            }
          },
        },
        'auth.notifications', 'auth.roles'
      )

      expect(page[:props][:auth][:notifications]).to eq(['msg'])
      expect(page[:props][:auth][:roles]).to eq(['admin'])
    end
  end

  describe 'DeferProp with rescue' do
    # Mimics a value (e.g. an ActiveRecord::Relation) that only fails when its
    # query runs / it is serialized, i.e. during as_json rather than in the block.
    let(:unserializable) do
      Class.new do
        def as_json(*)
          raise 'boom while serializing'
        end
      end.new
    end

    it 'omits a rescued prop and records it in rescuedProps on partial request' do
      page = resolve_partial(
        {
          name: 'Jonathan',
          permissions: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' },
        },
        'name', 'permissions'
      )

      expect(page[:props][:name]).to eq('Jonathan')
      expect(page[:props]).not_to have_key(:permissions)
      expect(page[:rescuedProps]).to eq(['permissions'])
    end

    it 'records nested rescued props using their dot-path' do
      page = resolve_partial(
        {
          auth: {
            user: 'Jonathan',
            notifications: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' },
          },
        },
        'auth.user', 'auth.notifications'
      )

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:notifications)
      expect(page[:rescuedProps]).to eq(['auth.notifications'])
    end

    it 'resolves a rescued prop normally when no error is raised' do
      page = resolve_partial(
        { permissions: Inertia::Core::DeferProp.new(rescue: true) { %w[read write] } },
        'permissions'
      )

      expect(page[:props][:permissions]).to eq(%w[read write])
      expect(page).not_to have_key(:rescuedProps)
    end

    it 'rescues errors raised while serializing the prop value' do
      page = resolve_partial(
        { permissions: Inertia::Core::DeferProp.new(rescue: true) { unserializable } },
        'permissions'
      )

      expect(page[:props]).not_to have_key(:permissions)
      expect(page[:rescuedProps]).to eq(['permissions'])
    end

    it 'rescues serialization errors from a value nested in a returned hash' do
      page = resolve_partial(
        { permissions: Inertia::Core::DeferProp.new(rescue: true) { { granted: unserializable } } },
        'permissions'
      )

      expect(page[:props]).not_to have_key(:permissions)
      expect(page[:rescuedProps]).to eq(['permissions'])
    end

    it 'rescues serialization errors from a value nested in a returned array' do
      page = resolve_partial(
        { permissions: Inertia::Core::DeferProp.new(rescue: true) { [unserializable] } },
        'permissions'
      )

      expect(page[:props]).not_to have_key(:permissions)
      expect(page[:rescuedProps]).to eq(['permissions'])
    end

    it 'resolves prop types nested in a rescued hash rather than serializing their internals' do
      stats = Inertia::Core::DeferProp.new { 'expensive' }
      auth = Inertia::Core::DeferProp.new(rescue: true) { { name: 'Jonathan', stats: stats } }

      page = resolve_partial({ auth: auth }, 'auth')

      # Keys are strings because a rescued value crosses the serializer.
      expect(page[:props][:auth]).to eq({ 'name' => 'Jonathan', 'stats' => 'expensive' })
    end

    it 'reports through an injected host without touching the global host' do
      reported = []
      host = Class.new(Inertia::Core::Host) do
        define_method(:report_error) { |error, **| reported << error }
      end.new

      resolver = described_class.new(
        { permissions: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' } },
        evaluator: Inertia::Core::PropEvaluator.new(Object.new, host: host),
        visit: { partial: true, only: ['permissions'] }
      )
      resolved_props, metadata = resolver.resolve

      expect(resolved_props).to eq({})
      expect(metadata[:rescuedProps]).to eq(['permissions'])
      expect(reported.map(&:message)).to eq(['boom'])
    end

    it 'caches through the injected host, key scheme and store alike' do
      store = TestCacheStore.new
      host = Class.new(Inertia::Core::Host) do
        define_method(:cache_store) { store }
        define_method(:expand_cache_key) { |key| "custom/#{key}" }
      end.new

      resolver = described_class.new(
        { stats: Inertia::Core::OptionalProp.new(cache: 'stats') { 'value' } },
        evaluator: Inertia::Core::PropEvaluator.new(Object.new, host: host), visit: { partial: true, only: ['stats'] }
      )
      resolved_props, = resolver.resolve

      expect(resolved_props[:stats].to_json).to eq('"value"')
      expect(store['custom/stats']).to eq('"value"')
    end

    it 'instruments cache fetches through the host' do
      events = []
      store = TestCacheStore.new
      host = Class.new(Inertia::Core::Host) do
        define_method(:cache_store) { store }
        define_method(:expand_cache_key) { |key| "spec/#{key}" }
        define_method(:instrument) do |event, payload = {}, &block|
          result = block.call(payload)
          events << [event, payload]
          result
        end
      end.new

      resolver = described_class.new(
        { stats: Inertia::Core::OptionalProp.new(cache: 'stats') { 'value' } },
        evaluator: Inertia::Core::PropEvaluator.new(Object.new, host: host), visit: { partial: true, only: ['stats'] }
      )
      resolver.resolve
      resolver.resolve

      expect(events).to eq([
                             [:cache_fetch, { key: 'spec/stats', hit: false }],
                             [:cache_fetch, { key: 'spec/stats', hit: true }]
                           ])
    end

    it 'does not rescue errors for deferred props without the rescue option' do
      expect do
        resolve_partial(
          { permissions: Inertia::Core::DeferProp.new { raise 'boom' } },
          'permissions'
        )
      end.to raise_error('boom')
    end
  end

  describe 'OnceProp' do
    it 'resolves once prop on initial load' do
      page = resolve({ locale: Inertia::Core::OnceProp.new { 'en' } })

      expect(page[:props][:locale]).to eq('en')
      expect(page[:onceProps]).to eq({ 'locale' => { prop: 'locale' } })
    end

    it 'once prop with custom key' do
      page = resolve({ locale: Inertia::Core::OnceProp.new(key: 'app-locale') { 'en' } })

      expect(page[:onceProps]).to eq({ 'app-locale' => { prop: 'locale' } })
    end

    it 'excludes once prop when already loaded by client' do
      props = { locale: Inertia::Core::OnceProp.new { 'en' }, timezone: 'UTC' }
      page = resolve(props, visit: { except_once: ['locale'] })

      expect(page[:props][:timezone]).to eq('UTC')
      expect(page[:props]).not_to have_key(:locale)
      # Metadata is still collected
      expect(page[:onceProps]).to eq({ 'locale' => { prop: 'locale' } })
    end

    it 'resolves nested once prop on initial load with dot-path metadata' do
      page = resolve({ config: { locale: Inertia::Core::OnceProp.new { 'en' } } })

      expect(page[:props][:config][:locale]).to eq('en')
      expect(page[:onceProps]).to eq({ 'config.locale' => { prop: 'config.locale' } })
    end

    it 'nested once prop with custom key and dot-path prop reference' do
      page = resolve({ config: { locale: Inertia::Core::OnceProp.new(key: 'app-locale') { 'en' } } })

      expect(page[:onceProps]).to eq({ 'app-locale' => { prop: 'config.locale' } })
    end

    it 'excludes nested once prop when already loaded' do
      page = resolve(
        { config: { locale: Inertia::Core::OnceProp.new { 'en' }, timezone: 'UTC' } },
        visit: { except_once: ['config.locale'] }
      )

      expect(page[:props][:config][:timezone]).to eq('UTC')
      expect(page[:props][:config]).not_to have_key(:locale)
      expect(page[:onceProps]).to eq({ 'config.locale' => { prop: 'config.locale' } })
    end

    it 'nested once metadata collected on exact partial request' do
      page = resolve_partial(
        { config: { locale: Inertia::Core::OnceProp.new { 'en' } } },
        'config.locale'
      )

      expect(page[:props][:config][:locale]).to eq('en')
      expect(page[:onceProps]).to eq({ 'config.locale' => { prop: 'config.locale' } })
    end

    it 'nested once metadata collected when parent is requested' do
      page = resolve_partial(
        { config: { locale: Inertia::Core::OnceProp.new { 'en' } } },
        'config'
      )

      expect(page[:props][:config][:locale]).to eq('en')
      expect(page[:onceProps]).to eq({ 'config.locale' => { prop: 'config.locale' } })
    end

    # Asking for `config` is asking for everything in it, held or not.
    it 'resends a held once prop when the partial reload names its parent' do
      props = { config: { locale: Inertia::Core::OnceProp.new { 'en' } } }

      page = resolve_partial(props, 'config', except_once: ['config.locale'])
      expect(page[:props]).to eq({ config: { locale: 'en' } })

      page = resolve_partial(props, 'other', except_once: ['config.locale'])
      expect(page[:props]).to eq({})
    end
  end

  describe 'DeferProp + once' do
    it 'suppresses deferred metadata when once-prop already loaded (non-partial)' do
      page = resolve({ posts: Inertia::Core::DeferProp.new(once: true) { [] } }, visit: { except_once: ['posts'] })

      expect(page).not_to have_key(:deferredProps)
    end

    it 'includes deferred + once metadata on first load' do
      page = resolve({ posts: Inertia::Core::DeferProp.new(once: true) { [] } })

      expect(page[:deferredProps]).to eq({ 'default' => ['posts'] })
      expect(page[:onceProps]).to eq({ 'posts' => { prop: 'posts' } })
    end

    it 'nested: suppresses deferred metadata when already loaded' do
      page = resolve(
        { feed: { posts: Inertia::Core::DeferProp.new(once: true) { [] } } },
        visit: { except_once: ['feed.posts'] }
      )

      expect(page).not_to have_key(:deferredProps)
    end

    it 'nested: includes deferred + once metadata on first load' do
      page = resolve({ feed: { posts: Inertia::Core::DeferProp.new(once: true) { [] } } })

      expect(page[:deferredProps]).to eq({ 'default' => ['feed.posts'] })
      expect(page[:onceProps]).to eq({ 'feed.posts' => { prop: 'feed.posts' } })
    end
  end

  describe 'closure returning prop type' do
    it 'closure returning defer prop is excluded from initial load' do
      resolved = false
      page = resolve({ notifications: lambda {
        Inertia::Core::DeferProp.new do
          resolved = true
          []
        end
      } })

      expect(page[:props]).not_to have_key(:notifications)
      expect(page[:deferredProps]).to eq({ 'default' => ['notifications'] })
      expect(resolved).to be false
    end

    it 'closure returning defer prop metadata is collected' do
      page = resolve({ notifications: -> { Inertia::Core::DeferProp.new(group: 'alerts') { [] } } })

      expect(page[:deferredProps]).to eq({ 'alerts' => ['notifications'] })
    end

    it 'closure returning merge prop resolves with metadata' do
      page = resolve({ posts: -> { Inertia::Core::MergeProp.new { [{ id: 1 }] } } })

      expect(page[:props][:posts]).to eq([{ id: 1 }])
      expect(page[:mergeProps]).to include('posts')
    end

    it 'closure returning once prop resolves with metadata' do
      page = resolve({ locale: -> { Inertia::Core::OnceProp.new { 'en' } } })

      expect(page[:props][:locale]).to eq('en')
      expect(page[:onceProps]).to eq({ 'locale' => { prop: 'locale' } })
    end

    it 'closure returning defer + merge prop is excluded with metadata' do
      page = resolve({ posts: -> { Inertia::Core::DeferProp.new(merge: true) { [{ id: 1 }] } } })

      expect(page[:props]).not_to have_key(:posts)
      expect(page[:deferredProps]).to eq({ 'default' => ['posts'] })
      expect(page[:mergeProps]).to include('posts')
    end

    it 'closure returning hash with optional prop excluded from initial load' do
      resolved = false
      page = resolve({
                       auth: lambda {
                         {
                           user: 'Jonathan',
                           permissions: Inertia::Core::OptionalProp.new do
                             resolved = true
                             ['admin']
                           end,
                         }
                       },
                     })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:permissions)
      expect(resolved).to be false
    end

    it 'closure returning hash with deferred prop excluded from initial load' do
      resolved = false
      page = resolve({
                       auth: lambda {
                         {
                           user: 'Jonathan',
                           notifications: Inertia::Core::DeferProp.new do
                             resolved = true
                             []
                           end,
                         }
                       },
                     })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:notifications)
      expect(page[:deferredProps]).to eq({ 'default' => ['auth.notifications'] })
      expect(resolved).to be false
    end

    it 'closure inside nested hash returning defer prop collects metadata' do
      page = resolve({
                       auth: lambda {
                         {
                           user: { name: 'Jonathan', email: 'jonathan@example.com' },
                           notifications: Inertia::Core::DeferProp.new(group: 'alerts') { [] },
                         }
                       },
                     })

      expect(page[:deferredProps]).to eq({ 'alerts' => ['auth.notifications'] })
    end

    # A prop met inside produced data is judged like one spelled in the props:
    # excluded by the visit, it is neither delivered nor announced.
    context 'when the visit excludes a path the closure produces' do
      it 'silences a merge prop the visit excludes' do
        page = resolve(
          { account: -> { { id: 1, notifications: Inertia::Core::MergeProp.new { [1] } } } },
          visit: { partial: true, except: ['account.notifications'] }
        )

        expect(page[:props][:account]).to eq({ id: 1 })
        expect(page).not_to have_key(:mergeProps)
      end

      it 'silences a once prop the visit excludes' do
        page = resolve(
          { account: -> { { id: 1, token: Inertia::Core::OnceProp.new { 'secret' } } } },
          visit: { partial: true, except: ['account.token'] }
        )

        expect(page[:props][:account]).to eq({ id: 1 })
        expect(page).not_to have_key(:onceProps)
      end

      it 'delivers and announces a prop the visit requests' do
        page = resolve(
          { account: -> { { id: 1, token: Inertia::Core::OnceProp.new { 'secret' } } } },
          visit: { partial: true, only: ['account.token'] }
        )

        expect(page[:props][:account]).to eq({ token: 'secret' })
        expect(page[:onceProps]).to eq({ 'account.token' => { prop: 'account.token' } })
      end
    end
  end

  describe 'prop type producing a prop type' do
    # The cache: option replaced the wrapped form; a produced cache prop is
    # stacking like any other.
    it 'refuses a cached prop produced by a once prop' do
      expect { resolve({ locale: Inertia::Core::OnceProp.new { Inertia::Core::CachedProp.new('locale') { 'en' } } }) }
        .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
    end

    it 'refuses a cached prop produced by a merge prop' do
      expect { resolve({ posts: Inertia::Core::MergeProp.new { Inertia::Core::CachedProp.new('posts') { [1] } } }) }
        .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
    end

    it 'once(cache:) resolves through the cache and announces onceProps' do
      runs = 0
      2.times do
        page = resolve({ locale: Inertia::Core::OnceProp.new(cache: 'locale') do
          runs += 1
          'en'
        end })

        expect(page[:props][:locale].to_json).to eq('"en"')
        expect(page[:onceProps]).to eq({ 'locale' => { prop: 'locale' } })
      end

      expect(runs).to eq(1)
    end

    it 'merge(cache:) resolves through the cache and announces mergeProps' do
      page = resolve({ posts: Inertia::Core::MergeProp.new(cache: 'posts_v2') { [{ id: 1 }] } })

      expect(page[:props][:posts].to_json).to eq('[{"id":1}]')
      expect(page[:mergeProps]).to include('posts')
    end

    it 'always(cache:) delivers the cached value even on an excluding partial' do
      page = resolve_partial({ other: 'x', auth: Inertia::Core::AlwaysProp.new(cache: 'auth') { { id: 1 } } }, 'other')

      expect(page[:props][:auth].to_json).to eq('{"id":1}')
    end

    it 'still refuses a prop type inside the cached value of once(cache:)' do
      expect { resolve({ posts: Inertia::Core::OnceProp.new(cache: 'poison') { Inertia::Core::DeferProp.new { 1 } } }) }
        .to raise_error(Inertia::Core::Error, /cannot be cached/)
    end

    # Producing any prop type is stacking. Composition happens in one prop's
    # options, where the combinations are validated; a chain never announces
    # a path twice, so cross-announcement conflicts are unrepresentable.
    it 'refuses a prop type produced by a prop block' do
      pagy = { page_name: 'p', previous_page: nil, next_page: 2, current_page: 1 }
      [
        Inertia::Core::MergeProp.new { Inertia::Core::DeferProp.new(group: 'alerts') { [] } },
        Inertia::Core::MergeProp.new { Inertia::Core::MergeProp.new { [1] } },
        Inertia::Core::OnceProp.new { Inertia::Core::MergeProp.new { [1] } },
        Inertia::Core::OnceProp.new(key: 'same') { Inertia::Core::OnceProp.new(key: 'same') { 1 } },
        Inertia::Core::MergeProp.new(deep_merge: true) do
          Inertia::Core::ScrollProp.new(metadata: pagy, deep_merge: true) { [1] }
        end
      ].each do |prop|
        expect { resolve({ posts: prop }) }
          .to raise_error(Inertia::Core::ResolutionError, /produces a prop type/)
      end
    end

    it 'names both types and the option alternative in the refusal' do
      expect { resolve({ posts: Inertia::Core::MergeProp.new { Inertia::Core::DeferProp.new { [] } } }) }
        .to raise_error(Inertia::Core::ResolutionError,
                        /`posts` \(MergeProp\) produces a prop type \(DeferProp\).*options/m)
    end

    it 'still selects a prop type from a plain closure at the key' do
      page = resolve({ posts: -> { Inertia::Core::DeferProp.new(merge: true) { [] } } })

      expect(page[:props]).not_to have_key(:posts)
      expect(page[:deferredProps]).to eq({ 'default' => ['posts'] })
      expect(page[:mergeProps]).to include('posts')
    end

    it 'refuses one once key claimed by two props' do
      props = { a: Inertia::Core::OnceProp.new(key: 'roles') { 1 }, b: Inertia::Core::OnceProp.new(key: 'roles') { 2 } }

      expect { resolve(props) }
        .to raise_error(Inertia::Core::ResolutionError, /share the `once` key `roles`/)
    end

    # Sibling props are separate claims, not a conflict.
    it 'allows different merge modes on different paths' do
      page = resolve({ a: Inertia::Core::MergeProp.new { [1] },
                       b: Inertia::Core::MergeProp.new(deep_merge: true) { { x: 1 } }, })

      expect(page[:mergeProps]).to eq(['a'])
      expect(page[:deepMergeProps]).to eq(['b'])
    end
  end

  describe 'excluded props are not resolved on initial load' do
    it 'both optional and deferred closures skip execution on initial load' do
      optional_resolved = false
      deferred_resolved = false
      page = resolve({
                       auth: {
                         user: 'Jonathan',
                         permissions: Inertia::Core::OptionalProp.new do
                           optional_resolved = true
                           ['admin']
                         end,
                         notifications: Inertia::Core::DeferProp.new do
                           deferred_resolved = true
                           []
                         end,
                       },
                     })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:permissions)
      expect(page[:props][:auth]).not_to have_key(:notifications)
      expect(optional_resolved).to be false
      expect(deferred_resolved).to be false
    end
  end

  describe 'ScrollProp' do
    let(:scroll_metadata) { { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 } }

    it 'nested scroll prop metadata is collected on initial load' do
      props = { feed: { posts: Inertia::Core::ScrollProp.new(metadata: scroll_metadata) { [{ id: 1 }] } } }
      resolver = described_class.new(props, evaluator: evaluator)
      resolved_props, metadata = resolver.resolve
      page = { props: resolved_props }.merge(metadata)

      expect(page[:props][:feed][:posts]).to eq([{ id: 1 }])
      expect(page[:scrollProps]).to eq('feed.posts' => { pageName: 'page', previousPage: nil, nextPage: 2,
                                                         currentPage: 1, reset: false, })
    end

    it 'nested scroll prop reset flag is set by reset header' do
      props = { feed: { posts: Inertia::Core::ScrollProp.new(metadata: scroll_metadata) { [{ id: 1 }] } } }
      resolver = described_class.new(props, evaluator: evaluator,
                                            visit: { partial: true, only: ['feed.posts'], reset: ['feed.posts'] })
      resolved_props, metadata = resolver.resolve
      page = { props: resolved_props }.merge(metadata)

      expect(page[:scrollProps]['feed.posts'][:reset]).to be true
    end

    it 'nested deferred scroll prop is excluded from initial load with metadata' do
      props = { feed: { posts: Inertia::Core::ScrollProp.new(defer: true, metadata: scroll_metadata) { [{ id: 1 }] } } }
      resolver = described_class.new(props, evaluator: evaluator)
      resolved_props, metadata = resolver.resolve
      page = { props: resolved_props }.merge(metadata)

      expect(page[:props]).not_to have_key(:feed)
      expect(page[:deferredProps]).to eq('default' => ['feed.posts'])
    end

    it 'nested scroll prop is included on partial request with metadata' do
      props = { feed: { posts: Inertia::Core::ScrollProp.new(metadata: scroll_metadata) { [{ id: 1 }] } } }
      resolver = described_class.new(props, evaluator: evaluator,
                                            visit: { partial: true, only: ['feed.posts'] })
      resolved_props, metadata = resolver.resolve
      page = { props: resolved_props }.merge(metadata)

      expect(page[:props][:feed][:posts]).to eq([{ id: 1 }])
      expect(page[:scrollProps]).to eq('feed.posts' => { pageName: 'page', previousPage: nil, nextPage: 2,
                                                         currentPage: 1, reset: false, })
    end
  end

  describe 'to_inertia protocol' do
    let(:deferred_serializer) do
      serializer = Object.new
      def serializer.to_inertia = { name: 'Jonathan', stats: Inertia::Core::DeferProp.new { 'expensive' } }
      def serializer.as_json(*) = { name: 'Jonathan', stats: 'expensive' }
      serializer
    end

    it 'resolves object responding to to_inertia' do
      serializer = Object.new
      def serializer.to_inertia = { name: 'Jonathan', email: 'jon@example.com' }

      page = resolve({ user: serializer })

      expect(page[:props][:user]).to eq({ name: 'Jonathan', email: 'jon@example.com' })
    end

    # A serializer may delegate to another one, so conversion repeats until the
    # value stops being a producer — otherwise the last object is serialized
    # with `as_json`, exposing every instance variable it holds.
    it 'resolves a chain of objects responding to to_inertia' do
      last = Object.new
      def last.to_inertia = { name: 'Jonathan' }
      middle = Object.new
      middle.define_singleton_method(:to_inertia) { last }
      first = Object.new
      first.define_singleton_method(:to_inertia) { middle }

      expect(resolve({ user: first })[:props][:user]).to eq({ name: 'Jonathan' })
      expect(resolve({ user: -> { first } })[:props][:user]).to eq({ name: 'Jonathan' })
      expect(resolve({ user: Inertia::Core::MergeProp.new { first } })[:props][:user]).to eq({ name: 'Jonathan' })
    end

    # A prop type has no key of its own here, so it cannot be addressed by
    # `only`/`except` or announced in the page metadata. Evaluating it inline
    # instead would silently invert its meaning — `optional { expensive }`
    # running on every first load — so the shape is refused. A cached prop is
    # the exception: caching is invisible to the client, so it works anywhere.
    context 'with a prop type used as an array element' do
      it 'refuses a prop type placed directly in an array' do
        expect { resolve({ a: [Inertia::Core::OptionalProp.new { 'x' }] }) }
          .to raise_error(Inertia::Core::ResolutionError, /`a\.0` places a OptionalProp in an array/)
      end

      it 'refuses a prop type a closure returns into an array' do
        expect { resolve({ a: [-> { Inertia::Core::DeferProp.new { 'x' } }] }) }
          .to raise_error(Inertia::Core::ResolutionError, /`a\.0`/)
      end

      it 'refuses a prop type nested deeper in an array' do
        expect { resolve({ a: [[Inertia::Core::MergeProp.new { 'x' }]] }) }
          .to raise_error(Inertia::Core::ResolutionError, /`a\.0\.0`/)
      end

      # Exclusion must not hide the shape every full load refuses.
      it 'refuses a prop type at an array index on every visit' do
        props = -> { { a: [1, Inertia::Core::AlwaysProp.new { 2 }, 3] } }

        expect { resolve(props.call) }
          .to raise_error(Inertia::Core::ResolutionError, /`a\.1` places a AlwaysProp in an array/)
        expect { resolve(props.call, visit: { partial: true, except: ['a.1'] }) }
          .to raise_error(Inertia::Core::ResolutionError, /`a\.1` places a AlwaysProp in an array/)
      end

      it 'allows a cached prop as an array element' do
        page = resolve({ a: [Inertia::Core::CachedProp.new('element_key') { 'x' }] })

        expect(page[:props][:a].map(&:to_json)).to eq(['"x"'])
      end

      it 'still allows a prop type that returns an array' do
        expect(resolve({ a: Inertia::Core::MergeProp.new { [{ id: 1 }] } })[:props][:a]).to eq([{ id: 1 }])
      end

      it 'still allows a prop type under a key inside an array' do
        page = resolve({ a: [{ stats: Inertia::Core::DeferProp.new { 'D' } }] })

        expect(page[:props][:a]).to eq([{}])
        expect(page[:deferredProps]).to eq('default' => ['a.0.stats'])
      end
    end

    it 'delivers an empty literal hash as it is' do
      expect(resolve({ a: {} })[:props]).to eq(a: {})
    end

    it 'keeps an array slot as an empty hash when a produced hash empties out' do
      props = { rows: [-> { { extra: Inertia::Core::OptionalProp.new { 'x' } } }, 'kept'] }

      expect(resolve(props)[:props][:rows]).to eq([{}, 'kept'])
    end

    # `rescue:` covers a failing data source. A shape the library itself refuses
    # is a mistake in the props, and hiding it behind `rescuedProps` would leave
    # the prop quietly missing — most likely on a deferred prop, which is
    # exactly where `rescue:` is used.
    context 'with rescue: true' do
      let(:visit) { { partial: true, only: ['a'] } }

      it 'still raises when a producer never settles' do
        looping = Object.new
        looping.define_singleton_method(:to_inertia) { looping }

        expect { resolve({ a: Inertia::Core::DeferProp.new(rescue: true) { looping } }, visit: visit) }
          .to raise_error(Inertia::Core::ResolutionError)
      end

      it 'still raises when a cached block holds a prop type' do
        inner = Inertia::Core::DeferProp.new { 'x' }
        props = { a: Inertia::Core::DeferProp.new(cache: 'rescue_key', rescue: true) { { inner: inner } } }

        expect { resolve(props, visit: visit) }.to raise_error(Inertia::Core::ResolutionError)
      end

      it 'still rescues a failing data source' do
        page = resolve({ a: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' } }, visit: visit)

        expect(page[:props]).to eq({})
        expect(page[:rescuedProps]).to eq(['a'])
      end
    end

    # Resolution is skipped for a value with nothing to resolve. That shortcut
    # is an optimisation, and it must not decide which keys a partial returns.
    it 'applies an indexed except path to an array of plain hashes' do
      props = { rows: [{ name: 'n', secret: 's' }] }
      visit = { partial: true, except: ['rows.0.secret'] }

      expect(resolve(props, visit: visit)[:props][:rows]).to eq([{ name: 'n' }])
    end

    it 'applies an indexed only path to an array of plain hashes' do
      props = { rows: [{ name: 'n', secret: 's' }] }
      visit = { partial: true, only: ['rows.0.name'] }

      expect(resolve(props, visit: visit)[:props][:rows]).to eq([{ name: 'n' }])
    end

    it 'keeps filtering below a second array level' do
      props = { rows: [[{ name: 'n', secret: 's' }]] }

      expect(resolve(props, visit: { partial: true, except: ['rows.0.0.secret'] })[:props][:rows])
        .to eq([[{ name: 'n' }]])
      expect(resolve(props, visit: { partial: true, only: ['rows.0.0.name'] })[:props][:rows])
        .to eq([[{ name: 'n' }]])
    end

    # A path is excluded by the visit or it is not: what produced the container
    # at that path — a literal, a closure, a serializer or a prop — makes no
    # difference.
    it 'filters an array a producer returned the same way' do
      props = { rows: Inertia::Core::AlwaysProp.new { [[{ name: 'n', secret: 's' }]] } }

      expect(resolve(props, visit: { partial: true, except: ['rows.0.0.secret'] })[:props][:rows])
        .to eq([[{ name: 'n' }]])
    end

    it 'reaches inside a hash a closure returned' do
      props = { user: -> { { name: 'n', stats: { views: 1 }, secret: 's' } } }

      expect(resolve(props, visit: { partial: true, only: ['user.stats'] })[:props][:user])
        .to eq({ stats: { views: 1 } })
    end

    # The visit excluded the path and `always` overrode it, so nothing the
    # visit says about paths below applies: the value ships whole.
    it 'delivers the whole value of an always prop the visit excluded' do
      props = { user: Inertia::Core::AlwaysProp.new { { name: -> { 'n' }, secret: 's' } }, other: 1 }

      expect(resolve(props, visit: { partial: true, only: ['other'] })[:props][:user])
        .to eq({ name: 'n', secret: 's' })
      expect(resolve(props, visit: { partial: true, except: ['user'] })[:props][:user])
        .to eq({ name: 'n', secret: 's' })
    end

    it 'silences a prop the visit excludes inside produced data' do
      stats = Inertia::Core::DeferProp.new { raise 'evaluated' }
      props = { user: -> { { name: 'n', stats: stats } } }

      expect(resolve(props, visit: { partial: true, only: ['user.name'] })[:props][:user]).to eq({ name: 'n' })
    end

    # A value that contains itself has no fixed point. Nesting is bounded, so
    # the cycle is refused once it drags the walk past the limit — and the
    # stack never runs out.
    context 'with a value that produces itself' do
      it 'refuses a serializer returning a hash that holds it' do
        looping = Object.new
        looping.define_singleton_method(:to_inertia) { { child: looping } }

        expect { resolve({ a: looping }) }
          .to raise_error(Inertia::Core::ResolutionError, /produces itself/)
      end

      it 'refuses a serializer returning an array that holds it' do
        looping = Object.new
        looping.define_singleton_method(:to_inertia) { [looping] }

        expect { resolve({ a: looping }) }
          .to raise_error(Inertia::Core::ResolutionError, /produces itself/)
      end

      it 'refuses an array that contains itself' do
        array = [1]
        array << array

        expect { resolve({ items: array }) }
          .to raise_error(Inertia::Core::ResolutionError, /produces itself/)
      end

      it 'refuses a hash and an array that contain each other' do
        hash = {}
        hash[:items] = [hash]

        expect { resolve({ data: -> { hash } }) }
          .to raise_error(Inertia::Core::ResolutionError, /produces itself/)
      end

      it 'still resolves many serializers side by side' do
        row = ->(i) { Object.new.tap { |o| o.define_singleton_method(:to_inertia) { { id: i } } } }

        expect(resolve({ a: (1..30).map { |i| row.call(i) } })[:props][:a].size).to eq(30)
      end

      # The same serializer instance at two sibling paths is reuse, not a cycle.
      it 'still resolves one serializer instance shared across keys' do
        shared = Object.new
        def shared.to_inertia = { id: 1 }

        expect(resolve({ a: shared, b: { c: shared } })[:props]).to eq(a: { id: 1 }, b: { c: { id: 1 } })
      end

      # Depth alone is not a cycle: a recursive serializer rendering a deep but
      # finite tree resolves however deep the data goes. Each level nests a
      # hash and an array, so 40 levels keeps the assertion under the JSON
      # generator's own nesting ceiling of 100.
      it 'resolves a recursive serializer tree deeper than the old chain limits' do
        build = nil
        build = lambda do |depth|
          Object.new.tap do |o|
            o.define_singleton_method(:to_inertia) do
              { body: depth, replies: depth.zero? ? [] : [build.call(depth - 1)] }
            end
          end
        end

        expect(resolve({ thread: build.call(40) })[:props].to_json).to include('"body":0')
      end
    end

    # A `Hash` or `Array` subclass can implement the serializer protocol too.
    # Deciding what a value is by its container type first left these scanned as
    # the container they inherit from — found to hold no producers, and passed
    # through with their raw contents in place of what `to_inertia` returns.
    context 'with a serializer that subclasses Hash' do
      let(:leaky) do
        Class.new(Hash) do
          def to_inertia = { safe: true }
        end
      end

      def leaking(klass)
        klass.new.tap { |hash| hash[:secret] = 'exposed' }
      end

      it 'serializes at a prop key' do
        expect(resolve({ a: leaking(leaky) })[:props][:a]).to eq({ safe: true })
      end

      it 'serializes as an array element' do
        expect(resolve({ a: [leaking(leaky)] })[:props][:a]).to eq([{ safe: true }])
      end

      it 'serializes inside a hash a closure produced' do
        row = leaking(leaky)

        expect(resolve({ a: -> { { row: row } } })[:props][:a]).to eq({ row: { safe: true } })
      end
    end

    # The serializer protocol is per-object, not per-class: an exact Hash with
    # a singleton `to_inertia` was scanned as a plain container, leaking its
    # raw contents from any position that pre-scans before unwrapping.
    context 'with an exact Hash carrying a singleton to_inertia' do
      def leaking_instance
        hash = { secret: 'exposed' }
        def hash.to_inertia = { safe: true }

        hash
      end

      it 'serializes at a prop key' do
        expect(resolve({ a: leaking_instance })[:props][:a]).to eq({ safe: true })
      end

      it 'serializes as an array element' do
        expect(resolve({ a: [leaking_instance] })[:props][:a]).to eq([{ safe: true }])
      end

      it 'serializes inside a hash a closure produced' do
        row = leaking_instance

        expect(resolve({ a: -> { { row: row } } })[:props][:a]).to eq({ row: { safe: true } })
      end
    end

    # A serializer is unwrapped to a fixed point before the hash it produces is
    # walked, so how many of them are stacked up cannot change which keys the
    # visit filters. Applying `to_inertia` only once left the chain's hash
    # looking like a value a prop had produced, and values are never filtered.
    it 'filters a serializer chain like a single serializer' do
      payload = { name: 'Jonathan', secret: 'hidden' }
      one = Object.new
      one.define_singleton_method(:to_inertia) { payload }
      two = Object.new
      two.define_singleton_method(:to_inertia) { one }

      visit = { partial: true, except: ['user.secret'] }

      expect(resolve({ user: one }, visit: visit)[:props][:user]).to eq({ name: 'Jonathan' })
      expect(resolve({ user: two }, visit: visit)[:props][:user]).to eq({ name: 'Jonathan' })
    end

    # A producer that manufactures a fresh producer each step never nests, so
    # the flat resolution loops carry a bound of their own. Each loop counts
    # its producers, so a chain alternating kinds is refused a little later —
    # but still refused.
    context 'with the resolution depth limit' do
      def serializer_chain(levels)
        levels.times.reduce('end') do |inner, _|
          Object.new.tap { |object| object.define_singleton_method(:to_inertia) { inner } }
        end
      end

      def alternating_chain(levels)
        levels.times.reduce('end') do |inner, _|
          serializer = Object.new.tap { |object| object.define_singleton_method(:to_inertia) { inner } }
          -> { serializer }
        end
      end

      it 'resolves a chain exactly at the limit' do
        expect(resolve({ a: serializer_chain(128) })[:props][:a]).to eq('end')
      end

      it 'raises one level past the limit' do
        expect { resolve({ a: serializer_chain(129) }) }
          .to raise_error(Inertia::Core::Error, /still unresolved after 128 producers/)
      end

      it 'still bounds a chain alternating closures with serializers' do
        expect(resolve({ a: alternating_chain(64) })[:props][:a]).to eq('end')
        expect { resolve({ a: alternating_chain(129) }) }
          .to raise_error(Inertia::Core::Error, /still unresolved after 128 producers/)
      end

      it 'bounds a chain of closures at the same limit' do
        closure_chain = ->(levels) { levels.times.reduce('end') { |inner, _| -> { inner } } }

        expect(resolve({ a: closure_chain.call(128) })[:props][:a]).to eq('end')
        expect { resolve({ a: closure_chain.call(129) }) }
          .to raise_error(Inertia::Core::Error, /still unresolved after 128 producers/)
      end

      it 'refuses the 129th producer without running it' do
        ran = 0
        chain = 129.times.reduce('end') do |inner, _|
          lambda do
            ran += 1
            inner
          end
        end

        expect { resolve({ a: chain }) }.to raise_error(Inertia::Core::Error, /128 producers/)
        expect(ran).to eq(128)
      end
    end

    it 'raises for a serializer whose to_inertia returns itself' do
      looping = Object.new
      looping.define_singleton_method(:to_inertia) { looping }

      expect { resolve({ user: looping }) }
        .to raise_error(Inertia::Core::Error, /produces itself/)
    end

    it 'resolves nested object responding to to_inertia' do
      serializer = Object.new
      def serializer.to_inertia = { name: 'Jonathan' }

      page = resolve({ auth: { user: serializer } })

      expect(page[:props][:auth][:user]).to eq({ name: 'Jonathan' })
    end

    it 'resolves to_inertia object with prop types inside' do
      serializer = Object.new
      def serializer.to_inertia
        {
          user: 'Jonathan',
          permissions: Inertia::Core::OptionalProp.new { ['admin'] },
        }
      end

      page = resolve({ auth: serializer })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:permissions)
    end

    it 'resolves to_inertia object with prop types on partial request' do
      serializer = Object.new
      def serializer.to_inertia
        {
          user: 'Jonathan',
          permissions: Inertia::Core::OptionalProp.new { ['manage-users'] },
        }
      end

      page = resolve_partial({ auth: serializer }, 'auth.permissions')

      expect(page[:props][:auth]).not_to have_key(:user)
      expect(page[:props][:auth][:permissions]).to eq(['manage-users'])
    end

    it 'resolves a serializer returned from a closure' do
      value = deferred_serializer
      page = resolve({ user: -> { value } })

      expect(page[:props][:user]).to eq({ name: 'Jonathan' })
      expect(page[:deferredProps]).to eq({ 'default' => ['user.stats'] })
    end

    it 'resolves a serializer returned from a prop block' do
      value = deferred_serializer
      page = resolve({ user: Inertia::Core::AlwaysProp.new { value } })

      expect(page[:props][:user]).to eq({ name: 'Jonathan' })
      expect(page[:deferredProps]).to eq({ 'default' => ['user.stats'] })
    end

    it 'resolves a serializer used as an array element' do
      page = resolve({ users: [deferred_serializer] })

      expect(page[:props][:users]).to eq([{ name: 'Jonathan' }])
      expect(page[:deferredProps]).to eq({ 'default' => ['users.0.stats'] })
    end
  end

  describe 'partial request filtering' do
    it 'builds a visit from protocol headers' do
      visit = Inertia::Core::Visit.from_headers(
        { 'X-Inertia-Partial-Component' => component, 'X-Inertia-Partial-Data' => 'a, ,b' },
        component: component
      )
      page = resolve({ a: -> { 1 }, b: -> { 2 }, c: -> { 3 } }, visit: visit)

      expect(page[:props]).to eq(a: 1, b: 2)
    end

    it 'builds a visit from a Rack env' do
      visit = Inertia::Core::Visit.from_env(
        { 'HTTP_X_INERTIA_PARTIAL_COMPONENT' => component, 'HTTP_X_INERTIA_PARTIAL_DATA' => 'a,b' },
        component: component
      )
      page = resolve({ a: -> { 1 }, b: -> { 2 }, c: -> { 3 } }, visit: visit)

      expect(page[:props]).to eq(a: 1, b: 2)
    end

    it 'accepts symbol paths in the visit lists' do
      page = resolve({ a: -> { 1 }, b: -> { 2 } }, visit: { partial: true, only: [:a] })

      expect(page[:props]).to eq(a: 1)
    end

    it 'does not serialize a to_inertia object at an excluded prop key' do
      serialized = false
      serializer = Class.new do
        define_method(:to_inertia) do
          serialized = true
          { heavy: true }
        end
      end
      page = resolve_partial({ users: [1], stats: serializer.new }, 'users')

      expect(serialized).to be false
      expect(page[:props]).to eq({ users: [1] })
    end

    it 'excludes a prop type even when it also implements to_inertia' do
      serialized = false
      prop_class = Class.new(Inertia::Core::BaseProp) do
        define_method(:to_inertia) do
          serialized = true
          'LEAK'
        end
      end
      page = resolve_partial({ users: [1], stats: prop_class.new(producer: ->(_c, **) { 'value' }) }, 'users')

      expect(serialized).to be false
      expect(page[:props]).to eq({ users: [1] })
    end

    it 'excludes props not in partial-data header' do
      page = resolve_partial(
        { name: 'Jonathan', email: 'jon@example.com' },
        'name'
      )

      expect(page[:props][:name]).to eq('Jonathan')
      expect(page[:props]).not_to have_key(:email)
    end

    it 'excludes nested props containing arrays when parent is not requested' do
      page = resolve_partial(
        { name: 'Jonathan', user: { name: 'Jonathon', tags: %w[ruby rails] } },
        'name'
      )

      expect(page[:props][:name]).to eq('Jonathan')
      expect(page[:props]).not_to have_key(:user)
    end

    it 'excludes nested always props when parent is not requested' do
      page = resolve_partial(
        { name: 'Jonathan',
          user: { name: 'Jonathon', errors: Inertia::Core::AlwaysProp.new { { name: 'required' } } }, },
        'name'
      )

      expect(page[:props][:name]).to eq('Jonathan')
      expect(page[:props]).not_to have_key(:user)
    end

    it 'excludes props via except header' do
      page = resolve(
        { auth: { user: 'Jonathan', token: 'secret' } },
        visit: { partial: true, only: ['auth'], except: ['auth.token'] }
      )

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:token)
    end

    it 'except header for parent suppresses all nested props' do
      page = resolve(
        { feed: { posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } }, other: 'value' },
        visit: { partial: true, only: %w[feed other], except: ['feed'] }
      )

      expect(page[:props]).not_to have_key(:feed)
      expect(page[:props][:other]).to eq('value')
      expect(page).not_to have_key(:mergeProps)
    end

    it 'partial request for parent resolves all nested prop types with dot-path metadata' do
      page = resolve_partial(
        {
          dashboard: {
            stats: 'visible',
            feed: Inertia::Core::MergeProp.new { [{ id: 1 }] },
            notifications: Inertia::Core::DeferProp.new { ['msg'] },
            settings: Inertia::Core::OptionalProp.new { { theme: 'dark' } },
            locale: Inertia::Core::OnceProp.new { 'en' },
          },
        },
        'dashboard'
      )

      expect(page[:props][:dashboard][:stats]).to eq('visible')
      expect(page[:props][:dashboard][:feed]).to eq([{ id: 1 }])
      expect(page[:props][:dashboard][:notifications]).to eq(['msg'])
      expect(page[:props][:dashboard][:settings]).to eq({ theme: 'dark' })
      expect(page[:props][:dashboard][:locale]).to eq('en')
      expect(page[:mergeProps]).to include('dashboard.feed')
      expect(page[:onceProps]).to eq({ 'dashboard.locale' => { prop: 'dashboard.locale' } })
      expect(page).not_to have_key(:deferredProps)
    end

    it 'except header suppresses nested merge metadata' do
      page = resolve(
        { feed: { posts: Inertia::Core::MergeProp.new { [{ id: 1 }] },
                  comments: Inertia::Core::MergeProp.new { [{ id: 2 }] }, } },
        visit: { partial: true, only: ['feed.posts', 'feed.comments'], except: ['feed.posts'] }
      )

      expect(page[:props][:feed]).not_to have_key(:posts)
      expect(page[:props][:feed][:comments]).to eq([{ id: 2 }])
      expect(page[:mergeProps]).to eq(['feed.comments'])
    end

    context 'with non-hash array elements' do
      it 'does not execute a closure at an unrequested index and keeps its slot as nil' do
        executed = false
        page = resolve_partial(
          { rows: [{ name: 'First' }, lambda {
            executed = true
            'LEAK'
          }, { name: 'Third' }] },
          'rows.0.name'
        )

        expect(executed).to be false
        expect(page[:props][:rows]).to eq([{ name: 'First' }, nil, {}])
      end

      it 'keeps the slot of a silenced cached prop at an unrequested index as nil' do
        page = resolve_partial({ rows: [Inertia::Core::CachedProp.new('row') { { name: 'First' } },
                                        { name: 'Second' }] },
                               'rows.1')

        expect(page[:props][:rows]).to eq([nil, { name: 'Second' }])
      end

      it 'does not execute a closure at an except-ed index and keeps its slot as nil' do
        executed = false
        page = resolve(
          { rows: [{ name: 'First' }, lambda {
            executed = true
            'LEAK'
          }, { name: 'Third' }] },
          visit: { partial: true, only: ['rows'], except: ['rows.1'] }
        )

        expect(executed).to be false
        expect(page[:props][:rows]).to eq([{ name: 'First' }, nil, { name: 'Third' }])
      end

      it 'does not serialize a to_inertia object at an unrequested index' do
        serialized = false
        serializer = Class.new do
          define_method(:to_inertia) do
            serialized = true
            { heavy: true }
          end
        end
        page = resolve_partial(
          { rows: [{ name: 'First' }, serializer.new] },
          'rows.0.name'
        )

        expect(serialized).to be false
        expect(page[:props][:rows]).to eq([{ name: 'First' }, nil])
      end

      it 'executes a closure at a requested index' do
        page = resolve_partial(
          { rows: ['zero', -> { 'one' }] },
          'rows.1'
        )

        expect(page[:props][:rows]).to eq([nil, 'one'])
      end

      it 'gives a Hash-subclass serializer at an unrequested index a nil slot' do
        serialized = false
        serializer = Class.new(Hash) do
          define_method(:to_inertia) do
            serialized = true
            { heavy: true }
          end
        end
        page = resolve_partial(
          { rows: [{ name: 'First' }, serializer.new] },
          'rows.0.name'
        )

        expect(serialized).to be false
        expect(page[:props][:rows]).to eq([{ name: 'First' }, nil])
      end
    end
  end

  describe 'non-partial Inertia request' do
    it 'behaves like initial load for nested prop types with dot-path metadata' do
      page = resolve({
                       dashboard: {
                         stats: 'visible',
                         feed: Inertia::Core::MergeProp.new { [{ id: 1 }] },
                         notifications: Inertia::Core::DeferProp.new { [] },
                         settings: Inertia::Core::OptionalProp.new { [] },
                       },
                     })

      expect(page[:props][:dashboard][:stats]).to eq('visible')
      expect(page[:props][:dashboard][:feed]).to eq([{ id: 1 }])
      expect(page[:props][:dashboard]).not_to have_key(:notifications)
      expect(page[:props][:dashboard]).not_to have_key(:settings)
      expect(page[:mergeProps]).to include('dashboard.feed')
      expect(page[:deferredProps]).to eq({ 'default' => ['dashboard.notifications'] })
    end
  end

  describe 'multiple nested prop types' do
    it 'handles all types together with dot-path metadata' do
      page = resolve({
                       dashboard: {
                         stats: 'visible',
                         feed: Inertia::Core::MergeProp.new { [{ id: 1 }] },
                         notifications: Inertia::Core::DeferProp.new { [] },
                         settings: Inertia::Core::OptionalProp.new { [] },
                         locale: Inertia::Core::OnceProp.new { 'en' },
                       },
                     })

      expect(page[:props][:dashboard][:stats]).to eq('visible')
      expect(page[:props][:dashboard][:feed]).to eq([{ id: 1 }])
      expect(page[:props][:dashboard][:locale]).to eq('en')
      expect(page[:props][:dashboard]).not_to have_key(:notifications)
      expect(page[:props][:dashboard]).not_to have_key(:settings)
      expect(page[:mergeProps]).to include('dashboard.feed')
      expect(page[:deferredProps]).to eq({ 'default' => ['dashboard.notifications'] })
      expect(page[:onceProps]).to eq({ 'dashboard.locale' => { prop: 'dashboard.locale' } })
    end

    it 'deeply nested merge prop uses full dot-path' do
      page = resolve({
                       app: { feed: { posts: Inertia::Core::MergeProp.new { [{ id: 1 }] } } },
                     })

      expect(page[:mergeProps]).to include('app.feed.posts')
    end
  end

  describe 'dot-notation key expansion' do
    it 'expands dot-notation key into nested hash' do
      page = resolve({ 'auth.user' => 'Jonathan' })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
    end

    it 'merges dot-notation key with existing nested hash' do
      page = resolve({
                       auth: { user: 'Jonathan' },
                       'auth.admin' => true,
                     })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth][:admin]).to be true
    end

    it 'deeply nested dot-notation key' do
      page = resolve({ 'app.auth.user.name' => 'Jonathan' })

      expect(page[:props][:app][:auth][:user][:name]).to eq('Jonathan')
    end

    it 'merges into the hash a closure or serializer produces' do
      serializer = Object.new
      def serializer.to_inertia = { role: 'admin' }

      page = resolve({ :user => -> { serializer }, 'user.name' => 'Jonathan' })

      expect(page[:props][:user]).to eq({ role: 'admin', name: 'Jonathan' })
    end

    it "leaves the caller's hash untouched when a dotted key writes into it" do
      input = { name: 'A' }

      page = resolve({ :user => input, 'user.age' => 1 })

      expect(page[:props][:user]).to eq({ name: 'A', age: 1 })
      expect(input).to eq({ name: 'A' })
    end

    it 'expands a dotted key into a frozen caller hash' do
      page = resolve({ :user => { name: 'A' }.freeze, 'user.age' => 1 })

      expect(page[:props][:user]).to eq({ name: 'A', age: 1 })
    end

    # The later plain key used to clobber the expanded hash, silently
    # dropping the dotted keys the reversed literal order kept.
    it 'merges dotted keys whatever the literal order' do
      page = resolve({ 'user.age' => 30, :user => -> { { name: 'x' } } })

      expect(page[:props][:user]).to eq({ name: 'x', age: 30 })
    end

    # Two spellings of one key are a mistake, not a merge: neither value is
    # rebuilt through the other, and neither wins silently.
    it 'refuses a canonical-key collision instead of merging through a serializing hash' do
      secret = { secret: 'raw' }
      def secret.as_json(*) = { safe: true }

      expect { resolve({ :user => secret, 'user' => { b: 1 } }) }
        .to raise_error(Inertia::Core::ResolutionError, /Props :user and "user" name the same path/)
    end

    it 'raises when the prop it merges into cannot hold keys' do
      expect { resolve({ :user => 'Jonathan', 'user.name' => 'Jon' }) }
        .to raise_error(Inertia::Core::ResolutionError, /Prop `user` \(String\) has nothing to merge into/)
    end

    # The message names the path the user wrote, not the segment the walk
    # happened to stop on — grepping for `b` in their props finds nothing.
    it 'names the full path when a deeper segment cannot hold keys' do
      expect { resolve({ :a => { b: 'oops' }, 'a.b.c' => 1 }) }
        .to raise_error(Inertia::Core::ResolutionError, /Prop `a\.b` \(String\).*`a\.b\.…`/m)
    end

    it 'tells you to return the keys from the block when the parent is a prop type' do
      expect { resolve({ :a => Inertia::Core::OptionalProp.new { 1 }, 'a.b' => 2 }) }
        .to raise_error(Inertia::Core::ResolutionError, /Return the nested keys from the prop's block/)
    end

    it 'dot-notation key with prop type' do
      page = resolve({
                       'auth.notifications' => Inertia::Core::DeferProp.new { ['msg'] },
                       'auth.user' => 'Jonathan',
                     })

      # Dot-notation keys should be expanded into nested hash
      expect(page[:props][:auth][:user]).to eq('Jonathan')
      expect(page[:props][:auth]).not_to have_key(:notifications)
      expect(page[:deferredProps]).not_to be_empty
    end

    it 'dot-notation key with closure' do
      page = resolve({ 'auth.user' => -> { 'Jonathan' } })

      expect(page[:props][:auth][:user]).to eq('Jonathan')
    end

    it 'dot-notation prop merges when parent is a closure' do
      page = resolve({
                       auth: lambda {
                         {
                           user: {
                             name: 'Jonathan',
                             email: 'jonathan@example.com',
                           },
                         }
                       },
                       'auth.user.permissions' => -> { %w[edit-posts delete-posts] },
                     })

      expect(page[:props][:auth][:user][:name]).to eq('Jonathan')
      expect(page[:props][:auth][:user][:email]).to eq('jonathan@example.com')
      expect(page[:props][:auth][:user][:permissions]).to eq(%w[edit-posts delete-posts])
    end
  end

  describe 'AlwaysProp errors' do
    it 'resolves AlwaysProp errors' do
      page = resolve({ name: 'Jon', errors: Inertia::Core::AlwaysProp.new { { email: 'required' } } })

      expect(page[:props][:errors]).to eq({ email: 'required' })
    end

    it 'includes AlwaysProp errors on partial request even when not requested' do
      page = resolve_partial(
        { name: 'Jon', errors: Inertia::Core::AlwaysProp.new { { email: 'required' } } },
        'name'
      )

      expect(page[:props][:name]).to eq('Jon')
      expect(page[:props][:errors]).to eq({ email: 'required' })
    end
  end
end

# Behaviour the fix releases pinned before the walk replaced the resolver;
# kept so the walk keeps their promises.
RSpec.describe Inertia::Core::PropsResolver, 'array slots and serializers inside arrays' do
  def resolve(props, visit: {})
    resolved_props, metadata = described_class.new(props, evaluator: evaluator, visit: visit).resolve
    { props: resolved_props }.merge(metadata)
  end

  def resolve_partial(props, *only)
    resolve(props, visit: { partial: true, only: only })
  end

  # A partial reload addresses array elements by index, so an element the
  # visit left out stays at its index as a placeholder: `{}` for one written
  # as a Hash, `nil` for anything else.
  it 'keeps an unrequested hash element as an empty hash' do
    page = resolve_partial({ rows: [{ name: 'First' }, { name: 'Second' }] }, 'rows.1.name')

    expect(page[:props][:rows]).to eq([{}, { name: 'Second' }])
  end

  it 'keeps an unrequested scalar element as a nil slot' do
    page = resolve_partial({ rows: [{ name: 'First' }, 'plain'] }, 'rows.0.name')

    expect(page[:props][:rows]).to eq([{ name: 'First' }, nil])
  end

  it 'leaves an array alone on a full load' do
    props = { rows: [{ name: 'n' }, 'plain', nil] }

    expect(resolve(props)[:props][:rows]).to eq([{ name: 'n' }, 'plain', nil])
  end

  # A relation answers `to_inertia` with its records (the Rails adapter adds
  # that), so a record's own `to_inertia` fires inside it as in a plain array.
  it 'resolves objects responding to to_inertia inside an array' do
    serializer = Object.new
    def serializer.to_inertia = { name: 'Jonathan' }

    page = resolve({ users: [serializer, { name: 'Claudia' }] })

    expect(page[:props][:users]).to eq([{ name: 'Jonathan' }, { name: 'Claudia' }])
  end

  it 'resolves prop types returned by a to_inertia object inside an array' do
    serializer = Object.new
    def serializer.to_inertia = { name: 'Jonathan', permissions: Inertia::Core::OptionalProp.new { ['admin'] } }

    page = resolve({ users: [serializer] })

    expect(page[:props][:users]).to eq([{ name: 'Jonathan' }])
  end

  it 'resolves an array-answering to_inertia exactly like the array itself' do
    relation = Object.new
    def relation.to_inertia = [{ name: 'kiwi' }]

    expect(resolve({ fruits: relation })).to eq(resolve({ fruits: [{ name: 'kiwi' }] }))
  end
end
