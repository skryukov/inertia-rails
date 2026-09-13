# frozen_string_literal: true

RSpec.describe Inertia::Core::SSR::Client do
  let(:host_class) do
    Class.new(Inertia::Core::Host) do
      attr_reader :reported, :events, :fetched
      attr_accessor :dev_server_url

      def initialize
        super
        @reported = []
        @events = []
        @fetched = []
        @entries = {}
      end

      def cache_store
        store = self
        Class.new do
          define_method(:fetch) { |key, **options, &block| store.fetch(key, **options, &block) }
        end.new
      end

      def fetch(key, **options)
        @fetched << [key, options]
        @entries[key] ||= yield
      end

      def report_error(error, **context)
        @reported << [error, context]
      end

      def instrument(event, payload = {})
        @events << [event, payload]
        yield(payload)
      end
    end
  end
  let(:host) { host_class.new }
  let(:page) { { component: 'Users/Index', props: { a: 1 }, url: '/users' } }
  let(:rendered) { { 'head' => ['<title>Users</title>'], 'body' => '<div>ok</div>' } }

  def client(host: self.host, cache: nil, **options)
    described_class.new(Inertia::Core::Configuration.new(**options), page: page, host: host, cache: cache)
  end

  def stub_ssr(status: 200, body: rendered)
    response = instance_double(Net::HTTPOK, body: body.to_json, code: status.to_s)
    allow(response).to receive(:is_a?) { |klass| status == 200 && [Net::HTTPSuccess, Net::HTTPOK].include?(klass) }
    http = instance_double(Net::HTTP)
    allow(http).to receive(:post).and_return(response)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    http
  end

  describe '#url' do
    it 'appends /render to a configured server, keeps a render path, and defaults to localhost' do
      expect(client(ssr_url: 'http://ssr:1000').url).to eq 'http://ssr:1000/render'
      expect(client(ssr_url: 'http://ssr:1000/render').url).to eq 'http://ssr:1000/render'
      expect(client(ssr_url: 'http://vite:5173/__inertia_ssr').url).to eq 'http://vite:5173/__inertia_ssr'
      expect(client.url).to eq 'http://localhost:13714/render'
    end

    it 'renders through the dev server the host runs when nothing is configured' do
      host.dev_server_url = 'http://localhost:5173'
      expect(client.url).to eq 'http://localhost:5173/__inertia_ssr'
      expect(client(ssr_url: 'http://ssr:1000').url).to eq 'http://ssr:1000/render'
    end
  end

  it 'posts the page JSON and answers the parsed body, instrumented through the host' do
    http = stub_ssr

    expect(client.render).to eq rendered
    expect(http).to have_received(:post)
      .with('/render', page.to_json, 'Content-Type' => 'application/json')
    expect(host.events).to eq [[:ssr, { url: 'http://localhost:13714/render', component: 'Users/Index' }]]
  end

  it 'skips the render when no configured bundle exists, unless the dev server is up' do
    stub_ssr

    expect(client(ssr_bundle: '/nope/ssr.js').render).to be_nil
    expect(client(ssr_bundle: ['/nope/ssr.js', __FILE__]).render).to eq rendered

    host.dev_server_url = 'http://localhost:5173'
    expect(client(ssr_bundle: '/nope/ssr.js').render).to eq rendered
  end

  describe 'caching' do
    before { stub_ssr }

    it 'fetches through the host store with the configured options, keyed by the page JSON' do
      expect(client(ssr_cache: { expires_in: 60 }).render).to eq rendered
      expect(client(ssr_cache: { expires_in: 60 }).render).to eq rendered

      expect(host.fetched.map(&:last)).to eq [{ expires_in: 60 }, { expires_in: 60 }]
      expect(host.fetched.map(&:first).uniq).to eq ["inertia_ssr/#{Digest::MD5.hexdigest(page.to_json)}"]
      expect(Net::HTTP).to have_received(:start).once
    end

    it 'lets a render override the configuration, and never caches a dev server render' do
      client(ssr_cache: true, cache: false).render
      expect(host.fetched).to be_empty

      client(cache: true).render
      expect(host.fetched.size).to eq 1

      host.dev_server_url = 'http://localhost:5173'
      client(ssr_cache: true).render
      expect(host.fetched.size).to eq 1
    end
  end

  describe 'failures' do
    it 'reports a server error through the host, hands it to on_ssr_error, and falls back' do
      stub_ssr(status: 500, body: { error: 'window is not defined', type: 'browser-api', hint: 'polyfill' })
      seen = []

      expect(client(on_ssr_error: ->(error, page) { seen << [error, page] }).render).to be_nil

      error, context = host.reported.first
      expect(error).to be_a(Inertia::Core::SSRError)
      expect([error.message, error.type, error.hint]).to eq ['window is not defined', 'browser-api', 'polyfill']
      expect(context).to eq(ssr: true, component: 'Users/Index')
      expect(seen).to eq [[error, page]]
    end

    it 'wraps a connection failure as an SSRError of type connection' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect(client.render).to be_nil
      error, = host.reported.first
      expect(error).to be_a(Inertia::Core::SSRError)
      expect(error.type).to eq 'connection'
    end

    it 'names the status when the error body is not JSON' do
      response = instance_double(Net::HTTPOK, body: 'not json', code: '502')
      allow(response).to receive(:is_a?).and_return(false)
      http = instance_double(Net::HTTP, post: response)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      client.render
      expect(host.reported.first.first.message).to eq 'SSR server returned 502'
    end

    it 'raises instead when ssr_raise_on_error is set' do
      stub_ssr(status: 500, body: { error: 'boom' })

      expect { client(ssr_raise_on_error: true).render }.to raise_error(Inertia::Core::SSRError, 'boom')
      expect(host.reported.size).to eq 1
    end
  end
end
