# frozen_string_literal: true

RSpec.describe InertiaRails::VERSION do
  # The gemspec pins the core to this exact version, so a release that bumped
  # only one of them would publish an adapter nobody can install.
  it 'matches the version of the core gem it depends on' do
    expect(InertiaRails::VERSION).to eq Inertia::Core::VERSION
  end
end
