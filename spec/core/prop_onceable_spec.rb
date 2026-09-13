# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::Prop, 'once options' do
  describe 'via DeferProp' do
    let(:prop_class) { Inertia::Core::DeferProp }

    describe 'once announcement' do
      it 'is absent by default' do
        prop = prop_class.new { 'value' }
        expect(announced(prop)).not_to have_key(:onceProps)
      end

      it 'is present with once: true' do
        prop = prop_class.new(once: true) { 'value' }
        expect(announced(prop)).to include(onceProps: { 'key' => { prop: 'key' } })
      end

      context 'once is independent of fresh' do
        it 'is announced when once is true regardless of fresh' do
          prop = prop_class.new(once: true, fresh: true) { 'value' }
          expect(announced(prop)).to have_key(:onceProps)
        end

        it 'refuses fresh when once is disabled' do
          expect { prop_class.new(once: false, fresh: true) { 'value' } }
            .to raise_error(ArgumentError, /`fresh:` belongs to/)
        end
      end
    end

    describe 'redelivery to a visit already holding the prop' do
      let(:holding_visit) { { partial: true, except_once: ['key'] } }

      it 'is withheld by default' do
        prop = prop_class.new(once: true) { 'value' }
        expect(delivered?(prop, visit: holding_visit)).to be false
      end

      it 'is delivered when fresh' do
        prop = prop_class.new(once: true, fresh: true) { 'value' }
        expect(delivered?(prop, visit: holding_visit)).to be true
      end
    end

    describe 'custom once key' do
      it 'is announced under its own path without a key' do
        prop = prop_class.new(once: true) { 'value' }
        expect(announced(prop)[:onceProps]).to have_key('key')
      end

      it 'can be set via constructor' do
        prop = prop_class.new(once: true, key: 'custom') { 'value' }
        expect(announced(prop)[:onceProps]).to have_key('custom')
      end
    end

    describe 'expiry' do
      let(:freeze_time) { Time.now }

      before do
        allow(Time).to receive(:now).and_return(freeze_time)
      end

      it 'is absent without expires_in' do
        prop = prop_class.new(once: true) { 'value' }
        expect(announced(prop)[:onceProps]['key']).not_to have_key(:expiresAt)
      end

      it 'is announced in milliseconds with expires_in' do
        prop = prop_class.new(once: true, expires_in: 3600) { 'value' }
        expected = ((freeze_time.to_f + 3600) * 1000).to_i
        expect(announced(prop)[:onceProps]['key']).to include(expiresAt: expected)
      end
    end

    it 'preserves existing DeferProp functionality' do
      prop = prop_class.new(group: 'custom', once: true) { 'value' }
      metadata = announced(prop)

      expect(metadata).to include(deferredProps: { 'custom' => ['key'] })
      expect(metadata).to have_key(:onceProps)
    end
  end

  describe 'via OptionalProp' do
    let(:prop_class) { Inertia::Core::OptionalProp }

    it 'supports once functionality' do
      freeze_time = Time.now
      allow(Time).to receive(:now).and_return(freeze_time)

      prop = prop_class.new(once: true, key: 'opt_key', expires_in: 1800) { 'value' }
      expected = ((freeze_time.to_f + 1800) * 1000).to_i

      expect(announced(prop)).to eq(onceProps: { 'opt_key' => { prop: 'key', expiresAt: expected } })
    end

    it 'defaults to not once' do
      prop = prop_class.new { 'value' }
      expect(announced(prop)).not_to have_key(:onceProps)
    end
  end

  describe 'via MergeProp' do
    let(:prop_class) { Inertia::Core::MergeProp }

    it 'supports once functionality' do
      freeze_time = Time.now
      allow(Time).to receive(:now).and_return(freeze_time)

      prop = prop_class.new(once: true, key: 'merge_key', expires_in: 7200) { 'value' }
      expected = ((freeze_time.to_f + 7200) * 1000).to_i

      expect(announced(prop)[:onceProps]).to eq('merge_key' => { prop: 'key', expiresAt: expected })
    end

    it 'preserves merge functionality' do
      prop = prop_class.new(once: true) { 'value' }
      metadata = announced(prop)

      expect(metadata).to include(mergeProps: ['key'])
      expect(metadata).to have_key(:onceProps)
    end
  end
end
