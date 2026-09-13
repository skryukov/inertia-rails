# frozen_string_literal: true

# The core suite runs on plain Ruby: no Rails, no ActiveSupport. Anything a
# spec needs from a host is a tiny test double in spec/support.
require_relative '../lib/inertia/core'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.order = :random
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
