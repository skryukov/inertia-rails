# frozen_string_literal: true

RSpec.describe Inertia::Core::Host do
  subject(:host) { described_class.new }

  it 'refuses to cache until the host names a store and a key scheme' do
    expect { host.cache_store }.to raise_error(NotImplementedError, /cache_store/)
    expect { host.expand_cache_key('k') }.to raise_error(NotImplementedError, /expand_cache_key/)
  end

  it 'reports a handled error to stderr with its context' do
    expect { host.report_error(RuntimeError.new('boom'), prop: 'stats') }
      .to output("[inertia-core] RuntimeError: boom (prop=stats)\n").to_stderr
  end

  it 'serializes through as_json when the value answers it, else through the json gem' do
    with_as_json = Class.new { def as_json(*) = { 'ok' => true } }.new
    expect(host.serialize(with_as_json)).to eq('ok' => true)
    expect(host.serialize(at: :sym)).to eq('at' => 'sym')
  end

  it 'yields the payload when instrumenting and runs no dev server' do
    expect(host.instrument(:ssr, url: 'u') { |payload| payload[:url] }).to eq 'u'
    expect(host.dev_server_url).to be_nil
  end
end
