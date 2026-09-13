# frozen_string_literal: true

# Observes a prop through its public contract: what it announces in the page
# metadata, whether a visit gets it delivered, what it produces, and what the
# resolver ships for it.
module CorePropHelpers
  def announced(prop, path: 'key', visit: {}, eager: false)
    resolver_for(prop, path, visit, eager).resolve.last
  end

  def delivered?(prop, path: 'key', visit: {}, eager: false)
    resolver = resolver_for(prop, path, visit, eager)
    resolver.resolve
    resolver.ledger.first.delivered?
  end

  # The prop on its own, met by the walk at the given path.
  def resolver_for(prop, path, visit, eager)
    Inertia::Core::PropsResolver.new({ path.to_sym => prop }, evaluator: evaluator, visit: visit, eager: eager)
  end

  # What the prop's block or value produces in this context.
  def evaluate(prop, context = TestContext.new)
    prop.produce(evaluator(context))
  end

  # What the resolver ships for the prop once a visit lets it through:
  # produced, cached when asked to be, walked.
  def shipped(prop, context = TestContext.new)
    Inertia::Core::PropsResolver.new({ key: prop }, evaluator: evaluator(context), eager: true).resolve.first[:key]
  end
end

# Only for the core suite: under the root `.rspec` the Rails suite has its own
# PropHelpers against the real host, and a global include would shadow them.
RSpec.configure { |config| config.include CorePropHelpers }
