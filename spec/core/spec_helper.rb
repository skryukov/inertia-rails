# frozen_string_literal: true

# The core suite runs on plain Ruby: no Rails, no ActiveSupport. Run it on its
# own with `bundle exec rspec -O spec/core/.rspec spec/core`; under the root
# `.rspec` (`bundle exec rspec spec/core`) it runs inside the Rails suite.
require_relative '../../lib/inertia/core'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.order = :random
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
