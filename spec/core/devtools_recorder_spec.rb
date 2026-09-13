# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::Devtools::Recorder do
  let(:host) { TestHost.new }
  let(:repository) { instance_double(Inertia::Core::Devtools::EntriesRepository, record: nil, prune_if_due: nil) }
  let(:html) { ['<html><body>hi</body></html>'] }

  def env(overrides = {})
    {
      'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/users', 'SCRIPT_NAME' => '', 'HTTP_HOST' => 'example.com',
      'rack.url_scheme' => 'http', 'HTTP_X_INERTIA_DEVTOOLS_TAB' => 'tab-1',
    }.merge(overrides)
  end

  def recorder(env = self.env, klass: described_class)
    klass.new(env, repository: repository, host: host, limits: { limit: 5 })
  end

  # A render happened: the request counts as a page load.
  def rendered(recorder)
    recorder.render_started(component: 'Users/Index', render_source: nil, shared_keys: [])
    recorder.page_rendered({ component: 'Users/Index', props: {} }, {})
    recorder
  end

  def content(body)
    body.each.to_a.join
  end

  # Rack 3, when loaded, wants lowercase response header names; the suite may
  # run with or without it, so written names are compared case-blind.
  def written(headers)
    headers.transform_keys(&:downcase)
  end

  it 'stamps the entry id and the outgoing parent on every response, and no base path at the root' do
    recorder = self.recorder
    _, headers, = recorder.finish(200, {}, ['x'])

    expect(written(headers)).to eq('x-inertia-devtools-id' => recorder.id,
                                   'x-inertia-devtools-parent-out' => recorder.id)
  end

  it 'tells the extension the prefix the app is mounted under' do
    recorder = rendered(recorder(env('SCRIPT_NAME' => '/sub')))
    _, headers, body = recorder.finish(200, { 'Content-Type' => 'text/html' }, html)

    expect(written(headers)['x-inertia-devtools-base-path']).to eq '/sub'
    expect(content(body)).to include(
      %(<script data-inertia-devtools-id="" type="application/json" data-inertia-devtools-base-path="/sub">)
    )
  end

  it 'inserts the discovery tag into an HTML page load and fixes the length' do
    recorder = rendered(self.recorder)
    _, headers, body = recorder.finish(200, { 'Content-Type' => 'text/html', 'Content-Length' => '28' }, html)

    expect(content(body)).to include(
      %(<script data-inertia-devtools-id="" type="application/json">"#{recorder.id}"</script></body>)
    )
    expect(headers['Content-Length']).to eq content(body).bytesize.to_s
  end

  it 'leaves the body alone for an Inertia response, a non-HTML one, or one carrying a validator' do
    inertia = rendered(recorder(env('HTTP_X_INERTIA' => 'true'))).finish(200, { 'Content-Type' => 'text/html' }, html)
    json = rendered(recorder).finish(200, { 'Content-Type' => 'application/json' }, ['{}'])
    validated = rendered(recorder).finish(200, { 'content-type' => 'text/html', 'ETag' => 'abc' }, html)

    expect(content(inertia[2])).to eq html.join
    expect(content(json[2])).to eq '{}'
    expect(content(validated[2])).to eq html.join
  end

  it 'carries the CSP nonce the host answers on the tag' do
    with_nonce = Class.new(described_class) { def nonce = 'n1' }
    _, _, body = rendered(recorder(klass: with_nonce)).finish(200, { 'Content-Type' => 'text/html' }, html)

    expect(content(body)).to include('nonce="n1"')
  end

  it 'persists the entry once the body closes, within the limits' do
    recorder = rendered(self.recorder)
    _, _, body = recorder.finish(200, { 'Content-Type' => 'text/html' }, html)

    expect(repository).not_to have_received(:record)

    body.close

    expect(repository).to have_received(:record).with(recorder.id, hash_including(:__meta), tab_uuid: 'tab-1', limit: 5)
    expect(repository).to have_received(:prune_if_due)
  end

  it 'records an exception as a synthetic 500, and reports what recording itself raised' do
    recorder = self.recorder
    recorder.record_exception(RuntimeError.new('boom'))

    expect(recorder.exception.message).to eq 'boom'
    expect(repository).to have_received(:record).with(recorder.id, hash_including(:__meta), tab_uuid: 'tab-1', limit: 5)

    allow(repository).to receive(:record).and_raise('disk full')
    rendered(self.recorder).finish(200, {}, ['x'])[2].close

    expect(host.reported.last).to match([an_instance_of(RuntimeError), { devtools: true }])
  end

  describe 'with the middlewares' do
    let(:middleware) do
      recorder_class = described_class
      repository = self.repository
      host = self.host
      Class.new(Inertia::Core::Rack::Middleware) do
        define_method(:recorder_for) do |env|
          env[recorder_class::ENV_KEY] = recorder_class.new(env, repository: repository, host: host)
        end
      end
    end

    def recorded(env)
      env[described_class::ENV_KEY]
    end

    it 'sees the response as the protocol leaves it' do
      app = ->(_env) { [302, { 'Location' => '/x' }, []] }
      env = env('REQUEST_METHOD' => 'PUT', 'HTTP_X_INERTIA' => 'true')
      status, headers, = middleware.new(app, configuration: Inertia::Core::Configuration.new).call(env)

      expect(status).to eq 303
      expect(written(headers)['x-inertia-devtools-id']).to eq recorded(env).id
    end

    it 'records the exception a request raised, and the outer frame finishes the entry' do
      app = ->(_env) { raise 'app boom' }
      env = self.env

      expect { middleware.new(app, configuration: Inertia::Core::Configuration.new).call(env) }
        .to raise_error('app boom')
      expect(recorded(env).exception.message).to eq 'app boom'

      error_page = ->(_env) { [500, {}, ['error page']] }
      _, headers, = Inertia::Core::Devtools::Middleware.new(error_page).call(env)

      expect(written(headers)['x-inertia-devtools-id']).to eq recorded(env).id
    end
  end

  describe Inertia::Core::Devtools::ClosingBody do
    it 'runs the callback once, on close, and closes on to_ary as Rack asks' do
      closed = 0
      body = described_class.new(%w[a b]) { closed += 1 }

      expect(body.each.to_a).to eq %w[a b]
      expect(body.to_ary).to eq %w[a b]
      expect(closed).to eq 1

      body.close
      expect(closed).to eq 1
    end

    it 'answers to_ary only for a body that has one, and never to_str' do
      stream = Object.new
      stream.define_singleton_method(:each) { |&block| block.call('x') }

      expect(described_class.new(%w[a]) { nil }).to respond_to(:to_ary)
      expect(described_class.new(stream) { nil }).not_to respond_to(:to_ary)
      expect(described_class.new(%w[a]) { nil }).not_to respond_to(:to_str)
    end
  end
end
