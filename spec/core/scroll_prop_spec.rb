# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::ScrollProp do
  it_behaves_like 'a prop'

  let(:page) { { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 } }

  def announced(prop, intent: nil, path: 'items', visit: { partial: true, only: [path], scroll_intent: intent })
    super(prop, path: path, visit: visit)
  end

  def announced_on_load(prop, path: 'items')
    announced(prop, path: path, visit: {})
  end

  # What the client receives in scrollProps, minus the per-request reset flag.
  def scroll_metadata(prop)
    announced(prop)[:scrollProps].fetch('items').except(:reset)
  end

  describe 'override validation' do
    # Everything is known at build time; a deferred prop skips its first-load
    # announce, so announce-time validation would 500 the automatic fetch.
    it 'refuses a misspelled override at construction' do
      expect { described_class.new(metadata: page, defer: true, curent_page: 5) { [1] } }
        .to raise_error(ArgumentError, /Unknown scroll metadata option\(s\): curent_page/)
    end

    it 'still builds a deferred prop with valid overrides' do
      prop = described_class.new(metadata: page, defer: true, current_page: 9) { [1] }

      expect(scroll_metadata(prop)[:currentPage]).to eq(9)
    end
  end

  describe 'snapshotting' do
    # Announcements keep what they were built with: mutating the pagination
    # hash or an override string afterwards must not change the wire.
    it 'ignores later mutation of the pagination hash' do
      pagination = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }
      prop = described_class.new(metadata: pagination) { [1] }

      pagination[:next_page] = 99

      expect(scroll_metadata(prop)[:nextPage]).to eq(2)
    end

    it 'ignores later mutation of an override string' do
      name = +'cursor'
      prop = described_class.new(metadata: page, page_name: name) { [1] }

      name << '-mutated'

      expect(scroll_metadata(prop)[:pageName]).to eq('cursor')
    end
  end

  describe 'scroll metadata' do
    it 'resolves custom metadata from provider hash' do
      metadata = {
        page_name: 'custom_page',
        previous_page: 1,
        next_page: 3,
        current_page: 2,
      }

      prop = described_class.new(metadata: metadata) { %w[item1 item2] }
      metadata = scroll_metadata(prop)

      expect(metadata).to eq(
        pageName: 'custom_page',
        previousPage: 1,
        nextPage: 3,
        currentPage: 2
      )
    end
  end

  # The merge direction is decided per request by the client's scroll intent,
  # so it is read off the visit when the prop announces itself.
  describe 'merge intent' do
    it 'defaults to appending when no intent is given' do
      prop = described_class.new(metadata: page, wrapper: 'data') { %w[item1 item2] }

      expect(announced(prop)).to include(mergeProps: ['items.data'])
    end

    context 'when merge intent is "append"' do
      it 'appends' do
        prop = described_class.new(metadata: page, wrapper: 'data') { %w[item1 item2] }

        expect(announced(prop, intent: 'append')).to include(mergeProps: ['items.data'])
      end
    end

    context 'when merge intent is "prepend"' do
      it 'prepends at root' do
        prop = described_class.new(metadata: page) { %w[item1 item2] }

        expect(announced(prop, intent: 'prepend')).to include(prependProps: ['items'])
      end
    end

    context 'with custom wrapper key' do
      it 'prepends to the wrapper key' do
        prop = described_class.new(metadata: page, wrapper: 'rows') { %w[item1 item2] }

        expect(announced(prop, intent: 'prepend')).to include(prependProps: ['items.rows'])
      end
    end
  end

  describe 'first load announcements' do
    it 'announces an append merge under the wrapper' do
      prop = described_class.new(metadata: page, wrapper: 'data') { %w[item1 item2] }

      expect(announced_on_load(prop)).to include(mergeProps: ['items.data'])
    end

    it 'announces a root append without a wrapper' do
      prop = described_class.new(metadata: page) { %w[item1 item2] }

      expect(announced_on_load(prop)).to include(mergeProps: ['items'])
    end
  end

  describe 'merge announcement' do
    it 'is always announced' do
      prop = described_class.new(metadata: page) { %w[item1 item2] }
      expect(announced(prop)).to have_key(:mergeProps)
    end
  end

  describe 'defer announcement' do
    it 'is absent by default' do
      prop = described_class.new(metadata: page) { %w[item1 item2] }
      expect(announced_on_load(prop)).not_to have_key(:deferredProps)
    end

    it 'is present when defer: true' do
      prop = described_class.new(defer: true) { %w[item1 item2] }
      expect(announced_on_load(prop)).to include(deferredProps: { 'default' => ['items'] })
    end
  end

  describe 'defer announcement group' do
    it 'defaults to the DeferProp default group' do
      prop = described_class.new(defer: true) { %w[item1 item2] }
      expect(announced_on_load(prop)[:deferredProps]).to eq(Inertia::Core::DeferProp::DEFAULT_GROUP => ['items'])
    end

    it 'accepts a custom group' do
      prop = described_class.new(defer: true, group: 'custom') { %w[item1 item2] }
      expect(announced_on_load(prop)[:deferredProps]).to eq('custom' => ['items'])
    end
  end

  describe 'scroll metadata with defer options' do
    it 'does not leak defer and group into metadata options' do
      metadata = {
        page_name: 'page',
        previous_page: nil,
        next_page: 2,
        current_page: 1,
      }

      prop = described_class.new(metadata: metadata, defer: true, group: 'custom') { %w[item1 item2] }
      result = scroll_metadata(prop)

      expect(result).to eq(
        pageName: 'page',
        previousPage: nil,
        nextPage: 2,
        currentPage: 1
      )
    end
  end

  describe 'edge cases' do
    let(:headers) { {} }
    let(:controller) do
      controller = double('Controller')
      request = double('Request')

      allow(controller).to receive(:request).and_return(request)
      allow(request).to receive(:headers).and_return(headers)
      controller
    end

    context 'with nil wrapper handling' do
      it 'merges at the root when wrapper is nil' do
        prop = described_class.new(metadata: page, wrapper: nil) { %w[item1 item2] }

        expect(announced(prop)).to include(mergeProps: ['items'])
      end
    end

    context 'with invalid metadata types' do
      it 'raises MissingMetadataAdapterError for unsupported metadata' do
        prop = described_class.new(metadata: 'unsupported_type') { %w[item1 item2] }

        expect do
          announced(prop)
        end.to raise_error(
          Inertia::Core::ScrollMetadata::MissingMetadataAdapterError,
          'No ScrollMetadata adapter found for "unsupported_type" ' \
          '- pass Pagy/Kaminari, a Hash, or the page fields as options.'
        )
      end

      it 'raises MissingMetadataAdapterError for custom objects' do
        custom_object = Class.new.new
        prop = described_class.new(metadata: custom_object) { %w[item1 item2] }

        expect do
          announced(prop)
        end.to raise_error(
          Inertia::Core::ScrollMetadata::MissingMetadataAdapterError
        )
      end

      it 'uses options as fallback when metadata is unsupported' do
        prop = described_class.new(
          metadata: 'unsupported',
          page_name: 'fallback',
          previous_page: nil,
          next_page: 2,
          current_page: 1
        ) { %w[item1 item2] }

        result = scroll_metadata(prop)

        expect(result).to eq(
          pageName: 'fallback',
          previousPage: nil,
          nextPage: 2,
          currentPage: 1
        )
      end
    end

    context 'with malformed intent values' do
      it 'defaults to append with unexpected value' do
        prop = described_class.new(metadata: page, wrapper: 'data') { %w[item1 item2] }

        expect(announced(prop, intent: 'invalid_value')).to include(mergeProps: ['items.data'])
      end

      it 'defaults to append with empty value' do
        prop = described_class.new(metadata: page, wrapper: 'data') { %w[item1 item2] }

        expect(announced(prop, intent: '')).to include(mergeProps: ['items.data'])
      end

      it 'defaults to append with nil value' do
        prop = described_class.new(metadata: page, wrapper: 'data') { %w[item1 item2] }

        expect(announced(prop, intent: nil)).to include(mergeProps: ['items.data'])
      end

      it 'handles case sensitivity correctly' do
        prop = described_class.new(metadata: page, wrapper: 'data') { %w[item1 item2] }

        expect(announced(prop, intent: 'PREPEND')).to include(mergeProps: ['items.data'])
      end

      it 'handles prepend with correct case' do
        prop = described_class.new(metadata: page, wrapper: 'data') { %w[item1 item2] }

        expect(announced(prop, intent: 'prepend')).to include(prependProps: ['items.data'])
      end
    end

    context 'with metadata options precedence' do
      let(:hash_metadata) do
        {
          page_name: 'original',
          previous_page: 1,
          next_page: 3,
          current_page: 2,
        }
      end

      it 'allows page_name override' do
        prop = described_class.new(
          metadata: hash_metadata,
          page_name: 'overridden'
        ) { %w[item1 item2] }

        result = scroll_metadata(prop)

        expect(result[:pageName]).to eq('overridden')
        expect(result[:currentPage]).to eq(2)
      end

      it 'allows multiple options override' do
        prop = described_class.new(
          metadata: hash_metadata,
          page_name: 'custom_page',
          current_page: 5,
          next_page: 6
        ) { %w[item1 item2] }

        result = scroll_metadata(prop)

        expect(result).to eq(
          pageName: 'custom_page',
          previousPage: 1,
          nextPage: 6,
          currentPage: 5
        )
      end

      it 'preserves original metadata when no options provided' do
        prop = described_class.new(metadata: hash_metadata) { %w[item1 item2] }

        result = scroll_metadata(prop)

        expect(result).to eq(
          pageName: 'original',
          previousPage: 1,
          nextPage: 3,
          currentPage: 2
        )
      end
    end

    context 'without metadata' do
      it 'handles nil metadata with options' do
        prop = described_class.new(
          metadata: nil,
          page_name: 'no_metadata',
          previous_page: nil,
          next_page: 2,
          current_page: 1
        ) { %w[item1 item2] }

        result = scroll_metadata(prop)

        expect(result).to eq(
          pageName: 'no_metadata',
          previousPage: nil,
          nextPage: 2,
          currentPage: 1
        )
      end

      it 'raises error when metadata is nil and insufficient options' do
        prop = described_class.new(
          metadata: nil,
          page_name: 'incomplete'
        ) { %w[item1 item2] }

        expect do
          announced(prop)
        end.to raise_error(
          Inertia::Core::ScrollMetadata::MissingMetadataAdapterError,
          'No ScrollMetadata adapter found for nil - pass Pagy/Kaminari, a Hash, or the page fields as options.'
        )
      end
    end
  end
end
