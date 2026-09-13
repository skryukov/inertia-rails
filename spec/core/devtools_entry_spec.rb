# frozen_string_literal: true

require_relative 'spec_helper'
require 'stringio'

RSpec.describe Inertia::Core::Devtools::EntryBuilder do
  def env(overrides = {})
    {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/users',
      'HTTP_HOST' => 'example.com',
      'rack.url_scheme' => 'http',
    }.merge(overrides)
  end

  def build(env, status: 200, headers: {}, body: nil, collector: nil, prefetch: false, error: nil)
    exchange = Inertia::Core::Devtools::Exchange.new(env, status: status, headers: headers, body: body)

    described_class.new(exchange, id: Inertia::Core::Devtools::Ulid.generate, elapsed_ms: 1.5, prefetch: prefetch,
                                  collector: collector, redactor: redactor, error: error).build
  end

  let(:redactor) do
    Inertia::Core::Devtools::Redactor.new(
      filter: Inertia::Core::Devtools::KeyFilter.new(%w[password token]),
      header_keys: %w[authorization cookie]
    )
  end

  # A finished collector, without a resolution to run: what the entry merges
  # into its page half.
  let(:collector) do
    instance_double(
      Inertia::Core::Devtools::Collector,
      component: 'Users/Index',
      build: {
        props: { 'name' => { inertiaType: nil } },
        propValues: { 'name' => 'Brandon' },
        renderSource: { file: 'app/controllers/users_controller.rb', line: 4 },
        componentPath: 'app/frontend/pages/Users/Index.tsx',
        responseBody: { 'component' => 'Users/Index', 'props' => { 'name' => 'Brandon' } },
      }
    )
  end

  it 'shapes the entry the extension reads' do
    entry = build(env('HTTP_X_INERTIA_DEVTOOLS_TAB' => 'tab-1', 'HTTP_X_INERTIA_DEVTOOLS_VISIT' => 'v-1'),
                  collector: collector)

    expect(entry[:__meta]).to include(
      tabUuid: 'tab-1', visitId: 'v-1', batchId: nil, method: 'GET',
      url: 'http://example.com/users', component: 'Users/Index', requestType: 'initial',
      status: 200, redirectLocation: nil, serverTimingMs: 1.5
    )
    expect(entry[:__meta][:timestamp]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
    expect(Inertia::Core::Devtools::Ulid.valid?(entry[:__meta][:id])).to be true
    expect(entry).to include(
      props: { 'name' => { inertiaType: nil } },
      propValues: { 'name' => 'Brandon' },
      route: { name: nil, uri: '', action: nil },
      componentPath: 'app/frontend/pages/Users/Index.tsx'
    )
    expect(entry[:http][:responseBody]).to eq(
      status: 'present', value: { 'component' => 'Users/Index', 'props' => { 'name' => 'Brandon' } }
    )
  end

  it 'names the request type the client asked for' do
    types = {
      {} => 'http',
      { 'HTTP_PRECOGNITION' => 'true' } => 'precognition',
      { 'HTTP_X_INERTIA' => 'true' } => 'navigate',
      { 'HTTP_X_INERTIA' => 'true', 'HTTP_X_INERTIA_PARTIAL_COMPONENT' => 'Users/Index' } => 'partial',
      { 'HTTP_X_INERTIA' => 'true', 'HTTP_X_INERTIA_DEVTOOLS_DEFERRED' => '1' } => 'deferred',
      { 'HTTP_X_INERTIA' => 'true', 'HTTP_X_INERTIA_DEVTOOLS_POLL' => '1' } => 'poll',
    }

    types.each do |headers, type|
      expect(build(env(headers))[:__meta][:requestType]).to eq type
    end

    expect(build(env, collector: collector)[:__meta][:requestType]).to eq 'initial'
    expect(build(env('HTTP_X_INERTIA' => 'true'), prefetch: true)[:__meta][:requestType]).to eq 'prefetch'
    expect(build(env('HTTP_PRECOGNITION' => ''))[:__meta][:requestType]).to eq 'http'
    expect(Inertia::Core::Devtools::RequestType.prefetch?('HTTP_PURPOSE' => 'Prefetch')).to be true
  end

  it 'records where a redirect points, with the query redacted' do
    location = build(env, status: 302, headers: { 'Location' => 'http://example.com/x?token=leaked' })
    expect(location[:__meta][:redirectLocation]).to eq 'http://example.com/x?token=leaked'
    expect(location[:http][:responseHeaders]['location']).to eq 'http://example.com/x?token=%5BREDACTED%5D'

    full_visit = build(env, status: 409, headers: { 'x-inertia-location' => 'http://example.com/x' })
    expect(full_visit[:__meta][:redirectLocation]).to eq 'http://example.com/x'
    expect(build(env)[:__meta][:redirectLocation]).to be_nil
  end

  it 'redacts the headers it was told to and leaves the rest' do
    entry = build(env('HTTP_AUTHORIZATION' => 'Bearer x', 'HTTP_COOKIE' => 'a=b', 'HTTP_ACCEPT' => 'text/html',
                      'CONTENT_TYPE' => 'application/json'))

    expect(entry[:http][:requestHeaders]).to include(
      'authorization' => '[REDACTED]', 'cookie' => '[REDACTED]',
      'accept' => 'text/html', 'content-type' => 'application/json'
    )
  end

  it 'redacts a JSON request body by key, and omits what it cannot' do
    post = lambda do |content|
      build(env('REQUEST_METHOD' => 'POST', 'HTTP_X_INERTIA' => 'true',
                'rack.input' => StringIO.new(content)))[:http][:requestBody]
    end

    expect(post.call('{"password":"hunter2","name":"Brandon"}')).to eq(
      status: 'present', value: { 'password' => '[REDACTED]', 'name' => 'Brandon' }
    )
    expect(post.call('password=hunter2')).to eq(status: 'omitted', reason: 'unserializable')
    expect(post.call('"a string"')).to eq(status: 'omitted', reason: 'unserializable')
    expect(post.call('')).to eq(status: 'empty')
    expect(post.call("{\"a\":\"#{'x' * described_class::RAW_BODY_LIMIT}\"}"))
      .to eq(status: 'omitted', reason: 'too-large')
  end

  it 'keeps a write nobody can attribute to Inertia out of the entry' do
    entry = build(env('REQUEST_METHOD' => 'POST', 'rack.input' => StringIO.new('{"password":"x"}')))

    expect(entry[:http][:requestBody]).to eq(status: 'omitted', reason: 'non-inertia-request')
  end

  it 'records a response body only when it can be redacted by key, and omits the rest in the words the extension has' do
    response = lambda do |content_type, body|
      build(env, headers: { 'content-type' => content_type }, body: body)[:http][:responseBody]
    end

    expect(response.call('application/json', ['{"token":"leaked"}'])).to eq(
      status: 'present', value: { 'token' => '[REDACTED]' }
    )
    expect(response.call('text/html', ['<html></html>'])).to eq(status: 'omitted', reason: 'non-inertia-response')
    expect(response.call('application/json', ['"a string"'])).to eq(status: 'omitted', reason: 'unserializable')
    expect(response.call('application/json', ['{oops'])).to eq(status: 'omitted', reason: 'unserializable')
    expect(response.call('image/png', ['binary'])).to eq(status: 'omitted', reason: 'non-textual')
    expect(response.call('application/json', nil)).to eq(status: 'omitted', reason: 'streamed')
    expect(response.call('application/json', [''])).to eq(status: 'empty')
  end

  it 'says an exception rather than the response the framework rendered for it' do
    entry = build(env, status: 500, error: RuntimeError.new('boom'))

    expect(entry[:__meta][:error]).to eq(class: 'RuntimeError', message: 'boom')
    expect(entry[:http][:responseBody]).to eq(status: 'omitted', reason: 'non-inertia-response')
  end
end

RSpec.describe Inertia::Core::Devtools::Redactor do
  let(:redactor) { described_class.new(filter: Inertia::Core::Devtools::KeyFilter.new(%w[password token])) }

  it 'masks a matching key wherever it sits, and nothing that merely looks like one' do
    expect(redactor.redact({ 'password' => 'x', 'user' => { 'token' => 'y', 'name' => 'z' } }))
      .to eq('password' => '[REDACTED]', 'user' => { 'token' => '[REDACTED]', 'name' => 'z' })
    expect(redactor.redact([{ password: 'x' }])).to eq([{ password: '[REDACTED]' }])
    expect(redactor.redact({ 'password_hint' => 'x' })).to eq('password_hint' => 'x')
    expect(redactor.redact('password')).to eq 'password'
  end

  it 'redacts a sensitive query parameter, nested keys included' do
    expect(redactor.redact_url('http://x/?token=leaked&page=2')).to eq 'http://x/?token=%5BREDACTED%5D&page=2'
    expect(redactor.redact_url('http://x/?user[token]=leaked')).to eq 'http://x/?user%5Btoken%5D=%5BREDACTED%5D'
    expect(redactor.redact_url('http://x/users')).to eq 'http://x/users'
  end

  it 'drops a query it cannot parse instead of passing it through' do
    expect(redactor.redact_url('http://x/?token=%zz')).to eq 'http://x/?[REDACTED]'
  end

  it 'redacts the URLs a payload carries under its own keys' do
    payload = { __meta: { url: 'http://x/?token=leaked', redirectLocation: 'http://x/y?token=leaked' } }

    expect(redactor.redact_payload(payload)[:__meta]).to eq(
      url: 'http://x/?token=%5BREDACTED%5D', redirectLocation: 'http://x/y?token=%5BREDACTED%5D'
    )
  end

  it 'replaces a value no JSON generator would take, leaf by leaf' do
    sanitized = described_class.sanitize([Float::NAN, Float::INFINITY, (+"caf\xE9").force_encoding('UTF-8'), 'ok'])

    expect(sanitized).to eq((['[UNSERIALIZABLE]'] * 3) + ['ok'])
    expect { JSON.generate(sanitized) }.not_to raise_error
  end
end

RSpec.describe Inertia::Core::Devtools::ScriptTag do
  it 'inserts the id before the closing body tag, leaving the html it was given alone' do
    html = +'<html><body>hi</BODY ></html>'

    expect(described_class.insert(html, id: 'ULID'))
      .to eq '<html><body>hi<script data-inertia-devtools-id="" type="application/json">"ULID"</script></BODY ></html>'
    expect(html).to eq '<html><body>hi</BODY ></html>'
  end

  it 'appends to a page with no body tag' do
    expect(described_class.insert('<p>hi</p>', id: 'ULID')).to end_with('</script>')
  end

  it 'carries the prefix the app is mounted under, escaped, and none at the root' do
    expect(described_class.build('ULID', base_path: '/sub"')).to eq(
      '<script data-inertia-devtools-id="" type="application/json" ' \
      'data-inertia-devtools-base-path="/sub&quot;">"ULID"</script>'
    )
    expect(described_class.build('ULID', base_path: '')).to eq described_class.build('ULID')
  end

  it 'carries a nonce, and lets neither it nor the id break out of the element' do
    tag = described_class.insert('', id: '</script><script>alert(1)</script>', nonce: 'n"><script>')

    expect(tag).to eq '<script data-inertia-devtools-id="" type="application/json" ' \
                      'nonce="n&quot;&gt;&lt;script&gt;">' \
                      '"<\\/script><script>alert(1)<\\/script>"</script>'
  end
end
