# frozen_string_literal: true

RSpec.describe Inertia::Core::MergeProp do
  it_behaves_like 'a prop'

  describe 'merge announcement' do
    subject(:metadata) { announced(prop) }

    let(:prop) { described_class.new { 'block' } }

    it { is_expected.to include(mergeProps: ['key']) }
    it { is_expected.not_to have_key(:deepMergeProps) }

    context 'when deep_merge is true' do
      let(:prop) { described_class.new(deep_merge: true) { 'block' } }

      it { is_expected.to include(deepMergeProps: ['key']) }
      it { is_expected.not_to have_key(:mergeProps) }
    end
  end

  describe 'append/prepend behavior' do
    it 'appends at the root by default' do
      metadata = announced(described_class.new { [] })

      expect(metadata).to include(mergeProps: ['key'])
      expect(metadata).not_to have_key(:prependProps)
      expect(metadata).not_to have_key(:matchPropsOn)
    end

    it 'can be configured to prepend at the root' do
      metadata = announced(described_class.new(prepend: true) { [] })

      expect(metadata).to include(prependProps: ['key'])
      expect(metadata).not_to have_key(:mergeProps)
      expect(metadata).not_to have_key(:matchPropsOn)
    end

    it 'supports appending with nested merge paths' do
      metadata = announced(described_class.new(append: 'data') { [] })

      expect(metadata).to include(mergeProps: ['key.data'])
      expect(metadata).not_to have_key(:prependProps)
      expect(metadata).not_to have_key(:matchPropsOn)
    end

    it 'supports appending with nested merge paths and match_on' do
      metadata = announced(described_class.new(append: { data: 'id' }) { [] })

      expect(metadata).to include(mergeProps: ['key.data'], matchPropsOn: ['key.data.id'])
      expect(metadata).not_to have_key(:prependProps)
    end

    it 'supports prepending with nested merge paths' do
      metadata = announced(described_class.new(prepend: 'data') { [] })

      expect(metadata).to include(prependProps: ['key.data'])
      expect(metadata).not_to have_key(:mergeProps)
      expect(metadata).not_to have_key(:matchPropsOn)
    end

    it 'supports prepending with nested merge paths and match_on' do
      metadata = announced(described_class.new(prepend: { data: 'id' }) { [] })

      expect(metadata).to include(prependProps: ['key.data'], matchPropsOn: ['key.data.id'])
      expect(metadata).not_to have_key(:mergeProps)
    end

    it 'supports append with nested merge paths as array' do
      metadata = announced(described_class.new(append: %w[data items]) { [] })

      expect(metadata).to include(mergeProps: %w[key.data key.items])
      expect(metadata).not_to have_key(:prependProps)
    end

    it 'supports prepend with nested merge paths as array' do
      metadata = announced(described_class.new(prepend: %w[data items]) { [] })

      expect(metadata).to include(prependProps: %w[key.data key.items])
      expect(metadata).not_to have_key(:mergeProps)
    end

    it 'supports complex mix of append and prepend with nested merge paths and match_on' do
      prop = described_class.new(
        append: {
          data: nil,
          users: 'id',
          posts: nil,
        },
        prepend: {
          categories: nil,
          companies: :id,
          comments: nil,
        },
        match_on: %w[comments.key]
      ) { [] }
      metadata = announced(prop)

      expect(metadata[:mergeProps]).to match_array(%w[key.data key.users key.posts])
      expect(metadata[:prependProps]).to match_array(%w[key.categories key.companies key.comments])
      expect(metadata[:matchPropsOn]).to match_array(%w[key.comments.key key.users.id key.companies.id])
    end
  end
end
