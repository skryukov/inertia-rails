# frozen_string_literal: true

# A host with an in-memory store that records what the core asks of it.
class TestHost < Inertia::Core::Host
  attr_reader :store, :reported, :events

  def initialize
    super
    @store = TestCacheStore.new
    @reported = []
    @events = []
  end

  def cache_store
    @store
  end

  def expand_cache_key(key)
    "test/#{Array(key).join('/')}"
  end

  def report_error(error, **context)
    @reported << [error, context]
  end

  def instrument(event, payload = {})
    result = yield(payload)
    @events << [event, payload]
    result
  end
end
