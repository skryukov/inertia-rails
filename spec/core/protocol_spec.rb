# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::Protocol do
  describe '.request?' do
    it 'reads the X-Inertia header off anything answering []' do
      expect(described_class.request?({ 'X-Inertia' => 'true' })).to be true
      expect(described_class.request?({})).to be false
    end
  end

  describe '.vary' do
    it 'adds X-Inertia once, keeping what was there' do
      expect(described_class.vary(nil)).to eq 'X-Inertia'
      expect(described_class.vary('Accept')).to eq 'Accept, X-Inertia'
      expect(described_class.vary('x-inertia, Accept')).to eq 'x-inertia, Accept'
    end
  end

  describe '.script_json' do
    it 'keeps a </script> inside a string from ending the element' do
      expect(described_class.script_json('{"a":"</script><b>"}')).to eq '{"a":"<\/script><b>"}'
    end
  end

  describe '.location_response' do
    it 'is a bodiless 409 pointing at the URL, with the version when known' do
      expect(described_class.location_response('http://x/a?b=1', version: 3))
        .to eq [409, { 'X-Inertia-Location' => 'http://x/a?b=1', 'X-Inertia-Version' => '3' }, []]
      expect(described_class.location_response('http://x/a')[1]).to eq('X-Inertia-Location' => 'http://x/a')
    end
  end

  describe Inertia::Core::Protocol::Version do
    it 'compares numerically when the server version is numeric' do
      expect(described_class.stale?('1.0', 1)).to be false
      expect(described_class.stale?('2', 1)).to be true
    end

    it 'compares as strings otherwise, and treats a missing header as stale' do
      expect(described_class.stale?('abc', 'abc')).to be false
      expect(described_class.stale?(nil, 'abc')).to be true
      expect(described_class.stale?(nil, nil)).to be false
    end
  end

  describe Inertia::Core::Protocol::Redirect do
    it 'rewrites 301/302 after PUT, PATCH and DELETE to 303, nothing else' do
      expect(described_class.status_for('PUT', 302)).to eq 303
      expect(described_class.status_for('DELETE', 301)).to eq 303
      expect(described_class.status_for('POST', 302)).to eq 302
      expect(described_class.status_for('PATCH', 307)).to eq 307
    end

    it 'tells a redirect status from any other' do
      expect(described_class.redirect?(303)).to be true
      expect(described_class.redirect?(308)).to be true
      expect(described_class.redirect?(200)).to be false
    end

    it 'tells an external location from the origin it came in on' do
      origin = { scheme: 'https', host: 'app.test', port: 443 }
      expect(described_class.external?('https://app.test/x', **origin)).to be false
      expect(described_class.external?('/relative', **origin)).to be false
      expect(described_class.external?('https://APP.test:443/x', **origin)).to be false
      expect(described_class.external?('http://app.test/x', **origin)).to be true
      expect(described_class.external?('https://other.test/x', **origin)).to be true
      expect(described_class.external?('https://app.test:8443/x', **origin)).to be true
      expect(described_class.external?('http://[bad', **origin)).to be false
    end

    it 'compares an IPv6 host without its brackets' do
      origin = { scheme: 'http', host: '::1', port: 3000 }
      expect(described_class.external?('http://[::1]:3000/x', **origin)).to be false
      expect(described_class.external?('http://[::2]:3000/x', **origin)).to be true
    end
  end
end
