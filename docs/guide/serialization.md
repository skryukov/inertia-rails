# Serializing Props

Props are encoded as JSON before they reach the page, so every prop value must be something Rails can serialize. Inertia Rails gives you three approaches, from the simplest to the most structured, plus a client-side option for key casing.

## Choosing an Approach

| Approach              | Best for                                      | Trade-off                                                      |
| --------------------- | --------------------------------------------- | -------------------------------------------------------------- |
| `as_json`             | Quick, inline shaping of a model or relation  | Shaping logic lives in the controller and is easy to duplicate |
| `to_inertia` protocol | Moving serialization into a plain Ruby object | You build the hash by hand                                     |
| Serializer library    | Reusable, composable resources at scale       | Adds a dependency                                              |

## Using `as_json`

Active Record models and relations respond to `as_json`, so you can shape them inline with the `only`, `except`, `methods`, and `include` options:

```ruby
class EventsController < ApplicationController
  def show
    event = Event.find(params[:id])

    render inertia: 'events/show', props: {
      event: event.as_json(
        only: [:id, :title, :start_date],
        include: { venue: { only: [:name, :city] } }
      )
    }
  end
end
```

This keeps you in full control of what leaves the server, but the shaping logic lives in the controller and is easy to duplicate across actions. Prefer explicit `only`/`except` over passing a bare model, so you don't leak columns you didn't mean to expose.

> [!NOTE]
> A `Hash` or `Array` subclass that defines its own `as_json` decides its own JSON, so Inertia hands it over untouched. Nothing inside it is resolved — a closure, serializer, or prop type among its entries raises rather than being sent unresolved — and partial reloads can't address paths inside it, so the whole container is sent whenever the prop is. Objects its `as_json` builds for itself, such as a serializer held in an instance variable, are serialized by Rails without `to_inertia`. Use a plain `Hash` or `Array` when you need any of that.

## The `to_inertia` Protocol

@available_since rails=3.19.0

Any object that responds to `to_inertia` is serialized by calling that method and using its return value as the prop. This lets you move serialization into a dedicated object:

```ruby
class UserSerializer
  def initialize(user)
    @user = user
  end

  def to_inertia
    { id: @user.id, name: @user.name, admin: @user.admin? }
  end
end

class UsersController < ApplicationController
  def show
    render inertia: 'users/show', props: {
      user: UserSerializer.new(User.find(params[:id])),
    }
  end
end
```

The return value is resolved like any other prop, so it can include prop types such as [`optional`](/guide/partial-reloads#lazy-data-evaluation), [`defer`](/guide/deferred-props), and [`merge`](/guide/merging-props) for per-attribute control:

```ruby
def to_inertia
  {
    id: @user.id,
    name: @user.name,
    stats: InertiaRails.defer { @user.compute_stats },
  }
end
```

@available_since rails=master

Inertia applies the `to_inertia` protocol wherever a prop is produced — placed directly, nested in a hash, returned from a lambda or a prop type, or used as an array element:

```ruby
render inertia: 'users/index', props: {
  users: User.all.map { |user| UserSerializer.new(user) },
  current: InertiaRails.defer { UserSerializer.new(current_user) },
}
```

`ActiveRecord::Relation` implements the protocol as `to_a`, so a record's `to_inertia` fires inside `users: User.all` exactly as it does inside a plain array. Records without `to_inertia` serialize through `as_json`, unchanged.

Prop types must sit under a key rather than as bare array elements. Everything a prop type does is addressed by prop key — `only` and `except` match paths, and `defer`, `merge`, `scroll`, and `once` announce paths in the page metadata — and an array element has an index instead. Inertia raises when it finds one, rather than silently inverting its meaning (an inline `optional` would be computed on every first load). `InertiaRails.cache` is the exception: caching is invisible to the client, so a cached prop works anywhere, including as an array element.

```ruby
# Raises — an omitted array slot would be indistinguishable from null
render inertia: 'users/index', props: { rows: [InertiaRails.optional { Stats.compute }] }

# Better — the prop type returns the array
render inertia: 'users/index', props: { rows: InertiaRails.optional { Stats.compute } }

# Better — the prop type sits under a key inside each element
render inertia: 'users/index', props: { rows: users.map { |u| { name: u.name, stats: InertiaRails.defer { u.stats } } } }
```

> [!NOTE]
> Prop types inside a serializer work wherever the serializer sits: `defer` and `optional` are still honoured, and still announced in the page metadata. Partial filtering reaches inside too: `only` and `except` address a serializer's attributes by path whether the serializer is placed directly as a prop value, returned from a lambda, or produced by a prop type. An excluded value is never evaluated, so an `always` returned from an excluded serializer is never met — place `InertiaRails.always` directly at the key when it must survive exclusion.

## Using a Serializer Library

For larger applications, a dedicated serializer library gives you reusable, composable resources. We recommend [`alba-inertia`](https://github.com/skryukov/alba-inertia), which pairs [Alba](https://github.com/okuramasafumi/alba) serializers with [Typelizer](https://github.com/skryukov/typelizer) to generate TypeScript types for your props automatically. It builds on the `to_inertia` protocol, so attributes can be marked `defer` or `optional` directly on the resource:

```ruby
class UserResource
  include Alba::Resource
  include Alba::Inertia::Resource

  attributes :id, :name

  attribute :stats, inertia: { defer: true } do |user|
    user.compute_stats
  end
end

class UsersController < ApplicationController
  def show
    render inertia: 'users/show', props: { user: UserResource.new(User.find(params[:id])) }
  end
end
```

## Shared Props

Everything above applies to [shared data](/guide/shared-data) too. `inertia_share` values are resolved by the same machinery, so you can share a serializer object or a hash containing prop types:

```ruby
inertia_share do
  {
    current_user: current_user && UserSerializer.new(current_user),
    notifications: InertiaRails.defer { current_user&.unread_notifications },
  }
end
```

## Key Casing

Rails conventionally uses `snake_case`, while JavaScript and TypeScript use `camelCase`. Converting between the two is a **round-trip** problem, not a one-way transformation:

- **Outgoing**: not just the prop keys, but the metadata paths in `deferredProps`, `mergeProps`, `deepMergeProps`, and friends.
- **Incoming**: form submissions, query parameters, and the `X-Inertia-Partial-Data` / `X-Inertia-Partial-Except` headers Rails reads to build [partial reloads](/guide/partial-reloads).

A server-side `deep_transform_keys` only touches part of the outgoing half: it renames the props themselves, but the metadata is built during resolution and merged into the page afterwards, so its paths are never remapped — and nothing incoming is touched at all. Deferred props, merges, infinite scroll, and form submissions all desync and silently break.

Do the conversion on the client instead, where a single layer owns both directions. [`inertia-caseshift`](https://github.com/skryukov/inertia-caseshift) does exactly this: it camelCases props, errors, flash, and metadata paths as they arrive, and snake_cases form data, query params, and partial-reload headers on the way out. Rails stays `snake_case` end to end, with no backend changes:

```js
// vite.config.ts
import caseShift from 'inertia-caseshift/vite'

export default defineConfig({
  plugins: [
    // ...your existing plugins
    caseShift(),
  ],
})
```

> [!WARNING]
> Don't reach for the [`prop_transformer`](/guide/configuration#prop-transformer) config to convert case. It only ever sees the resolved props, so the metadata paths described above are out of its reach and incoming data is untouched.
