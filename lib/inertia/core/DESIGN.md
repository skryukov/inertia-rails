# The props walk, on a whiteboard

## The one idea

Resolution is **one recursive function over positions**. A *position* is a
dotted path plus the reload filter in force there. Everything else — presets,
dot notation, caching, rescuing — is a decision made *at* a position, not a
different kind of traversal.

    walk(value, cursor) -> a value, or DROPPED

`DROPPED` means "nothing ships here". A hash key drops; a hash whose every key
dropped goes along with its own key; an array slot keeps its place (`{}` for a
literal hash, `nil` otherwise).

## The objects

| Object | One line |
| --- | --- |
| `Reload` | The partial-reload filter: `excludes?(path)`, `names_below?(path)`, `asks_for?(path)`. `Reload::NONE` excludes nothing. |
| `Visit` | One request's protocol headers as questions: `partial?`, `reload`, `reset?`, `holds_once?`, `asked_for?`, `scroll_intent`. `from_headers` / `from_env` read them. |
| `Cursor` | Where the walk is: `path`, `depth`, `reload`, `in_array?`, `cached?`. Immutable; `at(key)` makes the child, `unfiltered` drops the filter, `cached` starts inside a cached value. |
| `Slot` | A prop key: its value and the dotted keys written underneath it. `Slot.tree(props)` expands dot notation once; two spellings of one path are refused. |
| `Container` | The one question the walk, the merger and the array placeholder ask of a Hash or an Array: may it be rebuilt (`plain?`), or does it serialize itself (`opaque?`)? |
| `Prop` | A producer (`produce(evaluator)`), what it announces (`cache`, `defer`, `merge`, `once`, `live`, `scroll`), and one rule: `decide(visit, path, eager:, excluded:)` → `:delivered`, `:held`, `:omitted` or `:silenced`. The presets lock one option each. |
| `Prop::Options` | Reads the option hash once: refuses unknown names, contradictions, reverse spellings and orphaned sub-options; hands out the parts. |
| `Prop::Announcements::{Defer,Merge,Once,Live,Scroll}` | What a prop tells the client, frozen at construction. Each also knows how to `contribute` its page key from a ledger. |
| `Prop::Cache` | A cache key and its store options. |
| `Ledger` / `Ledger::Entry` | The record of one walk: every prop met (path, prop, verdict, reset) in order, and every error a `rescue:` prop swallowed. Only the walk writes it. |
| `Metadata` | The page's second half, derived from the ledger after the walk: one contributor per key, empty lists never ship. |
| `Observer` | `walked(ledger)` once the walk is done. `Observer::NULL` is silent; DevTools is one. |
| `PropEvaluator` | The context prop blocks `instance_exec` in, plus the `Host`. |
| `PropsResolver` | The walk. `resolve` → `[props, metadata]`; `ledger` afterwards. |
| `PropsMerger` | Shared props + render props into one hash with one spelling per key; serializers stay whole. |
| `ResolutionError` | Every shape the walk refuses, spelled out as a constructor, so the walk only says where and why. |

## The walk

```
resolve
  ledger = Ledger.new
  props  = walk_slots(Slot.tree(@props), Cursor.root(visit.reload))
  [props, Metadata.derive(ledger, visit)]   then observer.walked(ledger)

# A prop key: its own value, with any dotted keys grafted on top.
walk_slot(slot, existing, cursor)
  base = slot.value? ? walk(slot.value, cursor) : existing
  return base unless slot.branches?
  refuse_ungraftable!                          # a Prop, a scalar, an opaque container
  target  = base.is_a?(Hash) ? base : {}
  grafted = slot.branches.map { |k, child| walk_slot(child, target.fetch(k, MISSING), cursor.at(k)) }
  return target.merge(grafted) if grafted.any?
  base == MISSING ? DROPPED : base

# One position. A prop is always met — only the prop knows it outranks the
# visit; anything else is produced, then walked.
walk(value, cursor)
  return walk_prop(value, cursor)     if value.is_a?(Prop)
  return walk_excluded(value, cursor) if cursor.excludes?   # never evaluated; props inside a
                                                            # literal container are still ledgered
  settled = settle(value, cursor)                           # closures & to_inertia, to a fixed point
  settled.is_a?(Prop) ? walk_prop(settled, cursor) : walk_container(settled, cursor)

walk_prop(prop, cursor)
  refuse if cursor.cached?                                  # a prop inside a cached value
  refuse if cursor.in_array? && prop.requires_key?          # a prop with no key to announce under
  verdict = prop.decide(visit, cursor.path, eager:, excluded: cursor.excludes?)
  ledger.met(cursor.path, prop, verdict, reset: visit.reset?(path))
  return DROPPED unless verdict == :delivered
  cursor = cursor.unfiltered if prop.overrides_exclusion? && cursor.excludes?   # `always` won
  prop.rescue? ? rescuing { host.serialize(deliver(prop, cursor)) } : deliver(prop, cursor)

deliver(prop, cursor)
  value = settle(prop.cache ? cached(prop.cache) { prop.produce(evaluator) } : prop.produce(evaluator))
  refuse if value.is_a?(Prop)                               # composition is options, not nesting
  walk_container(value, cursor)

walk_container(value, cursor)
  return value unless Hash or Array
  return opaque(value)        if Container.opaque?(value)   # own as_json: handed over, or refused if it holds a producer
  return walk_inside(value)   if cursor.names_below?         # the reload names a path under here
  holds_producer?(value) ? walk_inside(value, cursor.unfiltered) : value   # plain data is handed over whole

walk_hash   -> each key walked at cursor.at(key); empty-after-walk => DROPPED
walk_array  -> each element walked at cursor.at(i, in_array: true); DROPPED => placeholder
```

Only the walk writes the ledger; `Metadata.derive` reads it once the walk is
done, and the same ledger reaches the observer. The page metadata and a
DevTools recording are therefore two views of one record, and can never
disagree about what a visit was told.

## The two bounds

* **128 producers** in one `settle` loop — a chain that never settles.
* **128 levels** of `Cursor#depth` — a container that contains itself.

Both raise `ResolutionError` whose message says *produces itself*, so a cycle
never reaches `SystemStackError` and `rescue: true` never swallows it: a
`rescue:` prop re-raises every `Inertia::Core::Error`.

## The partial-reload filter

`Reload` holds `only` and `except` as dotted strings and answers one question:

```
excludes?(path) =
  except names path or an ancestor
  || (only.any? && only names neither path, nor an ancestor, nor a descendant)
```

It is asked at **every** position, before anything is produced, so what made
the container — literal, closure, serializer or prop — cannot change which
paths survive. The only escape is `always`, which — when the visit excluded
its own path — swaps the subtree's filter for `Reload::NONE` and ships its
whole value. A reload that names a path *inside* an `always` prop
(`only: ['users.0.name']`, `except: ['users.0.email']`) does not exclude the
prop's own path, so the filter stays in force and is honoured inside.

## Caching

`cached(cache)` resolves the produced value once, with `Cursor.cached`, and
stores it as JSON through `Host#cache_store` under `Host#expand_cache_key`;
what comes back is a `RawJson` the page embeds verbatim. Nothing per-request
may be inside: a prop met under a cached cursor is refused, and the host is
asked to `instrument(:cache_fetch, key:)` with `hit:` settled inside the block.
