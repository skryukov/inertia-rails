# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::DeferProp do
  it_behaves_like 'a prop'

  it 'keeps the group it was built with when the caller mutates its string' do
    group = +'sidebar'
    prop = described_class.new(group: group) { 'block' }
    group << 'x'

    expect(announced(prop)[:deferredProps]).to eq('sidebar' => ['key'])
  end

  describe 'merge announcement' do
    subject(:metadata) { announced(prop) }

    let(:prop) { described_class.new { 'block' } }

    it { is_expected.not_to have_key(:mergeProps) }
    it { is_expected.not_to have_key(:deepMergeProps) }

    context 'when merge is set' do
      let(:prop) { described_class.new(merge: true) { 'block' } }

      it { is_expected.to include(mergeProps: ['key']) }
    end

    context 'when deep_merge is set' do
      let(:prop) { described_class.new(deep_merge: true) { 'block' } }

      it { is_expected.to include(deepMergeProps: ['key']) }
      it { is_expected.not_to have_key(:mergeProps) }
    end

    context 'when both merge and deep_merge are set' do
      let(:prop) { described_class.new(merge: true, deep_merge: true) { 'block' } }

      it 'raises an ArgumentError' do
        expect { prop }.to raise_error(ArgumentError, /Cannot combine `merge` with `deep_merge`/)
      end
    end
  end

  describe 'defer announcement group' do
    subject(:group) { announced(prop)[:deferredProps] }

    let(:prop) { described_class.new { 'block' } }

    it { is_expected.to eq('default' => ['key']) }

    context 'when group is set' do
      let(:prop) { described_class.new(group: 'custom') { 'block' } }

      it { is_expected.to eq('custom' => ['key']) }
    end
  end

  describe '#rescue?' do
    subject(:rescue?) { prop.rescue? }

    let(:prop) { described_class.new { 'block' } }

    it { is_expected.to be false }

    context 'when rescue is set' do
      let(:prop) { described_class.new(rescue: true) { 'block' } }

      it { is_expected.to be true }
    end
  end
end
