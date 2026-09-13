# frozen_string_literal: true

# The whole cache-store contract the core calls: `fetch(key, **options) { }`.
# Entries and the options each key was fetched with are readable for assertions.
class TestCacheStore
  attr_reader :options

  def initialize
    @entries = {}
    @options = {}
  end

  def fetch(key, **options)
    @options[key] = options
    return @entries[key] if @entries.key?(key)

    @entries[key] = yield
  end

  def [](key)
    @entries[key]
  end

  def []=(key, value)
    @entries[key] = value
  end
end
