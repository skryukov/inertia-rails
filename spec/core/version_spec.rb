# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../../lib/inertia_rails/version'

RSpec.describe 'Inertia::Core::VERSION' do
  it 'is released in lockstep with inertia_rails' do
    expect(Inertia::Core::VERSION).to eq InertiaRails::VERSION
  end
end
