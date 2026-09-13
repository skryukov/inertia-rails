# frozen_string_literal: true

# Plain Ruby gives `Hash` and `Array` no `as_json`, so here any answer is the
# value's own. The Rails suite covers the other half of the rule: a subclass
# that only inherits ActiveSupport's is not opaque (`opaque_container_spec.rb`).
RSpec.describe Inertia::Core::Container do
  let(:hash_class) { Class.new(Hash) { def as_json(*) = { safe: true } } }
  let(:array_class) { Class.new(Array) { def as_json(*) = ['safe'] } }
  let(:opaque_hash) { hash_class.new.tap { |hash| hash[:secret] = 'exposed' } }
  let(:opaque_array) { array_class.new.push('exposed') }
  let(:singleton_hash) do
    value = { secret: 'exposed' }
    def value.as_json(*) = { safe: true }
    value
  end

  describe '.opaque?' do
    it 'recognises a subclass that defines as_json' do
      expect(described_class.opaque?(opaque_hash)).to be(true)
      expect(described_class.opaque?(opaque_array)).to be(true)
    end

    it 'recognises a singleton as_json' do
      expect(described_class.opaque?(singleton_hash)).to be(true)
    end

    it 'leaves a container with nothing of its own alone' do
      expect(described_class.opaque?({ secret: 'exposed' })).to be(false)
      expect(described_class.opaque?(Class.new(Hash).new)).to be(false)
      expect(described_class.opaque?([])).to be(false)
    end

    it 'answers false for a value that is no container' do
      value = Object.new
      def value.as_json(*) = {}

      expect(described_class.opaque?(value)).to be(false)
    end
  end

  describe '.plain?' do
    it 'excludes an opaque container' do
      expect(described_class.plain?(opaque_hash)).to be(false)
      expect(described_class.plain?({ secret: 'exposed' })).to be(true)
    end
  end

  # Rebuilding an opaque container would drop the `as_json` it carries, so
  # the walk hands back the very object it was given.
  describe 'in the walk' do
    it 'hands an opaque container back untouched' do
      props, = resolve({ a: opaque_hash, b: opaque_array, c: singleton_hash })

      expect(props[:a]).to be(opaque_hash)
      expect(props[:b]).to be(opaque_array)
      expect(props[:c]).to be(singleton_hash)
    end

    it 'hands one back from inside a container that is being resolved' do
      props, = resolve({ a: [opaque_hash, -> { 'x' }] })

      expect(props[:a][0]).to be(opaque_hash)
      expect(props[:a][1]).to eq('x')
    end

    it 'refuses one that holds a producer' do
      holder = hash_class.new.tap { |hash| hash[:secret] = -> { 'exposed' } }

      expect { resolve({ a: holder }) }
        .to raise_error(Inertia::Core::ResolutionError, /defines its own `as_json`/)
    end
  end
end
