# frozen_string_literal: true

require 'rails_helper'

# The walk itself is covered in the core suite
# (`gems/inertia-core/spec/props_resolver_spec.rb`). What stays here is what
# `InertiaRails::CoreHost` contributes to it.
RSpec.describe InertiaRails::PropsResolver do
  let(:evaluator) { InertiaRails::PropEvaluator.new(Object.new, host: InertiaRails.host) }

  it 'reports the rescued error via the Rails error reporter' do
    skip('Requires Rails 7.0 or higher') if Rails.version < '7'

    error = RuntimeError.new('boom')
    expect(Rails.error).to receive(:report).with(error, handled: true, context: { prop: 'permissions' })

    described_class.new(
      { permissions: InertiaRails.defer(rescue: true) { raise error } },
      evaluator: evaluator, visit: { partial: true, only: ['permissions'] }
    ).resolve
  end
end
