# Live props

Live props refresh themselves when a broadcast event arrives. The server names the channel and events a prop listens to; the client subscribes and reloads the prop when one fires, or writes the values straight into the page when the broadcast carries them.

@available_since rails=master description="Requires the live props client from @inertiajs/core 3.x (upstream PR #3232)"

## Declaring a live prop

```ruby
class ChatsController < ApplicationController
  def show
    chat = Chat.find(params[:id])

    render inertia: 'Chats/Show', props: {
      chat: chat,
      messages: InertiaRails.live(on: 'MessageCreated', channel: "chat.#{chat.id}") do
        chat.messages.order(:created_at).map(&:to_inertia)
      end,
    }
  end
end
```

The response announces the subscription under `liveProps`:

```json
{
  "liveProps": {
    "messages": {
      "listeners": [
        {
          "channel": { "name": "chat.1", "type": "public" },
          "events": ["MessageCreated"]
        }
      ]
    }
  }
}
```

Options:

- `on:` — one event name or an array of them.
- `channel:` — a channel name, a `{ name:, type: }` hash (`type` is `public`, `private`, `presence` or `encrypted-private`), or an array of either. The transport adds the prefix a private or presence channel needs.
- `throttle:` — the shortest interval between two refreshes, in milliseconds.

Live updates combine with the other prop types as a `live:` option, which takes
the same keys (`throttle:` included) and an array for several listeners:

```ruby
InertiaRails.defer(live: { on: 'StatsUpdated', channel: 'stats', throttle: 1000 }) { expensive_stats }
InertiaRails.optional(live: { on: 'CommentPosted', channel: "post.#{post.id}" }) { post.comments }
InertiaRails.always(live: { on: 'PresenceChanged', channel: 'lobby' }) { online_users }
```

One prop is throttled once, so listeners cannot name different throttles. A listener that names none takes the throttle another listener on the same prop names.

A `merge` prop cannot be live: a refresh replaces the prop, and merging the replacement into what the client holds would duplicate it.

The response announces a prop's listeners whenever the prop is part of the page, even when it carries no value for it, as inertia-laravel does. A `defer` or `optional` live prop is announced on the first load, so the client subscribes before the value arrives. A [partial reload](/guide/partial-reloads) that leaves a live prop out still announces it, and so does a response that holds back a `once` value the client already has. The client merges the `liveProps` of every response over the ones it holds.

## Pushing values instead of reloading

By default the client reloads a live prop with a partial request when an event fires. To skip the round trip, put the resolved values in the broadcast under the `__inertia` key:

```ruby
class Message < ApplicationRecord
  after_create_commit :broadcast_created

  private

  def broadcast_created
    ActionCable.server.broadcast(
      "chat.#{chat_id}",
      { event: 'MessageCreated' }.merge(
        InertiaRails.broadcast_props(messages: -> { chat.messages.order(:created_at).map(&:to_inertia) })
      )
    )
  end
end
```

`broadcast_props` resolves the props the way a full page load would — deferred and optional values included, rescued props dropped — and keeps every top-level key literal, so `"chat.messages"` addresses that nested prop. Blocks run with no controller, so pass a context if they need one: `broadcast_props(props, context: presenter)`.

## The client side

Enable the live transport when creating the app, and map the channel name and type onto Action Cable subscriptions: a `public` channel is a stream name, while `private`, `presence` and `encrypted-private` name the convention your channel class enforces before streaming.

The client half — the `live` option, `useProp`, and the `router.on('live')` event — ships with `@inertiajs/core`. Until it is released, follow [inertiajs/inertia#3232](https://github.com/inertiajs/inertia/pull/3232).
