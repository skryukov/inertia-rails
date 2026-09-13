# frozen_string_literal: true

RSpec.shared_examples 'a prop' do
  describe '#call' do
    subject(:call) { evaluate(prop, context) }

    let(:prop) { described_class.new { 'block' } }
    let(:context) { TestContext.new }

    it { is_expected.to eq('block') }

    context 'with dependency on the context of a controller' do
      let(:prop) { described_class.new { controller_method } }

      it { is_expected.to eq('controller_method value') }
    end
  end
end
