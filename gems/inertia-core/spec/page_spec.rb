# frozen_string_literal: true

RSpec.describe Inertia::Core::Page do
  it 'builds the envelope, drops empty optional keys, and merges metadata and extensions' do
    page = described_class.new(
      component: 'Users/Index', props: { a: 1 }, url: '/users?x=1', version: 'v1',
      flash: {}, shared_keys: [], preserve_fragment: false,
      metadata: { deferredProps: { default: ['b'] } }, extensions: { live: { streams: {} } }
    ).to_h

    expect(page).to eq(
      component: 'Users/Index', props: { a: 1 }, url: '/users?x=1', version: 'v1',
      encryptHistory: false, clearHistory: false,
      deferredProps: { default: ['b'] }, live: { streams: {} }
    )
  end

  it 'refuses an extension key that would replace the envelope or the metadata' do
    page = lambda { |extensions|
      described_class.new(component: 'C', props: {}, url: '/', extensions: extensions,
                          metadata: { deferredProps: { 'default' => ['b'] } }).to_h
    }

    expect { page.call(props: {}) }.to raise_error(Inertia::Core::ResolutionError, /props/)
    expect { page.call(deferredProps: {}) }.to raise_error(Inertia::Core::ResolutionError, /deferredProps/)
    expect(page.call(live: { a: 1 })).to include(live: { a: 1 })
  end

  it 'carries flash, shared keys and preserveFragment when present' do
    page = described_class.new(
      component: 'C', props: {}, url: '/', encrypt_history: true, clear_history: true,
      flash: { notice: 'ok' }, shared_keys: ['auth'], preserve_fragment: true
    ).to_h

    expect(page).to include(encryptHistory: true, clearHistory: true, flash: { notice: 'ok' },
                            sharedProps: ['auth'], preserveFragment: true)
  end
end
