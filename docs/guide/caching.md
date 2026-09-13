# Caching

Inertia Rails offers several complementary strategies for avoiding redundant work. Each solves a different problem, and you can combine them. If you're new to caching in Rails, start with the [Rails caching guide](https://guides.rubyonrails.org/caching_with_rails.html).

## Choosing a Strategy

| Strategy                             | What it saves               | Where it lives          | Best for                                  |
| ------------------------------------ | --------------------------- | ----------------------- | ----------------------------------------- |
| [HTTP caching](#http-caching)        | Entire response render      | Browser / CDN           | Pages tied to a single record's freshness |
| [Cached props](#prop-level-caching)  | Block evaluation            | Server-side cache store | Expensive queries or computations         |
| [Once props](#once-props)            | Bandwidth and serialization | Client memory           | Large or rarely-changing shared data      |
| [SSR caching](#ssr-response-caching) | SSR render request          | Server-side cache store | Avoiding redundant Node.js SSR calls      |

In short: **cached props skip computing**, **once props skip sending**, **HTTP caching skips rendering**, and **SSR caching skips the SSR request**.

These strategies are independent. A prop can be both cached on the server and marked as once so the client doesn't re-request it. HTTP caching can wrap an entire response that contains cached props. SSR caching can be layered on top of any combination.

### Which prop types support the `cache` option

Every prop type except `scroll` accepts the `cache` option — caching decorates how the value is computed and is independent of how it is delivered:

```ruby
InertiaRails.defer(cache: 'feed') { current_user.feed }
InertiaRails.once(cache: 'countries') { Country.all }
InertiaRails.merge(cache: 'toplist') { Post.top }
InertiaRails.always(cache: 'nav') { NavigationItem.tree }
```

Two notes:

- **Once props** layer two expirations. In `InertiaRails.once(cache: { key: 'plans', expires_in: 1.hour }, expires_in: 30.minutes) { Plan.all }`, the inner `expires_in` belongs to the server cache entry and the outer one to the client's copy: the client refetches after 30 minutes, but the server answers from the cache until the hour passes — lower the cache expiry when a refetch must see fresh data.
- **Scroll props** refuse the option: pagination data changes per page and the merge direction per request, so a static cache key would pin one page. Cache inside the block with `Rails.cache.fetch`, keying on the page.

## HTTP Caching

Rails provides built-in HTTP caching via `stale?` and `fresh_when`, and it works with Inertia responses out of the box.

@available_since rails=3.22.0

The same URL answers with different bodies: an HTML document on the initial visit, an Inertia JSON page on client-side visits, and prop subsets on partial reloads. Inertia Rails folds the Inertia request headers into every ETag automatically, so each representation gets its own ETag and a conditional request never receives a `304 Not Modified` backed by a different representation's body. Plain (non-Inertia) requests are unaffected.

> [!NOTE]
> On older adapter versions, differentiate the ETags yourself by adding `etag { request.inertia? }` to your `ApplicationController`.

### Using `stale?`

Use `stale?` as you normally would in Rails:

```ruby
class PostsController < ApplicationController
  def show
    @post = Post.find(params[:id])

    if stale?(@post)
      render inertia: { post: @post.as_json }
    end
  end
end
```

When the post hasn't changed, Rails returns a `304 Not Modified` response and skips rendering entirely.

### Using `fresh_when`

For simpler cases where you don't need conditional logic:

```ruby
class PostsController < ApplicationController
  def show
    @post = Post.find(params[:id])
    fresh_when(@post)

    render inertia: { post: @post.as_json }
  end
end
```

> [!WARNING]
> Automatic differentiation applies to ETags. A `fresh_when last_modified:` call with no `etag` produces no validator to differentiate, so a shared cache that ignores `Vary` can pair a `304` with the wrong representation. Pair `last_modified` with an `etag`.

If your conditionally cached responses still carry `Set-Cookie` headers — most shared caches refuse to store those — see [HTTP caching and XSRF cookie refresh](/cookbook/http-caching-and-xsrf-cookie-refresh).

## Prop-Level Caching

Prop-level caching stores computed values in your Rails cache store, skipping expensive block evaluation on cache hits. See the [Cached props](/guide/cached-props) guide for full details.

```ruby
class DashboardController < ApplicationController
  def index
    render inertia: {
      stats: InertiaRails.cache('dashboard_stats', expires_in: 1.hour) { Stats.compute },
      feed: InertiaRails.defer(cache: { key: 'feed', expires_in: 5.minutes }) { current_user.feed },
    }
  end
end
```

## Once Props

Once props are remembered by the client and excluded from subsequent responses. This saves bandwidth for data that rarely changes, such as shared navigation or role lists. See the [Once props](/guide/once-props) guide for full details.

```ruby
class ApplicationController < ActionController::Base
  inertia_share countries: InertiaRails.once { Country.all }
end
```

## SSR Response Caching

When SSR is enabled, each page load sends a request to the Node.js server. SSR caching stores these responses so identical page data is only rendered once. See [SSR response caching](/guide/server-side-rendering#ssr-response-caching) for full details.

```ruby
InertiaRails.configure do |config|
  config.ssr_cache = true
end
```
