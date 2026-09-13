# Inertia::Core

The framework-agnostic half of the [Inertia.js](https://inertiajs.com) server
protocol: prop types, their resolution against a visit, the page object, the
response a render answers with, the head tags, the configuration knobs, the
Rack middleware, the SSR client, and the request/response decisions every
adapter makes the same way. Plain Ruby, stdlib only (`json`, `uri`,
`net/http`, `digest`, `cgi`). `inertia_rails` is one adapter built on it;
another framework's adapter is a `Host`, a `Configuration`, and a render
helper. How the walk works is in [DESIGN.md](DESIGN.md).

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
| `instrument(event, payload) { }` | Observability seam: `:resolve_props` (`component:`, `partial:`) around a response's walk, `:cache_fetch` (`key:`, `hit:` settles inside the block) around a cached prop fetch, `:ssr` (`url:`, `component:`) around an SSR render. Call the block with the payload and return its result | yields, emitting nothing |
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

## Rendering a page

`Inertia::Core::Response` is one render for one request. It reads the request
form off the Rack env (`X-Inertia`, the partial-reload headers, the URL),
resolves the page once, tries SSR when it is on, and answers what the host
writes out. A Sinatra host, whole:

```ruby
class Dashboard < Sinatra::Base
  CONFIGURATION = Inertia::Core::Configuration.new(version: 'v1', use_script_element_for_initial_page: true)
  HOST = MyHost.new

  get('/dashboard') { render_inertia 'Dashboard', user: -> { current_user }, stats: Inertia::Core::DeferProp.new { stats } }

  private

  def render_inertia(component, props)
    inertia = Inertia::Core::Response.new(component, props, env: request.env, configuration: CONFIGURATION,
                                                            evaluator: Inertia::Core::PropEvaluator.new(self, host: HOST))
    headers inertia.headers(response.headers['Vary'])
    content_type inertia.content_type
    inertia.json? ? inertia.json : "<!DOCTYPE html><html><body>#{inertia.html}</body></html>"
  end
end
```

That Sinatra app, and the same page mounted on a Hanami router, are kept as
running code in [`spec/core/hosts`](../../../spec/core/hosts): they are the
reference adapters, held to one set of expectations
(`spec/core/hosts/support/inertia_host_examples.rb`). They mount real web
frameworks, so they run as a pass of their own:
`rspec -O spec/core/.rspec spec/core/hosts`.

`Response.new(component, props, env:, configuration:, evaluator:, **page)` —
`props` values may be plain data, closures, serializers (`to_inertia` /
`as_json`), or prop types; merge shared props in first with
`PropsMerger.merge(shared, props, deep: config.deep_merge_shared_data)`. The
page keywords: `url:` (the request's full path by default), `head:` (a
`MetaTagBuilder`), `flash:`, `shared_keys:`, `encrypt_history:`,
`clear_history:`, `preserve_fragment:`, `ssr_cache:`, and the resolver's
`observer:` and `eager:`.

| Answer | |
| --- | --- |
| `json?`, `partial?` | An Inertia request; a partial reload of this component |
| `headers(vary)` | `Vary` (folded into what the host already sends) and, for JSON, `X-Inertia` |
| `content_type` | `application/json` or `text/html` |
| `json` | The page as JSON |
| `html(nonce:)` | What a first load boots from: the SSR body, or `Protocol.root_element` — the page in a `<script data-page>` beside an empty root, or a root carrying it in `data-page` (`root_dom_id`, `use_script_element_for_initial_page`) |
| `head`, `ssr?` | What the SSR server adds to `<head>`, joined; whether SSR answered |
| `page`, `metadata` | The page hash; the resolver's metadata |

The page resolves the way every adapter must: `errors` always ships (partial
reloads included), the head prop is refused when `server_head` reserves it,
`prop_transformer` runs before the head tags are added, the title template
runs in the evaluator's context, and `:resolve_props` is instrumented through
the host. A host that builds its own page can still use the parts below:
`Visit.from_env(env, component:)`, `PropsResolver.new(props, evaluator:,
visit:).resolve`, `Page.new(...).to_h`, `Protocol.root_element(page, id:,
script:, nonce:)`.

## Head tags

`MetaTagBuilder` is the head of one render (`add`, `remove`, `clear`,
`title`); each `MetaTag` knows its wire form (`as_json`, camelCased, keyed by
`headKey`) and its markup (`to_html(inertia_attribute:)`, where a boolean
attribute such as `async: true` prints bare). Hand the builder to
`Response.new(head:)`: the tags ship as `_inertia_meta`, or as HTML strings
in the `head` prop under `server_head`, marked with
`configuration.head_attribute`. A `<script>` tag ships as `text/plain`
unless it is `application/ld+json`.

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
| `recorder_for(env)` | A DevTools recorder for the request; it sees the response as the protocol leaves it |

The cookie half of the XSRF handshake is the host's: set
`XsrfCookie::COOKIE` on protected responses, and ask
`XsrfCookie.refresh?(policy, request_method, cookie) { |cookie| still_valid? }`
whether the `:lazy` policy lets a safe request keep the cookie it carried.

The pure decisions are also available on their own under `Inertia::Core::Protocol`:

- `HEADER`, `VERSION_HEADER`, `LOCATION_HEADER` — the header names;
- `request?(headers)` — an Inertia request, by header presence;
- `vary(existing)` — `X-Inertia` folded once into a `Vary` value;
- `script_json(json)` — page JSON safe inside a `<script>` element;
- `root_element(page, id:, script:, nonce:)` — the markup a first load boots
  from, escaped for HTML;
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

## Precognition

```ruby
errors = Inertia::Core::Precognition.validate(env, form)   # nil unless the request is precognitive
halt Precognition.status(errors), Precognition.headers(errors), JSON.generate(Precognition.body(errors) || {})
```

`validate` normalizes a Hash, an object answering `valid?` and `errors`, or
one answering `to_hash` / `to_h`, filters by `Precognition-Validate-Only`,
and raises `DoublePrecognitionError` on a second call in one request.
`status` is 204 or 422, `headers` echoes `Precognition` and adds
`Precognition-Success` on a pass, `body` is `{ errors: }` or nil.
`request?(env)` and `validate_only(env)` read the request headers alone.
## DevTools

`Inertia::Core::Devtools` is the server half of the DevTools protocol: every
request becomes an entry the browser extension reads back, with a row per
prop the page carries. The recording, the entry format and the store are the
protocol's (`DEVTOOLS_CONTRACT.md` checks them against inertia-laravel); an
adapter subclasses for what only its framework has.

```ruby
class MyRecorder < Inertia::Core::Devtools::Recorder
  def nonce = MyApp::Request.new(env).csp_nonce           # the discovery tag's CSP nonce
end

class MyMiddleware < Inertia::Core::Rack::Middleware
  def recorder_for(env)
    env[MyRecorder::ENV_KEY] = MyRecorder.new(env, repository: REPOSITORY, host: HOST, limits: { limit: 100 })
  end
end

use Inertia::Core::Devtools::Middleware                # outermost: finishes the entry of a request that raised
use MyMiddleware, configuration: config

recorder = env[MyRecorder::ENV_KEY]                    # inside the render:
recorder&.render_started(component: component, shared_keys: [])
Inertia::Core::Response.new(component, props, env: env, ..., observer: recorder&.collector || Inertia::Core::Observer::NULL)
recorder&.page_rendered(inertia.page, inertia.metadata)
```

An adapter writes:

| Piece | Duty |
| --- | --- |
| A read endpoint | `GET /_inertia/devtools/entries` (`repository.all`, filtered by `component`/`type`/`exclude`/`limit`/`offset`) and `/entries/:id` (`repository.get`), gated outside development |
| A `Recorder` subclass | The hooks: `exchange(status, headers, body)` (an `Exchange` subclass), `nonce`, `buffered_body(body)` (nil for a stream), `refine_source(source, key)` (a share site narrowed to the key's line) |
| An `Exchange` subclass | What the framework knows and the env does not: `request_method` behind a form override, `url`, `request_parameters` (uploads summarized), `raw_request_body`, `response_content` (nil when the body is a stream), `route`. The defaults answer from the Rack env alone |
| A `Sources` subclass | The editor links: `component_path(component)` and `prop_line(file, line, key)`. The default links nothing |
| The wiring | `recorder_for(env)` on the Rack middleware, `Devtools::Middleware` outermost, and its own configuration knobs (storage path, TTL, limits) |

Everything else comes with the core: `Recorder` (the id and parent stamped on
every response, the discovery tag inserted into an HTML page load — never
into one carrying an `ETag` or `Last-Modified`, which `Rack::ETag` would not
recompute — and the entry persisted when the body closes), `Headers` (the
`X-Inertia-Devtools-*` names and the env keys they arrive under),
`RequestType.of` (initial, navigate, partial, deferred, poll, prefetch,
precognition, http), `Collector` (an `Observer` that assembles the page half
of the entry from the ledger: a row per delivered prop with its `shared`,
`reset` and `rescued` verdicts, and the value each row points at),
`EntryBuilder` (the entry shape, body limits and omission reasons), `Ulid`
(time-ordered ids, so newest-first is a string sort), `ScriptTag`, and
`EntriesRepository` (a file-backed store shared across processes, pruned by
TTL and capped per tab; subclass `report` to route a write failure into your
own reporting).

## Errors

`Inertia::Core::Error` is the base. `Inertia::Core::ResolutionError` means the
props or the page are mis-written. `Inertia::Core::SSRError` is an SSR failure
(`type`, `hint`, `stack`, `source_location` when the server sent them).
`Inertia::Core::DoublePrecognitionError` is a second `Precognition.validate`
in one request.

## Stability

This contract — the classes and methods named above — is what adapters may
depend on. Everything else under `Inertia::Core` is private and changes
without notice.
