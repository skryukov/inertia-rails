# Cached Props

@available_since rails=3.21.0

Cached props use your server-side cache store to avoid recomputing expensive data on every request. When the cache is warm, the block is never evaluated — Inertia serves the pre-serialized JSON directly.

> [!NOTE]
> To understand when to use cached props vs once props vs HTTP caching, see the [Caching](/guide/caching) guide.

## Creating Cached Props

To create a cached prop, use the `InertiaRails.cache` method. This method requires a cache key and a block that returns the prop data.

```ruby
class DashboardController < ApplicationController
  def index
    render inertia: {
      stats: InertiaRails.cache('dashboard_stats', expires_in: 1.hour) { Stats.compute },
    }
  end
end
```

On the first request, the block is evaluated, serialized to JSON, and written to the cache. Subsequent requests serve the cached JSON without evaluating the block.

## Cache Keys

Cache keys determine when cached data is invalidated. Inertia supports several key formats.

### String Keys

The simplest form — a static string:

```ruby
InertiaRails.cache('sidebar_nav') { NavigationItem.tree }
```

### Active Record Objects

Pass an Active Record object to derive the key from `cache_key_with_version`. The cache is automatically invalidated when the record is updated:

```ruby
InertiaRails.cache(@post) { PostSerializer.render(@post) }
# Cache key: "inertia_rails_v2/posts/1-20260410120000"
```

### Array Keys

Pass an array to build a composite key:

```ruby
InertiaRails.cache(['stats', current_user.id]) { Stats.for(current_user) }
# Cache key: "inertia_rails_v2/stats/42"
```

## Cache Options

You can pass `expires_in` and `race_condition_ttl` options to control cache behavior:

```ruby
InertiaRails.cache('stats', expires_in: 1.hour) { Stats.compute }

InertiaRails.cache('stats', expires_in: 1.hour, race_condition_ttl: 10.seconds) { Stats.compute }
```

## Combining with Other Prop Types

The `cache` option can be passed to [deferred](/guide/deferred-props), [optional](/guide/partial-reloads#lazy-data-evaluation), [once](/guide/once-props), [merge](/guide/merging-props), and always props:

```ruby
class DashboardController < ApplicationController
  def index
    render inertia: {
      # Deferred prop with caching
      feed: InertiaRails.defer(cache: { key: 'feed', expires_in: 5.minutes }, group: 'feed') { current_user.feed },

      # Optional prop with caching
      categories: InertiaRails.optional(cache: @team) { @team.categories },

      # Once prop with caching
      countries: InertiaRails.once(cache: 'countries') { Country.all },
    }
  end
end
```

The `cache` option accepts the same key formats as `InertiaRails.cache`: strings, Active Record objects, arrays, and hashes with options.

```ruby
InertiaRails.defer(cache: { key: 'feed', expires_in: 5.minutes }) { current_user.feed }
```

> [!WARNING]
> Don't return prop types like `defer` or `optional` from a cached block, even nested inside a hash or array. The cache stores the value once and replays it for every request, but prop types do per-request work: they check what the visit asks for and write entries into the page metadata. Replayed JSON can do neither, so Inertia raises. Cache through the prop type's `cache:` option instead:
>
> ```ruby
> # Raises — the deferred prop can never be resolved from the cached JSON
> InertiaRails.cache('dashboard') { { totals: Stats.totals, feed: InertiaRails.defer { current_user.feed } } }
>
> # Works — each prop type caches its own value
> InertiaRails.cache('totals') { Stats.totals }
> InertiaRails.defer(cache: 'feed') { current_user.feed }
> ```
>
> The mirror rule applies to every prop type's block: it may not return any prop type — `InertiaRails.cache` included. Combine prop types as options instead (`defer(once: true)`), and cache with the `cache:` option (`once(cache: 'countries')`).

Objects responding to [`to_inertia`](/guide/serialization#the-to-inertia-protocol) are resolved before the value is cached, so serializers work inside a cached block.

## Cache Store

By default, Inertia uses `Rails.cache`. You can configure a different store via the [`cache_store`](/guide/configuration#cache_store) option. All cached prop keys are automatically prefixed with `inertia_rails_v2/` to avoid collisions. The `v2` marks the serialized format, which changed when serializers started resolving inside cached blocks. Entries written under the old `inertia_rails/` prefix are never read again, but they are not deleted either — they stay until their expiry passes or your cache store evicts them.

For more information on configuring cache stores, cache key strategies, and expiration policies, see the [Rails low-level caching guide](https://guides.rubyonrails.org/caching_with_rails.html#low-level-caching-using-rails-cache).
