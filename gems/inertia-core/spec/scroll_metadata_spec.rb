# frozen_string_literal: true

RSpec.describe Inertia::Core::ScrollMetadata do
  describe '.extract' do
    context 'with Hash adapter' do
      let(:hash_metadata) do
        {
          page_name: 'items',
          previous_page: 1,
          next_page: 3,
          current_page: 2,
        }
      end

      it 'extracts metadata from hash' do
        result = described_class.extract(hash_metadata)

        expect(result).to eq(
          pageName: 'items',
          previousPage: 1,
          nextPage: 3,
          currentPage: 2
        )
      end

      it 'raises error when required keys are missing' do
        incomplete_hash = { page_name: 'items' }

        expect do
          described_class.extract(incomplete_hash)
        end.to raise_error(KeyError)
      end

      it 'allows options to override hash values' do
        result = described_class.extract(
          hash_metadata,
          page_name: 'overridden',
          next_page: 5
        )

        expect(result).to eq(
          pageName: 'overridden',
          previousPage: 1,
          nextPage: 5,
          currentPage: 2
        )
      end
    end

    context 'with unsupported metadata type' do
      it 'raises MissingMetadataAdapterError with no options provided' do
        unsupported_metadata = 'unsupported'

        expect do
          described_class.extract(unsupported_metadata)
        end.to raise_error(
          Inertia::Core::ScrollMetadata::MissingMetadataAdapterError,
          'No ScrollMetadata adapter found for "unsupported" ' \
          '- pass Pagy/Kaminari, a Hash, or the page fields as options.'
        )
      end

      it 'uses options as fallback when no adapter matches' do
        unsupported_metadata = 'unsupported'

        result = described_class.extract(
          unsupported_metadata,
          page_name: 'fallback',
          previous_page: nil,
          next_page: nil,
          current_page: 1
        )

        expect(result).to eq(
          pageName: 'fallback',
          previousPage: nil,
          nextPage: nil,
          currentPage: 1
        )
      end

      it 'raises error when insufficient options provided for unsupported type' do
        unsupported_metadata = 'unsupported'

        expect do
          described_class.extract(unsupported_metadata, page_name: 'fallback')
        end.to raise_error(
          Inertia::Core::ScrollMetadata::MissingMetadataAdapterError,
          'No ScrollMetadata adapter found for "unsupported" ' \
          '- pass Pagy/Kaminari, a Hash, or the page fields as options.'
        )
      end
    end

    context 'with nil metadata' do
      it 'uses options to create props when all required options provided' do
        result = described_class.extract(
          nil,
          page_name: 'nil_page',
          previous_page: nil,
          next_page: 2,
          current_page: 1
        )

        expect(result).to eq(
          pageName: 'nil_page',
          previousPage: nil,
          nextPage: 2,
          currentPage: 1
        )
      end

      it 'raises error when insufficient options provided for nil metadata' do
        expect do
          described_class.extract(nil, page_name: 'partial')
        end.to raise_error(
          Inertia::Core::ScrollMetadata::MissingMetadataAdapterError,
          'No ScrollMetadata adapter found for nil - pass Pagy/Kaminari, a Hash, or the page fields as options.'
        )
      end
    end
  end

  describe 'adapter option validation' do
    let(:page) { { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 } }

    # A typo of a supported override vanished without a trace: the built-in
    # adapters take `**options` and read none of them.
    it 'refuses an option a built-in adapter does not accept' do
      expect { described_class.extract(page, curent_page: 9) }
        .to raise_error(ArgumentError, /Unknown scroll metadata option\(s\): curent_page/)
    end

    it 'names the unknown option instead of blaming absent metadata' do
      expect { described_class.extract(nil, curent_page: 9, page_name: 'p') }
        .to raise_error(ArgumentError, /curent_page/)
    end

    it 'validates against a custom adapter declaring accepted_options' do
      adapter = Class.new do
        def match?(metadata) = metadata == :strict
        def accepted_options = %i[cursor_name]

        def call(_metadata, **options)
          { page_name: options.fetch(:cursor_name, 'page'), previous_page: nil, next_page: 2, current_page: 1 }
        end
      end
      described_class.register_adapter(adapter)

      expect(described_class.extract(:strict, cursor_name: 'c')[:pageName]).to eq('c')
      expect { described_class.extract(:strict, cursr_name: 'c') }
        .to raise_error(ArgumentError, /cursr_name/)
    ensure
      described_class.adapters.shift
    end

    it 'leaves a custom adapter without accepted_options open' do
      adapter = Class.new do
        def match?(metadata) = metadata == :open

        def call(_metadata, **options)
          { page_name: options.fetch(:anything, 'page'), previous_page: nil, next_page: 2, current_page: 1 }
        end
      end
      described_class.register_adapter(adapter)

      expect(described_class.extract(:open, anything: 'goes')[:pageName]).to eq('goes')
    ensure
      described_class.adapters.shift
    end

    # `adapters` is a public writer; an adapter assigned there directly gets
    # the same treatment as a registered one.
    it 'leaves an adapter assigned to adapters= without accepted_options open' do
      adapter = Class.new do
        def match?(metadata) = metadata == :assigned

        def call(_metadata, **options)
          { page_name: options.fetch(:anything, 'page'), previous_page: nil, next_page: 2, current_page: 1 }
        end
      end
      described_class.adapters = [adapter.new] + described_class.adapters

      expect(described_class.extract(:assigned, anything: 'goes')[:pageName]).to eq('goes')
    ensure
      described_class.adapters.shift
    end
  end

  describe '.register_adapter' do
    around do |example|
      registered = described_class.adapters.dup
      example.run
    ensure
      described_class.adapters = registered
    end

    it 'registers custom adapter and gives it priority' do
      custom_adapter_class = Class.new do
        def match?(metadata)
          metadata == 'custom'
        end

        def call(_metadata, **_options)
          {
            page_name: 'custom_adapter',
            previous_page: nil,
            next_page: nil,
            current_page: 1,
          }
        end
      end

      described_class.register_adapter(custom_adapter_class)

      result = described_class.extract('custom')

      expect(result).to eq(
        pageName: 'custom_adapter',
        previousPage: nil,
        nextPage: nil,
        currentPage: 1
      )
    end

    it 'leaves a frozen adapter result untouched when applying overrides' do
      frozen_adapter = Class.new do
        def match?(metadata) = metadata == 'frozen'

        def call(_metadata, **_options)
          { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }.freeze
        end
      end

      described_class.register_adapter(frozen_adapter)

      result = described_class.extract('frozen', current_page: 5)

      expect(result).to include(currentPage: 5)
    end

    it 'gives precedence to most recently registered adapters' do
      first_adapter = Class.new do
        def match?(metadata)
          metadata.is_a?(Hash)
        end

        def call(_metadata, **_options)
          {
            page_name: 'first_adapter',
            previous_page: nil,
            next_page: nil,
            current_page: 1,
          }
        end
      end

      second_adapter = Class.new do
        def match?(metadata)
          metadata.is_a?(Hash)
        end

        def call(_metadata, **_options)
          {
            page_name: 'second_adapter',
            previous_page: nil,
            next_page: nil,
            current_page: 1,
          }
        end
      end

      described_class.register_adapter(first_adapter)
      described_class.register_adapter(second_adapter)

      result = described_class.extract({})

      expect(result[:pageName]).to eq('second_adapter')
    end
  end
end
