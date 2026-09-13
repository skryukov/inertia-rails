# frozen_string_literal: true

# `RawJson` itself is covered in the core suite
# (`gems/inertia-core/spec/raw_json_spec.rb`). What stays here is the encoder
# Rails uses, which goes through `#as_json` rather than `#to_json`.
RSpec.describe InertiaRails::RawJson do
  describe '#as_json' do
    it 'returns a value compatible with JSON encoding' do
      raw = described_class.new('[1,2,3]')
      expect { ActiveSupport::JSON.encode(data: raw) }.not_to raise_error
    end
  end

  describe 'embedding in ActiveSupport::JSON.encode' do
    it 'embeds the raw string without double-escaping' do
      raw = described_class.new('{"items":[1,2,3]}')
      hash = { component: 'Test', props: { data: raw } }

      parsed = JSON.parse(ActiveSupport::JSON.encode(hash))
      expect(parsed['props']['data']).to eq({ 'items' => [1, 2, 3] })
    end
  end
end
