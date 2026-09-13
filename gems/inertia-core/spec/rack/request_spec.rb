# frozen_string_literal: true

RSpec.describe Inertia::Core::Rack::Request do
  def request(env)
    described_class.new({ 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/a', 'QUERY_STRING' => '',
                          'rack.url_scheme' => 'http', 'SERVER_NAME' => 'app.test', 'SERVER_PORT' => '3000',
                          'HTTP_HOST' => 'app.test', }.merge(env))
  end

  it 'reads the protocol headers off the env' do
    plain = request({})
    inertia = request('HTTP_X_INERTIA' => 'true', 'HTTP_X_INERTIA_VERSION' => 'v1', 'REQUEST_METHOD' => 'POST')

    expect([plain.inertia?, plain.get?, plain.version]).to eq [false, true, nil]
    expect([inertia.inertia?, inertia.get?, inertia.version, inertia.request_method]).to eq [true, false, 'v1', 'POST']
  end

  it 'takes the origin the client reached, not the socket the app listens on' do
    plain = request({})
    expect([plain.scheme, plain.host, plain.port]).to eq ['http', 'app.test', 80]

    proxied = request('HTTP_X_FORWARDED_PROTO' => 'https', 'HTTP_X_FORWARDED_HOST' => 'internal.test, public.test')
    expect([proxied.scheme, proxied.host, proxied.port]).to eq ['https', 'public.test', 443]
  end

  describe 'the scheme' do
    it 'reads a chained X-Forwarded-Proto from the front, where the client-facing proxy wrote' do
      expect(request('HTTP_X_FORWARDED_PROTO' => 'https, http').scheme).to eq 'https'
      expect(request('HTTP_X_FORWARDED_PROTO' => 'http, https').scheme).to eq 'http'
      expect(request('HTTP_X_FORWARDED_SCHEME' => 'https').scheme).to eq 'https'
    end

    it 'honours Forwarded: proto= (RFC 7239), quoted or chained' do
      expect(request('HTTP_FORWARDED' => 'for=1.2.3.4;proto=https;host=app.test').scheme).to eq 'https'
      expect(request('HTTP_FORWARDED' => 'for=1.2.3.4;Proto="https"').scheme).to eq 'https'
      expect(request('HTTP_FORWARDED' => 'proto=https, for=10.0.0.1;proto=http').scheme).to eq 'https'
      expect(request('HTTP_FORWARDED' => 'for=1.2.3.4').scheme).to eq 'http'
    end

    it 'honours X-Forwarded-Ssl: on' do
      expect(request('HTTP_X_FORWARDED_SSL' => 'on').scheme).to eq 'https'
      expect(request('HTTP_X_FORWARDED_SSL' => 'off').scheme).to eq 'http'
    end

    it 'honours HTTPS=on in the env' do
      expect(request('HTTPS' => 'on').scheme).to eq 'https'
      expect(request('HTTPS' => 'off').scheme).to eq 'http'
    end

    it 'falls back to the connection, then to http' do
      expect(request('rack.url_scheme' => 'https').scheme).to eq 'https'
      expect(described_class.new({}).scheme).to eq 'http'
    end
  end

  it 'reads a port from the authority, then from the proxy' do
    expect(request('HTTP_HOST' => 'app.test:8080').port).to eq 8080
    expect(request('HTTP_X_FORWARDED_PORT' => '8443').port).to eq 8443
  end

  it 'splits an IPv6 authority at the colon outside the brackets' do
    ipv6 = request('HTTP_HOST' => '[::1]:3000')
    expect([ipv6.host, ipv6.port]).to eq ['::1', 3000]
    expect(ipv6.url).to eq 'http://[::1]:3000/a'
    expect(request('HTTP_HOST' => '[::1]').host).to eq '::1'
  end

  it 'falls back to the server name and port when no host header arrives' do
    bare = described_class.new('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/a',
                               'SERVER_NAME' => 'app.test', 'SERVER_PORT' => '3000')
    expect(bare.url).to eq 'http://app.test:3000/a'
  end

  it 'builds the URL with the mount point and the query string' do
    mounted = request('SCRIPT_NAME' => '/admin', 'QUERY_STRING' => 'page=2', 'HTTP_X_FORWARDED_PROTO' => 'https')
    expect(mounted.fullpath).to eq '/admin/a?page=2'
    expect(mounted.url).to eq 'https://app.test/admin/a?page=2'
  end
end
