# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Inertia::Core::Rack::Middleware do
  let(:configuration) { Inertia::Core::Configuration.new(version: 'v1') }

  def env_for(method, path, headers = {})
    base = { 'REQUEST_METHOD' => method, 'PATH_INFO' => path, 'QUERY_STRING' => 'q=1', 'SCRIPT_NAME' => '',
             'rack.url_scheme' => 'https', 'HTTP_HOST' => 'app.test', }
    headers.each { |name, value| base["HTTP_#{name.upcase.tr('-', '_')}"] = value }
    base
  end

  def middleware(response, configuration: self.configuration)
    described_class.new(->(_env) { response.dup }, configuration: configuration)
  end

  # Rack 3, when loaded, wants lowercase response header names; the suite may
  # run with or without it, so written names are compared case-blind.
  def written(headers)
    headers.transform_keys(&:downcase)
  end

  it 'leaves non-Inertia requests alone' do
    status, = middleware([302, { 'Location' => '/x' }, []]).call(env_for('PUT', '/a'))
    expect(status).to eq 302
  end

  it 'rewrites a redirect after PUT/PATCH/DELETE to 303' do
    status, = middleware([302, { 'Location' => '/x' }, []]).call(env_for('PUT', '/a', 'X-Inertia' => 'true'))
    expect(status).to eq 303
  end

  it 'forces a full visit on a stale GET, carrying the current version and the app headers' do
    response = [200, { 'Content-Type' => 'text/html', 'Set-Cookie' => 'session=fresh' }, ['page']]
    status, headers, body = middleware(response)
                            .call(env_for('GET', '/a', 'X-Inertia' => 'true', 'X-Inertia-Version' => 'old'))

    expect([status, body]).to eq [409, []]
    expect(written(headers)).to eq('set-cookie' => 'session=fresh', 'x-inertia-location' => 'https://app.test/a?q=1',
                                   'x-inertia-version' => 'v1')
  end

  it 'passes a fresh GET through' do
    status, = middleware([200, {}, ['page']])
              .call(env_for('GET', '/a', 'X-Inertia' => 'true', 'X-Inertia-Version' => 'v1'))
    expect(status).to eq 200
  end

  it 'does not force a refresh on a stale non-GET' do
    status, = middleware([200, {}, ['page']])
              .call(env_for('POST', '/a', 'X-Inertia' => 'true', 'X-Inertia-Version' => 'old'))
    expect(status).to eq 200
  end

  it 'turns a cross-origin redirect into a location response, keeping other headers' do
    response = [302,
                { 'Location' => 'https://other.test/oauth', 'Set-Cookie' => 'a=1', 'Content-Type' => 'text/html' }, []]
    status, headers, body = middleware(response).call(env_for('POST', '/a', 'X-Inertia' => 'true'))

    expect([status, body]).to eq [409, []]
    expect(written(headers)).to eq('set-cookie' => 'a=1', 'x-inertia-location' => 'https://other.test/oauth',
                                   'x-inertia-version' => 'v1')
  end

  it 'leaves a same-origin redirect and a method-preserving one alone' do
    same = middleware([302, { 'Location' => 'https://app.test/next' }, []])
           .call(env_for('POST', '/a', 'X-Inertia' => 'true'))
    preserving = middleware([307, { 'Location' => 'https://other.test/next' }, []])
                 .call(env_for('POST', '/a', 'X-Inertia' => 'true'))

    expect(same.first).to eq 302
    expect(preserving.first).to eq 307
  end

  it 'keeps a cross-origin redirect when conversion is off' do
    configuration = Inertia::Core::Configuration.new(version: 'v1', convert_external_redirects: false)
    status, = middleware([302, { 'Location' => 'https://other.test/x' }, []], configuration: configuration)
              .call(env_for('POST', '/a', 'X-Inertia' => 'true'))
    expect(status).to eq 302
  end

  it 'prefers a location response already there over a forced refresh' do
    response = [409, { 'X-Inertia-Location' => 'https://app.test/elsewhere' }, []]
    _, headers, = middleware(response).call(env_for('GET', '/a', 'X-Inertia' => 'true', 'X-Inertia-Version' => 'old'))

    expect(headers['X-Inertia-Location']).to eq 'https://app.test/elsewhere'
  end

  it 'reads lowercase Rack 3 headers too' do
    response = [302, { 'location' => 'https://other.test/x' }, []]
    status, headers, = middleware(response).call(env_for('POST', '/a', 'X-Inertia' => 'true'))

    expect(status).to eq 409
    expect(written(headers).keys).to eq %w[x-inertia-location x-inertia-version]
  end

  it 'closes the body it drops' do
    body = Class.new do
      def each; end
      def close = @closed = true
      def closed? = @closed
    end.new
    middleware([302, { 'Location' => 'https://other.test/x' }, body]).call(env_for('POST', '/a', 'X-Inertia' => 'true'))

    expect(body.closed?).to be true
  end

  it 'copies the XSRF header to the CSRF one before the app runs' do
    seen = nil
    app = lambda { |env|
      seen = env['HTTP_X_CSRF_TOKEN']
      [200, {}, []]
    }
    described_class.new(app, configuration: configuration).call(env_for('POST', '/a', 'X-XSRF-TOKEN' => 'tok'))
    expect(seen).to eq 'tok'
  end

  it 'lets a subclass answer the configuration per request, and skips when it answers nil' do
    app = ->(_env) { [302, { 'Location' => '/x' }, []] }
    subclass = Class.new(described_class) do
      def configuration_for(request)
        request.env['PATH_INFO'] == '/managed' ? Inertia::Core::Configuration.new(version: 'v1') : nil
      end
    end

    expect(subclass.new(app).call(env_for('PUT', '/managed', 'X-Inertia' => 'true')).first).to eq 303
    expect(subclass.new(app).call(env_for('PUT', '/other', 'X-Inertia' => 'true')).first).to eq 302
  end

  it 'tells after_app whether the visit goes on, before any rewrite' do
    calls = []
    subclass = Class.new(described_class) do
      define_method(:after_app) { |request, status, stale:| calls << [request.fullpath, status, stale] }
    end
    app = ->(_env) { [302, { 'Location' => '/x' }, []] }

    subclass.new(app, configuration: configuration).call(env_for('PUT', '/a', 'X-Inertia' => 'true'))
    subclass.new(app, configuration: configuration)
            .call(env_for('GET', '/b', 'X-Inertia' => 'true', 'X-Inertia-Version' => 'old'))

    expect(calls).to eq [['/a?q=1', 302, false], ['/b?q=1', 302, true]]
  end

  describe 'behind a proxy' do
    # The app builds its redirect Location from the same forwarded headers, so
    # reading the raw connection would call every redirect external.
    it 'keeps a same-origin redirect when TLS is terminated upstream' do
      response = [302, { 'Location' => 'https://app.test/next' }, []]
      status, = middleware(response).call(env_for('POST', '/a', 'X-Inertia' => 'true',
                                                                'X-Forwarded-Proto' => 'https, http'))

      expect(status).to eq 302
    end

    it 'keeps a same-origin redirect when the proxy rewrites the host' do
      response = [302, { 'Location' => 'https://public.test/next' }, []]
      status, = middleware(response).call(env_for('POST', '/a', 'X-Inertia' => 'true',
                                                                'X-Forwarded-Proto' => 'https',
                                                                'X-Forwarded-Host' => 'internal.test, public.test'))

      expect(status).to eq 302
    end

    it 'keeps a same-origin redirect on an IPv6 authority' do
      response = [302, { 'Location' => 'http://[::1]:3000/next' }, []]
      env = env_for('POST', '/a', 'X-Inertia' => 'true').merge('HTTP_HOST' => '[::1]:3000', 'rack.url_scheme' => 'http')
      status, = middleware(response).call(env)

      expect(status).to eq 302
    end

    it 'still converts a genuinely external redirect' do
      response = [302, { 'Location' => 'https://other.test/next' }, []]
      status, = middleware(response).call(env_for('POST', '/a', 'X-Inertia' => 'true',
                                                                'X-Forwarded-Proto' => 'https'))

      expect(status).to eq 409
    end

    it 'sends a stale client back to the URL the client used' do
      _, headers, = middleware([200, {}, []]).call(env_for('GET', '/a', 'X-Inertia' => 'true',
                                                                        'X-Inertia-Version' => 'old',
                                                                        'X-Forwarded-Proto' => 'https',
                                                                        'X-Forwarded-Host' => 'public.test'))

      expect(written(headers)['x-inertia-location']).to eq 'https://public.test/a?q=1'
    end
  end
end
