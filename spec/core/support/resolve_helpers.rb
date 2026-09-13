# frozen_string_literal: true

# Resolves props against a fresh TestHost per example.
module CoreResolveHelpers
  def host
    @host ||= TestHost.new
  end

  def evaluator(context = TestContext.new)
    Inertia::Core::PropEvaluator.new(context, host: host)
  end

  def resolve(props, visit = {}, **options)
    Inertia::Core::PropsResolver.new(props, evaluator: evaluator, visit: visit, **options).resolve
  end
end

RSpec.configure { |config| config.include CoreResolveHelpers, file_path: %r{/spec/core/} }
