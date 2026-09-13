# frozen_string_literal: true

RSpec.describe Inertia::Core::OnceProp do
  it_behaves_like 'a prop'

  let(:freeze_time) { Time.now }

  before do
    allow(Time).to receive(:now).and_return(freeze_time)
  end

  describe 'once announcement' do
    it 'announces the prop under its own path by default' do
      prop = described_class.new { 'value' }

      expect(announced(prop)).to eq(onceProps: { 'key' => { prop: 'key' } })
    end

    it 'announces under a custom key' do
      prop = described_class.new(key: 'custom_key') { 'value' }

      expect(announced(prop)).to eq(onceProps: { 'custom_key' => { prop: 'key' } })
    end

    it 'keeps the key it was built with when the caller mutates its string' do
      key = +'custom_key'
      prop = described_class.new(key: key) { 'value' }
      key << 'x'

      expect(announced(prop)[:onceProps]).to have_key('custom_key')
    end

    it 'is announced regardless of fresh' do
      expect(announced(described_class.new { 'value' })).to have_key(:onceProps)
      expect(announced(described_class.new(fresh: true) { 'value' })).to have_key(:onceProps)
    end
  end

  describe 'expiry' do
    it 'has no expiry without expires_in' do
      prop = described_class.new { 'value' }

      expect(announced(prop)[:onceProps]['key']).not_to have_key(:expiresAt)
    end

    it 'announces the expiration timestamp in milliseconds with Numeric (seconds)' do
      prop = described_class.new(expires_in: 3600) { 'value' }
      expected = ((freeze_time.to_f + 3600) * 1000).to_i

      expect(announced(prop)[:onceProps]['key']).to include(expiresAt: expected)
    end

    it 'refuses an expires_in that is not a number of seconds' do
      ['5 minutes', :soon, [1, 2]].each do |bad|
        expect { described_class.new(expires_in: bad) { 'value' } }
          .to raise_error(ArgumentError, /`expires_in:` is a number of seconds/)
      end
    end
  end

  describe 'delivery to a visit already holding the prop' do
    let(:holding_visit) { { except_once: ['key'] } }

    it 'is withheld by default' do
      prop = described_class.new { 'value' }

      expect(delivered?(prop, visit: holding_visit)).to be false
    end

    it 'is delivered again when fresh' do
      prop = described_class.new(fresh: true) { 'value' }

      expect(delivered?(prop, visit: holding_visit)).to be true
    end
  end
end
