# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::Prop, 'option handling' do
  describe 'locked preset options' do
    it 'refuses a false selector flag on its own preset' do
      [
        -> { Inertia::Core::OnceProp.new(once: false) { 1 } },
        -> { Inertia::Core::DeferProp.new(defer: false) { 1 } },
        -> { Inertia::Core::AlwaysProp.new(always: false) { 1 } },
        -> { Inertia::Core::OptionalProp.new(optional: false) { 1 } },
        -> { Inertia::Core::MergeProp.new(merge: false) { 1 } }
      ].each do |build|
        expect(&build).to raise_error(ArgumentError, /contradicts this prop type/)
      end
    end

    it 'accepts the selector flag as true' do
      expect(announced(Inertia::Core::OnceProp.new(once: true) { 1 })).to have_key(:onceProps)
      expect(announced(Inertia::Core::DeferProp.new(defer: true) { 1 })).to have_key(:deferredProps)
    end
  end

  describe 'contradictory combinations' do
    it 'refuses always with defer' do
      expect { Inertia::Core::AlwaysProp.new(defer: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `defer`/)
    end

    it 'refuses always with optional' do
      expect { Inertia::Core::AlwaysProp.new(optional: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `optional`/)
    end

    it 'refuses always with once' do
      expect { Inertia::Core::AlwaysProp.new(once: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `once`/)
    end

    it 'refuses always with merge options' do
      expect { Inertia::Core::AlwaysProp.new(merge: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `merge`/)
      expect { Inertia::Core::AlwaysProp.new(deep_merge: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `deep_merge`/)
      expect { Inertia::Core::AlwaysProp.new(append: 'items') { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `append`/)
    end

    it 'gives the reverse always spellings the same explanation' do
      expect { Inertia::Core::DeferProp.new(always: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `defer`/)
      expect { Inertia::Core::OptionalProp.new(always: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `optional`/)
      expect { Inertia::Core::OnceProp.new(always: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `once`/)
      expect { Inertia::Core::MergeProp.new(always: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `merge`/)
      expect { Inertia::Core::DeferProp.new(always: false) { 1 } }.not_to raise_error
    end

    # The compositions live on the delivery preset (`defer(once: true)`); the
    # reverse spellings earn a pointer there, not an unknown-option error.
    it 'points reverse delivery spellings at the composing preset' do
      expect { Inertia::Core::OnceProp.new(defer: true) { 1 } }
        .to raise_error(ArgumentError, /spell it `defer\(once: true\)`/)
      expect { Inertia::Core::MergeProp.new(defer: true) { 1 } }
        .to raise_error(ArgumentError, /spell it `defer\(merge: true\)`/)
      expect { Inertia::Core::OnceProp.new(optional: true) { 1 } }
        .to raise_error(ArgumentError, /spell it `optional\(once: true\)`/)
      expect { Inertia::Core::MergeProp.new(optional: true) { 1 } }
        .to raise_error(ArgumentError, /spell it `optional\(merge: true\)`/)
      expect { Inertia::Core::OnceProp.new(defer: false) { 1 } }.not_to raise_error
    end

    it 'explains that defer and optional both omit the first load' do
      expect { Inertia::Core::OptionalProp.new(defer: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `defer` with `optional`: both omit the first load/)
      expect { Inertia::Core::DeferProp.new(optional: true) { 1 } }
        .to raise_error(ArgumentError, /both omit the first load/)
    end

    it 'refuses always on scroll props' do
      page = { page_name: 'p', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::ScrollProp.new(metadata: page, always: true) { [1] } }
        .to raise_error(ArgumentError, /`always:` is not supported on scroll props/)
    end

    it 'refuses optional with defer on scroll props' do
      page = { page_name: 'p', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::ScrollProp.new(metadata: page, optional: true, defer: true) { [1] } }
        .to raise_error(ArgumentError, /Cannot combine `defer` with `optional`/)
    end

    it 'refuses unknown options' do
      expect { Inertia::Core::DeferProp.new(grup: 'oops') { 1 } }
        .to raise_error(ArgumentError, /Unknown prop option\(s\): grup/)
    end
  end

  describe 'cache option scope' do
    it 'accepts cache on every prop type but scroll' do
      expect { Inertia::Core::DeferProp.new(cache: 'k') { 1 } }.not_to raise_error
      expect { Inertia::Core::OptionalProp.new(cache: 'k') { 1 } }.not_to raise_error
      expect { Inertia::Core::OnceProp.new(cache: 'k') { 1 } }.not_to raise_error
      expect { Inertia::Core::MergeProp.new(cache: 'k') { 1 } }.not_to raise_error
      expect { Inertia::Core::AlwaysProp.new(cache: 'k') { 1 } }.not_to raise_error
    end

    it 'refuses cache on scroll props, naming the alternative' do
      page = { page_name: 'p', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::ScrollProp.new(metadata: page, cache: 'k') { [1] } }
        .to raise_error(ArgumentError, /not supported on scroll props.*keying on the page/m)
    end

    it 'refuses live on scroll props instead of forwarding it to the adapters' do
      page = { page_name: 'p', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::ScrollProp.new(metadata: page, live: { on: 'E', channel: 'c' }) { [1] } }
        .to raise_error(ArgumentError, /`live:` is not supported on scroll props/)
    end
  end

  describe 'rescue option scope' do
    let(:page) { { page_name: 'p', previous_page: nil, next_page: 2, current_page: 1 } }

    it 'rescues deferred props' do
      expect { Inertia::Core::DeferProp.new(rescue: true) { 1 } }.not_to raise_error
      expect { Inertia::Core::ScrollProp.new(metadata: page, defer: true, rescue: true) { [1] } }.not_to raise_error
    end

    it 'is refused everywhere else' do
      [
        -> { Inertia::Core::OnceProp.new(rescue: true) { 1 } },
        -> { Inertia::Core::MergeProp.new(rescue: true) { 1 } },
        -> { Inertia::Core::AlwaysProp.new(rescue: true) { 1 } },
        -> { Inertia::Core::OptionalProp.new(rescue: true) { 1 } },
        -> { Inertia::Core::ScrollProp.new(metadata: page, rescue: true) { [1] } }
      ].each do |build|
        expect(&build).to raise_error(ArgumentError, /`rescue:` belongs to/)
      end
    end
  end

  describe 'orphan sub-options' do
    it 'refuses merge sub-options without a merge flag' do
      expect { Inertia::Core::DeferProp.new(append: 'items') { 1 } }
        .to raise_error(ArgumentError, /`append:` belongs to/)
      expect { Inertia::Core::OptionalProp.new(match_on: 'id') { 1 } }
        .to raise_error(ArgumentError, /`match_on:` belongs to/)
    end

    it 'refuses once sub-options without once' do
      expect { Inertia::Core::DeferProp.new(fresh: true) { 1 } }
        .to raise_error(ArgumentError, /`fresh:` belongs to/)
      expect { Inertia::Core::MergeProp.new(key: 'k') { 1 } }
        .to raise_error(ArgumentError, /`key:` belongs to/)
    end
  end

  describe 'false cross-family flags' do
    # A disabled modifier is the dynamic form (`once: user.admin?`) at its
    # false branch; refusing it described a combination the user never asked for.
    it 'treats them as absent' do
      expect(evaluate(Inertia::Core::AlwaysProp.new(merge: false, once: false, defer: false) { 1 })).to eq(1)
      expect { Inertia::Core::DeferProp.new(fresh: false) { 1 } }.not_to raise_error
      expect { Inertia::Core::OptionalProp.new(match_on: false) { 1 } }.not_to raise_error
    end

    it 'still refuses the truthy combinations' do
      expect { Inertia::Core::AlwaysProp.new(merge: true) { 1 } }
        .to raise_error(ArgumentError, /Cannot combine `always` with `merge`/)
      expect { Inertia::Core::AlwaysProp.new(key: 'k') { 1 } }
        .to raise_error(ArgumentError, /`key:` belongs to/)
    end
  end

  describe 'malformed wire names' do
    it 'refuses a once key that is not a non-empty string' do
      [false, '', 0, []].each do |bad|
        expect { Inertia::Core::OnceProp.new(key: bad) { 1 } }
          .to raise_error(ArgumentError, /`key:` entries must be non-empty strings/)
      end
    end

    it 'refuses a once key the except-once header cannot round-trip' do
      ['plans,v2', '  ', "a\nb"].each do |bad|
        expect { Inertia::Core::OnceProp.new(key: bad) { 1 } }
          .to raise_error(ArgumentError, /must survive the `X-Inertia-Except-Once-Props` header/)
      end
      expect { Inertia::Core::OnceProp.new(key: 'user profile') { 1 } }.not_to raise_error
    end

    it 'refuses a defer group that is not a non-empty string' do
      [false, '', 0, []].each do |bad|
        expect { Inertia::Core::DeferProp.new(group: bad) { 1 } }
          .to raise_error(ArgumentError, /`group:` entries must be non-empty strings/)
      end
    end
  end

  describe 'value and block' do
    it 'accepts a value alone' do
      expect(evaluate(Inertia::Core::DeferProp.new(value: 1))).to eq(1)
    end

    it 'refuses both' do
      expect { Inertia::Core::DeferProp.new(value: 1) { 2 } }
        .to raise_error(ArgumentError, 'You must provide either a value or a block, not both')
    end

    it 'refuses neither' do
      expect { Inertia::Core::DeferProp.new }
        .to raise_error(ArgumentError, 'You must provide either a value or a block')
    end

    # It built fine, announced `deferredProps`, then the deferred fetch died
    # with a bare ArgumentError — the composition route `stacked!` cannot see.
    it 'refuses a prop type as the value' do
      expect { Inertia::Core::DeferProp.new(value: Inertia::Core::OptionalProp.new { 1 }) }
        .to raise_error(ArgumentError, /combine prop types as options on one prop/)
    end

    # A bare callable used to go through `instance_exec(&value)`, which needs
    # `to_proc` and raised TypeError for plain objects implementing `call`.
    it 'calls a non-proc callable value' do
      callable = Class.new { def call = 'computed' }.new

      expect(evaluate(Inertia::Core::DeferProp.new(value: callable))).to eq('computed')
    end
  end

  describe '#requires_key?' do
    it 'is false only for a plain cached prop' do
      expect(Inertia::Core::CachedProp.new('k') { 1 }.requires_key?).to be false
    end

    it 'is true for a bare prop' do
      expect(Inertia::Core::Prop.new(producer: ->(_controller, **) { 1 }).requires_key?).to be true
    end
  end

  describe 'scroll option forwarding' do
    it 'hands options it does not know to the scroll metadata adapters' do
      adapter = Class.new do
        def match?(metadata) = metadata == :custom

        def call(_metadata, **options)
          {
            page_name: options.fetch(:cursor_name, 'page'),
            previous_page: nil,
            next_page: 2,
            current_page: 1,
          }
        end
      end
      Inertia::Core::ScrollMetadata.register_adapter(adapter)

      prop = Inertia::Core::ScrollProp.new(metadata: :custom, cursor_name: 'next_cursor') { [1] }

      expect(announced(prop)[:scrollProps]['key'][:pageName]).to eq('next_cursor')
    ensure
      Inertia::Core::ScrollMetadata.adapters.shift
    end

    it 'refuses known prop options it does not support' do
      page = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }

      [
        -> { Inertia::Core::ScrollProp.new(metadata: page, merge: true) { [1] } },
        -> { Inertia::Core::ScrollProp.new(metadata: page, append: 'items') { [1] } },
        -> { Inertia::Core::ScrollProp.new(metadata: page, fresh: true) { [1] } },
        -> { Inertia::Core::ScrollProp.new(metadata: page, value: 'v') { [1] } }
      ].each do |build|
        expect(&build).to raise_error(ArgumentError, /not supported on scroll props/)
      end
    end

    # `once: false` and `always: false` are not scroll modifiers: unchecked,
    # they slipped through to the adapters as `{once: false, always: false}`.
    it 'refuses once and always by presence, whatever the value' do
      page = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::ScrollProp.new(metadata: page, once: false) { [1] } }
        .to raise_error(ArgumentError, /`once:` is not supported on scroll props/)
      expect { Inertia::Core::ScrollProp.new(metadata: page, always: false) { [1] } }
        .to raise_error(ArgumentError, /`always:` is not supported on scroll props/)
    end

    it 'refuses wrapper with deep_merge' do
      page = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::ScrollProp.new(metadata: page, deep_merge: true, wrapper: 'data') { [1] } }
        .to raise_error(ArgumentError, /Cannot combine `deep_merge` with `wrapper`/)
    end

    it 'refuses a wrapper that is not a non-empty string' do
      page = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }

      [false, '', 0, []].each do |bad|
        expect { Inertia::Core::ScrollProp.new(metadata: page, wrapper: bad) { [1] } }
          .to raise_error(ArgumentError, /`wrapper:` entries must be non-empty strings/)
      end
    end

    it 'refuses group without defer' do
      page = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::ScrollProp.new(metadata: page, group: 'sidebar') { [1] } }
        .to raise_error(ArgumentError, /`group:` belongs to/)
    end

    it 'forwards key to the adapters' do
      adapter = Class.new do
        def match?(metadata) = metadata == :keyed

        def call(_metadata, **options)
          { page_name: options.fetch(:key), previous_page: nil, next_page: 2, current_page: 1 }
        end
      end
      Inertia::Core::ScrollMetadata.register_adapter(adapter)

      prop = Inertia::Core::ScrollProp.new(metadata: :keyed, key: 'cursor') { [1] }

      expect(announced(prop)[:scrollProps]['key'][:pageName]).to eq('cursor')
    ensure
      Inertia::Core::ScrollMetadata.adapters.shift
    end

    it 'refuses once on scroll props' do
      page = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }

      expect { Inertia::Core::ScrollProp.new(metadata: page, once: true, key: 'custom') { [1] } }
        .to raise_error(ArgumentError, /`once:` is not supported on scroll props/)
    end
  end
end
