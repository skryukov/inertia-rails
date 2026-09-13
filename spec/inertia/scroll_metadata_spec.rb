# frozen_string_literal: true

# `ScrollMetadata` itself is covered in the core suite
# (`gems/inertia-core/spec/scroll_metadata_spec.rb`). The core ships no
# pagination adapters — they belong to the gems that define the pagination
# objects — so the Kaminari and Pagy ones and their registration order live here.
RSpec.describe InertiaRails::ScrollMetadata do
  describe '.extract' do
    context 'with Kaminari adapter' do
      before do
        stub_const('Kaminari', Class.new)
        stub_const('Kaminari::PageScopeMethods', Module.new)
        allow(Kaminari).to receive(:config).and_return(double(param_name: 'page'))
      end

      let(:kaminari_metadata) do
        instance_double('KaminariPage').tap do |metadata|
          metadata.extend(Kaminari::PageScopeMethods)
          allow(metadata).to receive(:prev_page).and_return(1)
          allow(metadata).to receive(:next_page).and_return(3)
          allow(metadata).to receive(:current_page).and_return(2)
        end
      end

      it 'extracts metadata from Kaminari paginator' do
        result = described_class.extract(kaminari_metadata)

        expect(result).to eq(
          pageName: 'page',
          previousPage: 1,
          nextPage: 3,
          currentPage: 2
        )
      end

      it 'handles nil param_name in Kaminari config' do
        allow(Kaminari.config).to receive(:param_name).and_return(nil)

        result = described_class.extract(kaminari_metadata)

        expect(result).to eq(
          pageName: 'page',
          previousPage: 1,
          nextPage: 3,
          currentPage: 2
        )
      end

      it 'allows options to override metadata values' do
        result = described_class.extract(
          kaminari_metadata,
          page_name: 'custom_page',
          current_page: 5
        )

        expect(result).to eq(
          pageName: 'custom_page',
          previousPage: 1,
          nextPage: 3,
          currentPage: 5
        )
      end
    end

    context 'with Pagy adapter' do
      let(:pagy_metadata) do
        instance_double('Pagy::Offset').tap do |metadata|
          allow(metadata).to receive(:is_a?).and_return(false)
          allow(metadata).to receive(:is_a?).with(Pagy).and_return(true)
          allow(metadata).to receive(:options).and_return({ page_key: :page })
          allow(metadata).to receive(:previous).and_return(1)
          allow(metadata).to receive(:next).and_return(3)
          allow(metadata).to receive(:page).and_return(2)
        end
      end

      it 'extracts metadata from Pagy paginator' do
        result = described_class.extract(pagy_metadata)

        expect(result).to eq(
          pageName: 'page',
          previousPage: 1,
          nextPage: 3,
          currentPage: 2
        )
      end

      it 'allows options to override metadata values' do
        result = described_class.extract(
          pagy_metadata,
          page_name: 'items_page',
          previous_page: 0
        )

        expect(result).to eq(
          pageName: 'items_page',
          previousPage: 0,
          nextPage: 3,
          currentPage: 2
        )
      end
    end
  end

  describe 'adapter precedence' do
    it 'tries adapters in registration order' do
      # Mock all adapters to match
      allow_any_instance_of(InertiaRails::ScrollAdapters::KaminariAdapter)
        .to receive(:match?).and_return(true)
      allow_any_instance_of(InertiaRails::ScrollAdapters::PagyAdapter)
        .to receive(:match?).and_return(true)
      allow_any_instance_of(InertiaRails::ScrollMetadata::HashAdapter)
        .to receive(:match?).and_return(true)

      # Mock calls to return identifiable results
      allow_any_instance_of(InertiaRails::ScrollAdapters::KaminariAdapter)
        .to receive(:call).and_return({
                                        page_name: 'kaminari',
                                        previous_page: nil,
                                        next_page: nil,
                                        current_page: 1,
                                      })

      result = described_class.extract('test')

      # Should use Kaminari adapter (first in the list)
      expect(result[:pageName]).to eq('kaminari')
    end
  end
end
