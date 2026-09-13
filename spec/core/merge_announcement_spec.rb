# frozen_string_literal: true

require_relative 'spec_helper'

# The merge options a prop is built with, observed through what it announces
# on the wire (mergeProps/prependProps/deepMergeProps/matchPropsOn).
RSpec.describe Inertia::Core::Prop::Announcements::Merge do
  describe 'construction' do
    it 'raises ArgumentError when both deep_merge and merge are true' do
      expect do
        Inertia::Core::MergeProp.new(deep_merge: true, merge: true) { 1 }
      end.to raise_error(ArgumentError, /Cannot combine `merge` with `deep_merge`/)
    end

    it 'is absent from a prop that does not merge' do
      expect(announced(Inertia::Core::OptionalProp.new { 1 })).to eq({})
    end

    it 'announces a deep merge' do
      expect(announced(Inertia::Core::MergeProp.new(deep_merge: true) { 1 })).to eq(deepMergeProps: ['key'])
    end
  end

  describe 'match_on' do
    it 'announces a string match_on under the prop path' do
      expect(announced(Inertia::Core::MergeProp.new(match_on: 'id') { 1 })).to include(matchPropsOn: ['key.id'])
    end

    it 'announces every entry of an array match_on' do
      expect(announced(Inertia::Core::MergeProp.new(match_on: %w[id slug]) { 1 }))
        .to include(matchPropsOn: ['key.id', 'key.slug'])
    end

    it 'announces nothing without match_on' do
      expect(announced(Inertia::Core::MergeProp.new { 1 })).not_to have_key(:matchPropsOn)
    end

    it 'treats an empty match_on as absent' do
      expect(announced(Inertia::Core::MergeProp.new(match_on: []) { 1 })).not_to have_key(:matchPropsOn)
    end

    it 'keeps announcing the wire it was built with when the caller mutates its array' do
      match = ['id']
      prop = Inertia::Core::MergeProp.new(match_on: match) { [] }
      match << 'slug'

      expect(announced(prop)[:matchPropsOn]).to eq(['key.id'])
    end

    it 'keeps announcing the wire it was built with when the caller mutates its strings' do
      path = +'items'
      match = [+'id']
      prop = Inertia::Core::MergeProp.new(append: path, match_on: match) { [] }
      path << 'x'
      match.first << 'x'

      expect(announced(prop)).to include(mergeProps: ['key.items'], matchPropsOn: ['key.id'])
    end

    it "leaves a caller's match_on array untouched" do
      match = ['existing']
      announced(Inertia::Core::MergeProp.new(match_on: match, append: { items: 'id' }) { [] })

      expect(match).to eq(['existing'])
    end
  end

  describe 'append' do
    it 'merges at the root when append is true' do
      expect(announced(Inertia::Core::MergeProp.new(append: true) { 1 })).to include(mergeProps: ['key'])
    end

    it 'refuses false as a direction' do
      expect { Inertia::Core::MergeProp.new(append: false) { 1 } }
        .to raise_error(ArgumentError, /`append:` accepts true, a String path.*got false/)
    end

    it 'appends at a path given a string' do
      metadata = announced(Inertia::Core::MergeProp.new(append: 'items') { 1 })

      expect(metadata).to include(mergeProps: ['key.items'])
      expect(metadata).not_to have_key(:prependProps)
    end

    it 'reads paths and match_on fields from a hash' do
      metadata = announced(Inertia::Core::MergeProp.new(append: { items: nil, products: 'slug' }) { 1 })

      expect(metadata).to include(mergeProps: ['key.items', 'key.products'])
      expect(metadata[:matchPropsOn]).to eq(['key.products.slug'])
    end
  end

  describe 'prepend' do
    it 'prepends at the root when prepend is true' do
      expect(announced(Inertia::Core::MergeProp.new(prepend: true) { 1 })).to include(prependProps: ['key'])
    end

    it 'refuses false as a direction' do
      expect { Inertia::Core::MergeProp.new(prepend: false) { 1 } }
        .to raise_error(ArgumentError, /`prepend:` accepts true, a String path.*got false/)
    end

    it 'prepends at a path given a string' do
      metadata = announced(Inertia::Core::MergeProp.new(prepend: 'items') { 1 })

      expect(metadata).to include(prependProps: ['key.items'])
      expect(metadata).not_to have_key(:mergeProps)
    end

    it 'reads paths and match_on fields from a hash' do
      metadata = announced(Inertia::Core::MergeProp.new(prepend: { items: nil, products: 'slug' }) { 1 })

      expect(metadata).to include(prependProps: ['key.items', 'key.products'])
      expect(metadata[:matchPropsOn]).to eq(['key.products.slug'])
    end
  end

  describe 'combined directions' do
    it 'handles mixed append and prepend paths' do
      metadata = announced(
        Inertia::Core::MergeProp.new(append: %w[items categories], prepend: 'featured_products') { 1 }
      )

      expect(metadata).to include(mergeProps: ['key.categories', 'key.items'])
      expect(metadata).to include(prependProps: ['key.featured_products'])
    end

    it 'handles nested path configurations with match_on' do
      metadata = announced(
        Inertia::Core::MergeProp.new(append: { 'users.posts' => 'id', 'users.comments' => 'created_at' }) { 1 }
      )

      expect(metadata).to include(mergeProps: ['key.users.comments', 'key.users.posts'])
      expect(metadata[:matchPropsOn]).to include('key.users.posts.id', 'key.users.comments.created_at')
    end

    it 'accumulates match_on patterns from every source' do
      metadata = announced(
        Inertia::Core::MergeProp.new(match_on: ['existing'], append: { items: 'id' }, prepend: { products: 'slug' }) { 1 }
      )

      expect(metadata[:matchPropsOn]).to include('key.existing', 'key.items.id', 'key.products.slug')
    end
  end

  describe 'edge cases' do
    it 'refuses the same path appended and prepended' do
      expect { Inertia::Core::MergeProp.new(append: 'items', prepend: 'items') { 1 } }
        .to raise_error(ArgumentError, /both append and prepend at `items`/)
    end

    it 'collapses duplicate direction paths' do
      expect(announced(Inertia::Core::MergeProp.new(append: %w[items items]) { 1 }))
        .to include(mergeProps: ['key.items'])
    end

    it 'refuses unsupported direction values' do
      expect { Inertia::Core::MergeProp.new(append: 123) { 1 } }
        .to raise_error(ArgumentError, /`append:` accepts true, a String path/)
    end

    it 'refuses both boolean directions at once' do
      expect { Inertia::Core::MergeProp.new(append: true, prepend: true) { 1 } }
        .to raise_error(ArgumentError, /both `append: true` and `prepend: true`/)
    end

    it 'refuses a root boolean combined with per-path directions' do
      expect { Inertia::Core::MergeProp.new(append: true, prepend: 'items') { 1 } }
        .to raise_error(ArgumentError, /`append: true` with per-path directions/)
      expect { Inertia::Core::MergeProp.new(prepend: true, append: 'items') { 1 } }
        .to raise_error(ArgumentError, /`prepend: true` with per-path directions/)
    end

    it 'refuses empty and non-string paths' do
      expect { Inertia::Core::MergeProp.new(append: [nil]) { 1 } }
        .to raise_error(ArgumentError, /`append:` entries must be non-empty strings — got nil/)
      expect { Inertia::Core::MergeProp.new(append: '') { 1 } }
        .to raise_error(ArgumentError, /`append:` entries must be non-empty strings/)
    end

    it 'refuses non-string match_on entries' do
      pagy = { page_name: 'p', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::MergeProp.new(match_on: false) { 1 } }
        .to raise_error(ArgumentError, /`match_on:` entries must be non-empty strings — got false/)
      expect { Inertia::Core::ScrollProp.new(metadata: pagy, match_on: 123) { [1] } }
        .to raise_error(ArgumentError, /`match_on:` entries must be non-empty strings/)
    end

    it 'refuses deep merge combined with direction paths' do
      expect { Inertia::Core::MergeProp.new(deep_merge: true, append: 'items') { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `deep_merge` with `append`/)
    end

    it 'merges at the root given empty arrays' do
      metadata = announced(Inertia::Core::MergeProp.new(append: [], prepend: []) { 1 })

      expect(metadata).to include(mergeProps: ['key'])
    end

    it 'announces no match_on given empty hashes' do
      metadata = announced(Inertia::Core::MergeProp.new(append: {}, prepend: {}) { 1 })

      expect(metadata).to include(mergeProps: ['key'])
      expect(metadata).not_to have_key(:matchPropsOn)
    end

    it 'refuses numeric hash paths like every other non-string path' do
      expect { Inertia::Core::MergeProp.new(append: { 123 => 'id' }) { 1 } }
        .to raise_error(ArgumentError, /`append:` entries must be non-empty strings — got 123/)
    end

    it 'converts symbol match_on fields to strings' do
      metadata = announced(Inertia::Core::MergeProp.new(append: { items: :id }) { 1 })

      expect(metadata[:matchPropsOn]).to include('key.items.id')
    end

    it 'handles special characters in paths' do
      metadata = announced(Inertia::Core::MergeProp.new(append: { 'user-data_items' => 'item-id' }) { 1 })

      expect(metadata[:matchPropsOn]).to include('key.user-data_items.item-id')
    end
  end
end
