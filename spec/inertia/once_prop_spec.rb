# frozen_string_literal: true

# `OnceProp` is covered in the core suite
# (`gems/inertia-core/spec/once_prop_spec.rb`). What stays here is the
# ActiveSupport spelling of `expires_in:`.
RSpec.describe InertiaRails::OnceProp do
  let(:freeze_time) { Time.now }

  before do
    allow(Time).to receive(:now).and_return(freeze_time)
  end

  it 'announces the expiration timestamp in milliseconds with ActiveSupport::Duration' do
    prop = described_class.new(expires_in: 1.hour) { 'value' }
    expected = ((freeze_time + 1.hour).to_f * 1000).to_i

    expect(announced(prop)[:onceProps]['key']).to include(expiresAt: expected)
  end
end
