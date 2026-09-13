# frozen_string_literal: true

RSpec.describe Inertia::Core::LiveProp do
  def resolve(props, visit = {})
    Inertia::Core::PropsResolver.new(props, evaluator: evaluator, visit: visit).resolve
  end

  let(:listener) { { channel: { name: 'chat.1', type: 'public' }, events: ['MessageCreated'] } }

  it 'announces its listeners under liveProps alongside the value' do
    props, metadata = resolve(messages: described_class.new(on: 'MessageCreated', channel: 'chat.1') { [1] })

    expect(props).to eq(messages: [1])
    expect(metadata).to eq(liveProps: { 'messages' => { listeners: [listener] } })
  end

  it 'carries a throttle, several events, and typed channels' do
    channels = [{ name: 'room', type: 'private' }, { name: 'vault', type: 'encrypted-private' }, 'lobby']
    prop = described_class.new(on: %w[Created Deleted], channel: channels, throttle: 500) { [] }
    _, metadata = resolve(messages: prop)

    expect(metadata[:liveProps]['messages']).to eq(
      listeners: [
        { channel: { name: 'room', type: 'private' }, events: %w[Created Deleted] },
        { channel: { name: 'vault', type: 'encrypted-private' }, events: %w[Created Deleted] },
        { channel: { name: 'lobby', type: 'public' }, events: %w[Created Deleted] }
      ],
      throttle: 500
    )
  end

  it 'keeps announcing its listeners on a partial reload that drops the value' do
    props = { messages: described_class.new(on: 'E', channel: 'c') { [1] }, other: 2 }
    resolved, metadata = resolve(props, partial: true, only: ['other'])

    expect(resolved).to eq(other: 2)
    expect(metadata).to eq(liveProps: { 'messages' => { listeners: [{ channel: { name: 'c', type: 'public' },
                                                                      events: ['E'], }] } })
  end

  it 'announces its listeners from inside a literal hash the partial reload excluded' do
    props = { chat: { messages: described_class.new(on: 'E', channel: 'c') { [1] }, count: -> { raise 'ran' } },
              other: 2, }
    resolved, metadata = resolve(props, partial: true, only: ['other'])

    expect(resolved).to eq(other: 2)
    expect(metadata[:liveProps].keys).to eq ['chat.messages']
  end

  it 'rides on defer, optional, once and always as a `live:` option, announced whether or not the value ships' do
    live = { on: 'E', channel: 'c' }
    props = {
      d: Inertia::Core::DeferProp.new(live: live) { 1 },
      o: Inertia::Core::OptionalProp.new(live: live) { 2 },
      n: Inertia::Core::OnceProp.new(live: live) { 3 },
      a: Inertia::Core::AlwaysProp.new(live: live) { 4 },
    }

    resolved, first = resolve(props)
    expect(resolved.keys).to eq %i[n a]
    expect(first[:liveProps].keys).to eq %w[d o n a]

    resolved, partial = resolve(props, partial: true, only: %w[d o])
    expect(resolved.keys).to eq %i[d o a]
    expect(partial[:liveProps].keys).to eq %w[d o n a]
  end

  it 'announces the listeners of a once prop the client already holds' do
    props = { n: Inertia::Core::OnceProp.new(live: { on: 'E', channel: 'c' }) { 3 } }
    resolved, metadata = resolve(props, partial: true, except_once: ['n'])

    expect(resolved).to eq({})
    expect(metadata[:liveProps].keys).to eq ['n']
  end

  it 'points the reverse delivery spellings at the composing preset' do
    expect { described_class.new(on: 'E', channel: 'c', defer: true) { [] } }
      .to raise_error(ArgumentError, /spell it `defer\(live: \{ on:, channel: \}\)`/)
    expect { described_class.new(on: 'E', channel: 'c', optional: true) { [] } }
      .to raise_error(ArgumentError, /spell it `optional\(live: \{ on:, channel: \}\)`/)
  end

  it 'refuses merge, since a live refresh replaces the prop' do
    expect { Inertia::Core::MergeProp.new(live: { on: 'E', channel: 'c' }) { [] } }
      .to raise_error(ArgumentError, /Cannot combine `merge` with `live`/)
    expect { described_class.new(on: 'E', channel: 'c', merge: true) { [] } }
      .to raise_error(ArgumentError, /Cannot combine `merge` with `live`/)
  end

  it 'refuses malformed listeners' do
    expect { described_class.new(channel: 'c') { [] } }.to raise_error(ArgumentError, /`live:` takes/)
    expect { described_class.new(on: 'E') { [] } }.to raise_error(ArgumentError, /`channel:` entries/)
    expect { described_class.new(on: [], channel: 'c') { [] } }
      .to raise_error(ArgumentError, /at least one event/)
    expect { described_class.new(on: 'E', channel: { name: 'c', type: 'secret' }) { [] } }
      .to raise_error(ArgumentError, /channel type/)
    expect { described_class.new(on: 'E', channel: 'c', throttle: 'fast') { [] } }
      .to raise_error(ArgumentError, /throttle/)
  end

  it 'refuses listeners that name different throttles' do
    listeners = [{ on: 'A', channel: 'a', throttle: 100 }, { on: 'B', channel: 'b', throttle: 250 }]
    expect { Inertia::Core::DeferProp.new(live: listeners) { [] } }
      .to raise_error(ArgumentError, /different throttles \(100, 250\)/)
  end

  it 'lets a listener without a throttle agree with the one that names it' do
    listeners = [{ on: 'A', channel: 'a', throttle: 100 }, { on: 'B', channel: 'b' }]
    _, metadata = resolve(stats: Inertia::Core::DeferProp.new(live: listeners) { [] })

    expect(metadata[:liveProps]['stats'][:throttle]).to eq 100
  end

  describe Inertia::Core::Broadcast do
    it 'resolves props eagerly into the __inertia envelope, dropping rescued ones' do
      payload = described_class.props({
                                        count: -> { 3 },
                                        deferred: Inertia::Core::DeferProp.new { 'now' },
                                        optional: Inertia::Core::OptionalProp.new { 'now' },
                                        'dotted.key' => 1,
                                        broken: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' },
                                      }, evaluator: evaluator)

      expect(payload).to eq('__inertia' => { 'props' => { 'count' => 3, 'deferred' => 'now', 'optional' => 'now',
                                                          'dotted.key' => 1, } })
    end

    it 'runs blocks in the given context' do
      context = Class.new { def name = 'ctx' }.new
      payload = described_class.props({ who: -> { name } }, evaluator: evaluator(context))

      expect(payload.dig('__inertia', 'props', 'who')).to eq 'ctx'
    end
  end
end
