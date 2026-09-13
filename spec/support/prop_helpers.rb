# frozen_string_literal: true

# Observes props through their public contract: what they announce in the
# page metadata and whether a visit gets them delivered.
module PropHelpers
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
    evaluator = Inertia::Core::PropEvaluator.new(Object.new, host: InertiaRails.host)
    Inertia::Core::PropsResolver.new({ path.to_sym => prop }, evaluator: evaluator, visit: visit, eager: eager)
  end

  # What the prop's block or value produces in this context.
  def evaluate(prop, context)
    prop.produce(Inertia::Core::PropEvaluator.new(context, host: InertiaRails.host))
  end

  # What the resolver ships for the prop once a visit lets it through:
  # produced, cached when asked to be, walked.
  def shipped(prop, context)
    evaluator = Inertia::Core::PropEvaluator.new(context, host: InertiaRails.host)
    Inertia::Core::PropsResolver.new({ key: prop }, evaluator: evaluator, eager: true).resolve.first[:key]
  end
end

RSpec.configure do |config|
  config.include PropHelpers
end
