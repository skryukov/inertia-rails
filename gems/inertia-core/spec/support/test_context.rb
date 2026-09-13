# frozen_string_literal: true

# Stands in for the controller-like object prop blocks are instance_exec'd in.
class TestContext
  def controller_method
    'controller_method value'
  end
end
