# Inertia::Core

The framework-agnostic half of the [Inertia.js](https://inertiajs.com) server
protocol: prop types, their resolution against a visit, the page object, the
configuration knobs, the Rack middleware, the SSR client, and the
request/response decisions every adapter makes the same way. Plain Ruby,
stdlib only (`json`, `uri`, `net/http`, `digest`). `inertia_rails` is one
adapter built on it; another framework's adapter is a `Host`, a
`Configuration`, and a render helper. How the walk works is in
[DESIGN.md](DESIGN.md).

```ruby
require 'inertia/core'
```

## What an adapter provides

### 1. A Host — behaviour only the framework can supply

```ruby
class MyHost < Inertia::Core::Host
  def cache_store = MyApp.cache           # fetch(key, **options) { ... }
  def expand_cache_key(key) = "myapp/#{Array(key).join('/')}"
  def report_error(error, **context) = MyApp.errors.report(error, context)
  def instrument(event, payload = {}, &block) = MyApp.notify("#{event}.inertia", payload, &block)
end
```

| Method | Duty | Default |
| --- | --- | --- |
| `cache_store` | Object answering `fetch(key, **options) { ... }` for `cache:` props and SSR caching. Core stores the fully resolved value as a JSON **string** and replays it verbatim | raises — no portable store exists |
| `expand_cache_key(key)` | Turn whatever `cache:` named (string, array, object with `cache_key`) into the final store key, including any versioned namespace the host claims | raises |
| `report_error(error, **context)` | A handled error: a `rescue: true` prop's failure (`prop:` names its path), an SSR render that fell back to the client (`ssr: true`, `component:`) | writes to stderr |
| `serialize(value)` | The serialization boundary `rescue:` widens to and a cached value crosses before storage; make it the one your page crosses | `as_json` when the value answers it, else a json-gem round-trip |
| `instrument(event, payload) { }` | Observability seam: `:cache_fetch` (`key:`, `hit:` settles inside the block) around a cached prop fetch, `:ssr` (`url:`, `component:`) around an SSR render. Call the block with the payload and return its result | yields, emitting nothing |
| `dev_server_url` | The dev server the framework integration runs (Vite's, say): SSR renders through its `/__inertia_ssr` endpoint, uncached | nil |

`InertiaRails.host` is the Rails host.

### 2. A Configuration — the knobs an application sets

`Inertia::Core::Configuration` declares the framework-neutral options
(`version`, `encrypt_history`, `deep_merge_shared_data`, `prop_transformer`,
`component_path_resolver`, `convert_external_redirects`, `root_dom_id`,
`use_script_element_for_initial_page`, `server_head`, `meta_title_template`,
`xsrf_cookie_refresh`, `ssr_*`, ...). Behaviour belongs to the host, knobs to
the configuration: the cache store, for one, is the host's. Subclass and
declare your own:

```ruby
class MyConfiguration < Inertia::Core::Configuration
  option :layout, 'application'
end

config = MyConfiguration.default          # defaults + INERTIA_* env overlay
config.version = -> { assets.manifest_hash }
config.bind(action).version               # callables evaluate inside a context
```

`option(name, default, evaluate: true)` declares a reader, a writer and the
environment overlay (`INERTIA_<NAME>`, read the way the default means it: a
boolean default parses `1`/`0`, `yes`/`no`, `on`/`off`; a numeric one parses a
number). A reader may be redefined in the class body and reach the generated
one through `super`. `evaluate: false` hands a callable back uncalled, for the
options a render invokes itself (`on_ssr_error`, `meta_title_template`).
Options stay sparse: `merge` and `merge!` combine two, `with_defaults(parent)`
finalizes a layered one and freezes it.

### 3. An evaluation context per request

Prop blocks run via `instance_exec` inside an object the adapter chooses — the
controller in Rails, the action or app instance elsewhere — and the host goes
with it, so two adapters in one process cannot step on each other:

```ruby
evaluator = Inertia::Core::PropEvaluator.new(context, host: host)
```

## Resolving props

```ruby
visit = Inertia::Core::Visit.from_env(env, component: 'Dashboard')   # or from_headers(headers, component:)
props, metadata = Inertia::Core::PropsResolver.new(props, evaluator: evaluator, visit: visit).resolve
Inertia::Core::Page.new(component: 'Dashboard', props: props, metadata: metadata, url: url, ...).to_h
```

- `props` values may be plain data, closures, serializers (`to_inertia`, or a
  container with its own `as_json`), or prop types, at any depth. Merge shared
  props in first with `PropsMerger.merge(shared, props, deep:)`, which keeps
  one spelling per key and leaves serializers whole. Top-level String keys
  containing dots expand (`'user.name' => ...`).
- `Visit.from_headers(headers, component:)` takes anything answering `[]`
  with canonical names (`X-Inertia-Partial-Data`, `-Partial-Except`,
  `-Partial-Component`, `X-Inertia-Reset`, `-Except-Once-Props`,
  `-Infinite-Scroll-Merge-Intent`); `from_env` reads the `HTTP_*` keys.
- Every prop type takes keyword options plus a block (or `value:`);
  `CachedProp` takes its key positionally:

  ```ruby
  OptionalProp.new(**options, &block)                       # cache:, once:, merge:, live: families
  DeferProp.new(group: 'default', rescue: false, **, &block)
  MergeProp.new(deep_merge: false, match_on:, append:, prepend:, **, &block)
  OnceProp.new(key: nil, expires_in: nil, fresh: false, **, &block)
  AlwaysProp.new(value: ...)
  CachedProp.new('key_or_array_or_record', **store_options, &block)
  ScrollProp.new(metadata: pagination, wrapper:, group:, defer:, optional:, **, &block)
  LiveProp.new(on: 'MessageCreated', channel: 'chat.1', throttle: nil, &block)
  ```

  Invalid combinations raise `ArgumentError` at construction; shapes the walk
  cannot ship (a prop type produced by another, a prop at an array index, a
  producer that never settles) raise `ResolutionError` while resolving.
- `metadata` is the hash of page-object keys the client understands
  (`deferredProps`, `mergeProps`, `prependProps`, `deepMergeProps`,
  `matchPropsOn`, `onceProps`, `scrollProps`, `liveProps`, `rescuedProps`). `Page` merges
  it; `extensions:` merges an adapter's own keys the same way.
- `eager: true` resolves deferred and optional props on a full load (for
  tests and broadcasts); `observer:` is an `Inertia::Core::Observer` subclass whose
  `walked(ledger)` receives the `Inertia::Core::Ledger` once the walk is done:
  every prop met with its verdict, and every rescued error. The page metadata
  is derived from the same ledger.
- `ScrollMetadata.register_adapter(klass)` adds a pagination adapter
  (`match?(metadata)`, `call(metadata, **options)`, optional
  `accepted_options`); the core ships only the Hash and bare-fields forms.

## The page object

`Inertia::Core::Page.new(component:, props:, url:, version:, encrypt_history:,
clear_history:, flash:, shared_keys:, preserve_fragment:, metadata:,
extensions:).to_h` is the envelope the client receives. `flash`, `sharedProps`
and `preserveFragment` ship only when set; `metadata` is the hash of page-object
keys the client understands (`deferredProps`, `mergeProps`, ...); `extensions`
merges an adapter's own keys the same way, and a key that would replace the
envelope or the metadata raises `ResolutionError`.

## The HTTP conventions

`Inertia::Core::Rack::Middleware` does the response side for any Rack app:

```ruby
use Inertia::Core::Rack::Middleware, configuration: config
```

- copies `X-XSRF-TOKEN` to `X-CSRF-Token` before the app runs;
- a `301/302/303` to another origin becomes `409` + `X-Inertia-Location`
  (when `convert_external_redirects`), other headers intact;
- a `301/302` after `PUT/PATCH/DELETE` becomes `303`;
- a GET whose `X-Inertia-Version` differs from `configuration.version`
  becomes `409` + `X-Inertia-Location: <full URL>` + `X-Inertia-Version`.

Mount it inside the session middleware: a location response keeps the app's
headers, `Set-Cookie` included.

Every protected hook is handed the same `Request`, which carries the `env`
and reads the origin the client reached off the proxy headers (`Forwarded:
proto=`, `X-Forwarded-Proto` from the front, `X-Forwarded-Ssl`, `HTTPS=on`,
`X-Forwarded-Host`, `X-Forwarded-Port`, an IPv6 authority):

| Hook | For |
| --- | --- |
| `request_for(env)` | Your framework's own request: subclass `Rack::Request` and override what it knows better (`fullpath` before a routing rewrite, say) |
| `configuration_for(request)` | The configuration this route or controller carries; `nil` leaves the request alone |
| `inertia_request?(request)` | Endpoints that opt out of Inertia handling |
| `call_app(env)` | Wrapping the app call |
| `after_app(request, status, stale:)` | Consuming per-visit session state, unless the visit goes on |
| `refresh_response(request, configuration, headers, body)` | What a stale client is sent, e.g. keeping the flash |

The pure decisions are also available on their own under `Inertia::Core::Protocol`:

- `HEADER`, `VERSION_HEADER`, `LOCATION_HEADER` — the header names;
- `request?(headers)` — an Inertia request, by header presence;
- `vary(existing)` — `X-Inertia` folded once into a `Vary` value;
- `script_json(json)` — page JSON safe inside a `<script>` element;
- `Version.stale?(client, server)` — a numeric server version compares
  numerically, anything else as the strings the header carries;
- `Redirect.redirect?(status)`, `Redirect.status_for(method, status)` — a
  `301/302` after `PUT/PATCH/DELETE` becomes `303`;
- `Redirect.external?(location, scheme:, host:, port:)` — whether a redirect
  leaves the origin the request came in on;
- `location_headers(url, version:)` and `location_response(url, version:)` —
  the `409` + `X-Inertia-Location` (+ `X-Inertia-Version`) that tells the
  client to make a full page visit.

## SSR

`Inertia::Core::SSR::Client` renders a page through the SSR server on a first
load, falling back to the client when the server is off, the bundle is
missing (`ssr_bundle`), or the render failed (`on_ssr_error`,
`ssr_raise_on_error`). It renders through `Host#dev_server_url` when one is
up (uncached), caches through `Host#cache_store` under `ssr_cache`, and
reports a failure through `Host#report_error(error, ssr: true, component:)`:

```ruby
Inertia::Core::SSR::Client.new(config, page: page, host: host).render
# => { 'head' => [...], 'body' => '...' } or nil
```

## Broadcasting live props

```ruby
payload = Inertia::Core::Broadcast.props({ messages: -> { room.messages } }, evaluator: evaluator)
# => { '__inertia' => { 'props' => { 'messages' => [...] } } }  — embed in the broadcast event
```

## Errors

`Inertia::Core::Error` is the base. `Inertia::Core::ResolutionError` means the
props or the page are mis-written. `Inertia::Core::SSRError` is an SSR failure
(`type`, `hint`, `stack`, `source_location` when the server sent them).

## Stability

This contract — the classes and methods named above — is what adapters may
depend on. Everything else under `Inertia::Core` is private and changes
without notice.
