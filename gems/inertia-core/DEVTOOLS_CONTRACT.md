# DevTools contract (from inertia-laravel PR #892)

Source: https://patch-diff.githubusercontent.com/raw/inertiajs/inertia-laravel/pull/892.diff
(line numbers below refer to that diff). Verdicts compare it with the
Ruby implementation in `gems/inertia-core/lib/inertia/core/devtools/` and
`lib/inertia_rails/devtools/`. Where the docs page
(https://inertiajs.com/docs/v3/advanced/devtools) says nothing, the extension
itself is cited: https://github.com/inertiajs/inertia-devtools at `8e9d1e9`
(v0.8.1), and inertia-laravel's `src/DevTools/` at the matching release.

Verdict legend: MATCH / DIVERGES / N/A (Laravel-only, not verifiable here).
"+" marks something the Ruby side adds on top of the contract.

## A. Stored entry envelope

| # | Contract (quoted) | Verdict |
|---|---|---|
| A1 | `IncomingEntry::toArray` top-level keys: `'__meta'`, `'http'`, `'props'`, `'propValues'`, `'route'`, `'renderSource'`, `'componentPath'` (L464-486) | MATCH |
| A2 | `__meta` keys: `id, tabUuid, batchId, timestamp, utime, method, url, component, requestType, status, redirectLocation, serverTimingMs, visitId` (L466-479) | MATCH, + `error: {class, message}` when the action raised |
| A3 | `timestamp` = `Carbon::createFromTimestampMs(..., 'UTC')->format('Y-m-d\TH:i:s.v\Z')`: ISO-8601 UTC, milliseconds, literal `Z` (L456) | MATCH (`Time#utc.iso8601(3)`) |
| A4 | `utime` = `microtime(true)` float seconds (L455) | MATCH |
| A5 | `http` = `['requestHeaders' => [], 'responseHeaders' => [], 'requestBody' => null, 'responseBody' => null]` (L436) | MATCH |
| A6 | `route` default `['name' => null, 'uri' => '', 'action' => null]`, optional `actionSource => {file, line}`; the collector's route `method` is not copied into the entry (L445, L1452-1466) | MATCH |
| A7 | `renderSource` nullable `{file, line}`; `componentPath` nullable string (L448-450) | MATCH |
| A8 | `schemaVersion => 1` exists only in the collector payload (L360), never in the stored entry | MATCH (never emitted) |

## B. Headers

| # | Contract (quoted) | Verdict |
|---|---|---|
| B1 | Response `X-Inertia-Devtools-Id` "stamped on every response with the entry's ULID" (L605, L2459) | MATCH |
| B2 | Response `X-Inertia-Devtools-Parent-Out` = prefetch ? own id : `$batchId ?? $id` (L612, L2543-2550) | MATCH |
| B3 | Request `X-Inertia-Devtools-Parent` -> `batchId`, read only when `X-Inertia` is present (L2558-2560, test L5294-5307) | MATCH |
| B4 | Request `X-Inertia-Devtools-Tab` -> `tabUuid` (L622, L1367) | MATCH |
| B5 | Request `X-Inertia-Devtools-Visit` -> `visitId` (L628, L1369) | MATCH |
| B6 | Request `X-Inertia-Devtools-Deferred` -> request type `deferred`, also gates defer classification (L635, L1500, L1905) | MATCH |
| B7 | Request `X-Inertia-Devtools-Poll` -> request type `poll` (L642, L1504) | MATCH |
| B8 | Request `Precognition` header -> request type `precognition` (L3046, L1492) | DIVERGES (before): an empty `Precognition:` header counted in Ruby (`env['HTTP_PRECOGNITION']` truthy) and not in PHP. Fixed in the rebuild: empty reads as absent |
| B9 | `DevToolsHeader::read` returns null for absent or empty string (L647-652) | MATCH |
| B10 | Excluded paths get no devtools headers at all (test L4995-5002) | MATCH |
| B11 | Response `X-Inertia-Devtools-Base-Path` = `$request->getBaseUrl()` when non-empty (`DevToolsHeader.php:20`). The service worker reads it (`src/background.ts:66-75`) and fetches `${basePath}/_inertia/devtools/entries/${id}` itself; a 404 is final, no retry. Not on the docs page | MATCH (Rack's `SCRIPT_NAME`, the prefix the server mounted the app under; empty at the root, so the header is absent there) |

The request headers `-Parent`, `-Tab`, `-Visit`, `-Deferred` and `-Poll` are
sent only by a client created with `createInertiaApp({ dev: true })`; without
it the server sees plain Inertia requests, so every entry is `navigate` /
`partial` and batches never form.

## C. Request type

| # | Contract (quoted) | Verdict |
|---|---|---|
| C1 | Enum values: `navigate, partial, deferred, poll, prefetch, initial, http, precognition` (L518-528) | MATCH |
| C2 | Precedence: precognition > non-Inertia (`initial` if payload has non-empty string component, else `http`) > deferred > poll > partial (`X-Inertia-Partial-Component`) > prefetch > navigate (L1488-1517) | MATCH |
| C3 | `initial` requires `is_string($payload['component']) && !== ''` (L1524-1532) | MATCH (a collector exists only once a component renders; Rails always resolves a String component) |
| C4 | Prefetch = Laravel `$request->prefetch()`: `strcasecmp` of `Purpose`, `Sec-Purpose`, `X-Moz` against `prefetch` (test L5196) | DIVERGES (before): Ruby matched `include?('prefetch')` case-sensitively, so `Purpose: Prefetch` was missed. Fixed in the rebuild: `casecmp?` |
| C5 | Redirect responses keep request intent (`navigate` + 302 + redirectLocation) (test L5247-5259) | MATCH |

## D. Prop classification

| # | Contract (quoted) | Verdict |
|---|---|---|
| D1 | `inertiaType` wire values: `always, defer, optional, merge, scroll, once`; plain value -> `null` (L499-507, L1959-1970) | MATCH, + `live: true` flag for live props (`inertiaType` stays null) |
| D2 | DeferProp reads as `defer` + `deferGroup` ONLY under the deferred header; on a manual partial reload `inertiaType` is null and no `deferGroup` key (L1888-1891, L1963, test L3463-3496) | MATCH |
| D3 | Other deferrables (`scroll->defer('g')`) carry `deferGroup` regardless of the header; default group `'default'` (L1912-1923, tests L5457-5482) | MATCH (`Announcements::Defer::DEFAULT_GROUP = 'default'`; a scroll prop's group is nil unless `defer:`) |
| D4 | `once` = `Onceable && shouldResolveOnce()` independent of type (L1897, test L5484-5502) | MATCH (read from `onceProps` in the page metadata rather than the prop; same answer) |
| D5 | `mergeDirection`: `'prepend'` when `prependsAtRoot()` or (nested prepend && no nested append); else `'append'`; null when not mergeable. Scroll default `append`. Mixed nested reads `append`. Direction is read from the prop, "so it survives deep merges" and a reset (L1939-1953, tests L5504-5558) | DIVERGES, deliberate: direction is read from the page metadata, so a reset prop carries no `mergeDirection` (Rails spec "flags a reset prop and drops its merge direction" pins it). `deep_merge` + `prepend` is refused by the Ruby prop model, so that sub-case is N/A |
| D6 | `deepMerge` = `shouldDeepMerge() \|\| count(matchesOn()) > 0` (L1929-1932) | MATCH |
| D7 | `reset` = path in `X-Inertia-Reset` comma list; empty header never resets (L1896, L1975-1978) | MATCH (via `outcome.reset?`) |
| D8 | Per-prop entry keys: `shared` (bool, always), `inertiaType` (always, nullable), then only-when-set: `deferGroup, shareSource, reset, once, mergeDirection, deepMerge, rescued, renderSource` (L177-208, L272-275) | MATCH, + `live` |
| D9 | `shared` = top-level key is in the shared props (first dotted segment) (L178, L2491-2502) | MATCH |
| D10 | Prune: dotted paths dropped unless `shared === true \|\| inertiaType !== null \|\| count(meta) > 2`; every top-level path kept (L287-302) | MATCH |
| D11 | Unresolved optional props are absent from `props` (test L3408) | MATCH (only delivered outcomes are recorded) |
| D12 | `propValues`: only for kept paths, plucked from the JSON-normalized resolved props, nested objects stored once under their path (L312-346, test L3389-3402) | MATCH (plucked from the page after the prop transformer, which Laravel has no equivalent of) |
| D13 | Rescued deferred prop: `inertiaType: 'defer'`, `rescued: true`, absent from `propValues` (L2378-2381, test L3498-3519) | MATCH |
| D14 | Array element index paths are not recorded as separate props unless badged (`tags.0` absent) (test L3394-3397) | MATCH (`rows.1.tag` is kept when the element carries an `always`) |

## E. Redaction

| # | Contract (quoted) | Verdict |
|---|---|---|
| E1 | Default keys: `password, password_confirmation, current_password, token, _token, access_token, refresh_token, secret, client_secret, api_key` (L57-68) | MATCH (`devtools_redact_keys`), + the app's `filter_parameters` |
| E2 | Default headers: `cookie, set-cookie, authorization, proxy-authorization, x-xsrf-token, x-csrf-token` (L70-77) | MATCH (`devtools_redact_headers`) |
| E3 | Markers `'[REDACTED]'` and `'[UNSERIALIZABLE]'` (L1995-1997) | MATCH |
| E4 | Key redaction is case-insensitive, recursive, replaces the whole subtree (L2039-2050, test L5720-5735) | MATCH |
| E5 | Headers flattened to strings, multi-values joined `', '`, sensitive names replaced (L2056-2069, test L4544-4562) | MATCH, + URL-bearing headers (`location`, `referer`, `x-inertia-location`, ...) get their query redacted |
| E6 | URL redaction on `url` and `redirectLocation` keys: sensitive query params (incl. nested `filter[secret]`) -> `[REDACTED]`; unparseable returned unchanged (L2095-2171, tests L5737-5767) | DIVERGES, deliberate: an unparseable query is dropped to `?[REDACTED]` instead of stored raw (fail closed; both suites pin it) |
| E7 | Storage pass = redact keys over the whole payload + redact urls + redact header bags + sanitize (L2023-2032) | DIVERGES, deliberate: each surface is redacted once when captured; the storage pass only redacts URLs and sanitizes. Running the key filter over the whole entry, as Laravel does, would replace the metadata row of a prop *named* `password` with the marker; the Rails spec "keeps metadata for props named like sensitive keys" pins the Ruby choice |
| E8 | `propValues` redacted with the key list and sanitized at build time (L1409-1413) | MATCH |

## F. Bodies and redirect

| # | Contract (quoted) | Verdict |
|---|---|---|
| F1 | Body shape `{status: present\|empty\|omitted, value?, reason?}` (L1554) | MATCH |
| F2 | requestBody: write method without `X-Inertia` -> `omitted / non-inertia-request` (L1558-1562) | MATCH |
| F3 | requestBody: JSON body decoded + redacted; empty -> `empty` (L1566-1570) | MATCH |
| F4 | requestBody: form input redacted, uploads summarized `{name, size (null if invalid), mimeType}` (L1572-1576, L1751-1774) | MATCH (size is always reported) |
| F5 | requestBody: raw content invalid UTF-8 -> `omitted / binary`; any other raw string stored as `present` (L1731-1742) | DIVERGES, deliberate: a raw body is stored only when it parses as JSON (redactable by key); everything else is `omitted / unserializable` (Laravel would store `password=hunter2` verbatim under `text/plain`), + a 256 000-byte cap on the raw request body |
| F6 | responseBody for an Inertia render: page object JSON-normalized then redacted, `status: present` (L1598-1634) | MATCH |
| F7 | responseBody raw: non-textual -> `omitted/non-textual`; streamed -> `omitted/streamed`; > 256_000 bytes -> `omitted/too-large`; JSON decoded+redacted; malformed JSON -> raw string; invalid UTF-8 -> `omitted/binary`; `''` -> `empty` (L1642-1673) | DIVERGES, deliberate: textual non-JSON (HTML, plain text) is `omitted / non-inertia-response` and JSON that is not an object or array (or does not parse) is `omitted / unserializable`, rather than stored raw; the other reasons match. The response to an action that raised is `omitted / non-inertia-response` with `__meta.error` alongside |
| F11 | Omitted reasons the extension has words for (`src/types.ts:56-63`, `src/panel/lib/bodies.ts` @ 8e9d1e9): `non-inertia-response`, `non-inertia-request`, `non-textual`, `streamed`, `too-large`, `unserializable`, `binary`; anything else renders as a bare "Body not captured." | MATCH: every reason emitted is one of these. `binary` is never emitted (a body that is not JSON is refused before its encoding matters) |
| F8 | Textual = content-type contains `json`, `text/`, `xml`, or `javascript` (L1675-1684) | MATCH |
| F9 | `redirectLocation`: `X-Inertia-Location` wins regardless of status; else `Location` only for 3xx; else null (L1534-1551) | MATCH |
| F10 | `serverTimingMs` = hrtime delta from request start, 0.0 if missing (L1834-1843) | MATCH (monotonic clock, rounded to 3 decimals) |

## G. Script tag

| # | Contract (quoted) | Verdict |
|---|---|---|
| G1 | `'<script data-inertia-devtools-id type="application/json">'.json_encode($id).'</script>'` inserted before the LAST `</body>`; no tag when the page has no `</body>` (L2534-2540) | MATCH for the DOM (`data-inertia-devtools-id=""` is the same attribute), + a CSP `nonce`, + `</` escaped inside the JSON. DIVERGES, deliberate: without a `</body>` the tag is appended (core spec pins it) |
| G2 | Only on: non-Inertia request, 200, payload has a component, content-type contains `text/html`; plain HTML without an Inertia page untouched (L2509-2528) | MATCH, + a response carrying an `ETag`/`Last-Modified` is left alone (Rack::ETag would ship a stale validator) |
| G3 | `data-inertia-devtools-base-path="<base url>"` on the same tag when `$request->getBaseUrl()` is non-empty (`RequestRecorder.php:206-216, 288-300`); the content script reads it (`src/content-script.ts:16-17, 136-160`) to fetch the entry beneath the prefix. Not on the docs page | MATCH (`SCRIPT_NAME`, escaped; absent at the root) |

## H. Endpoint

| # | Contract (quoted) | Verdict |
|---|---|---|
| H1 | Routes `GET _inertia/devtools/entries` and `GET _inertia/devtools/entries/{id}` (L714-718) | MATCH (`lib/inertia_rails/engine.rb`) |
| H2 | index query params: `component` (exact), `type` (comma list), `exclude` (comma list), `offset` (>=0), `limit` (>=1) applied in that order (L1263-1278) | MATCH |
| H3 | index returns a JSON array of `__meta` objects, newest first (sorted by id desc) (L802-808) | MATCH |
| H4 | show returns the full entry; non-ULID or missing -> 404 (L1283-1290) | MATCH (route constraint + repository), + a miss is re-read up to 3 times, 50 ms apart, before the 404: the extension fetches when the response headers arrive and takes a 404 as final, while the entry is written when the body closes |
| H5 | Authorize: local env always allowed; otherwise the configured gate; failure -> 403 `{message: 'Forbidden.'}` (L1216-1239) | MATCH (`Rails.env.development?`, `devtools_authorize`) |
| H6 | Entries requests marked `X-Requested-With: XMLHttpRequest` so they do not become the session's previous URL (L1320-1332) | N/A (Rails keeps no previous URL), + the read API is kept out of the log (`devtools_silence_logs`) |
| H7 | Default `except`: `['telescope*', 'horizon*', '_inertia/devtools*']` (L37) | MATCH for the devtools prefix (always skipped); `telescope*`/`horizon*` N/A |

## I. Storage and retention

| # | Contract (quoted) | Verdict |
|---|---|---|
| I1 | Path `storage_path('inertia-devtools')`, per-entry `{id}.json`, index `_meta.json`, `_last_prune`, `.gitignore` containing `*`, dir mode 0700 (L41, L749-751, L865-879) | MATCH (`tmp/inertia-devtools`), + a `_meta.lock` file because entries are published by rename |
| I2 | `ttl` 24h, `prune_interval` 300s, `limit` 100 per tab, newest kept (L43-47, L826-841) | MATCH, + `max_entries` global cap, + tab-less entries share one bucket |
| I3 | Entry write is atomic (temp + rename) (L771-773) | MATCH |
| I4 | Index mutated under an exclusive lock; missing/corrupt index rebuilt from entry files (L916-948, L980-1010) | MATCH |
| I5 | `save` rejects non-ULID ids with an exception; `get` returns null (L762-766, L780-784) | MATCH |
| I6 | Circuit breaker: a persist failure logs once and suppresses recording for 30s (L1134-1191) | MATCH (reported through `host.report_error`) |
| I7 | ULID = `Str::ulid()` 26-char Crockford base32 uppercase (L454, test L4939) | MATCH |
| I8 | Flush + `pruneIfDue` at app terminate, after the response (L692-702) | MATCH (`Rack::BodyProxy` close) |
| I9 | Recording failures never change the user's response (L2444-2450, test L4593-4605) | MATCH |

## J. Sources

| # | Contract (quoted) | Verdict |
|---|---|---|
| J1 | `renderSource` = first caller frame outside package src and `/vendor/` (L2594-2620) | MATCH (first frame under `Rails.root`, outside the gem and `vendor/bundle`) |
| J2 | Per-prop `renderSource` line found by regex `['"]key['"]\s*=>` scanning up to 100 lines from the render line (L272-275, L2735-2753) | MATCH (Ruby regex also takes `key:`) |
| J3 | `shareSource` per shared key, from the `share()` call site or the middleware `share()` method body (L2296-2343, L2627-2654) | MATCH (`inertia_share` call site or block source) |
| J4 | `route.actionSource` = file/line of the action's reflection (L2760-2784) | MATCH (`instance_method(action).source_location`) |
| J5 | `componentPath` from the view finder (L2426) | MATCH (`devtools_component_paths` roots, six extensions) |
