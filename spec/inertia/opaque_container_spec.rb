# frozen_string_literal: true

# A `Hash` or `Array` that decides its own JSON is handed over untouched
# instead of being rebuilt. `Container.opaque?` recognises one by comparing
# `as_json` owners against the base's; ActiveSupport puts one on `Hash` and
# `Array`, so a subclass that only inherits it is the half of the rule this
# suite can pin (the core suite pins the other, in `container_spec.rb`).
#
# What reaches the wire is the encoder's call, and Rails' varies: 6.1, 7.0 and
# 8.1 (`JSON::Coder`) send the container's own `as_json`; 7.1 to 8.0 walk any
# `Hash`/`Array` natively and never ask. So these examples check the object the
# walk hands back, not the JSON Rails makes of it.
RSpec.describe InertiaRails::PropsResolver, 'containers that serialize themselves' do
  let(:evaluator) { InertiaRails::PropEvaluator.new(Object.new, host: InertiaRails.host) }

  def resolve(props, visit: {})
    resolved_props, metadata = described_class.new(props, evaluator: evaluator, visit: visit).resolve
    { props: resolved_props }.merge(metadata)
  end

  def resolve_partial(props, *only, **visit_opts)
    resolve(props, visit: { partial: true, only: only.map(&:to_s), **visit_opts })
  end

  context 'with an exact container carrying a singleton as_json' do
    let(:opaque_hash) do
      value = { secret: 1 }
      def value.as_json(*) = { safe: true }
      value
    end

    it 'honors it at a prop key' do
      expect(resolve({ a: opaque_hash })[:props][:a]).to be(opaque_hash)
    end

    it 'honors it inside an array being resolved' do
      page = resolve({ a: [opaque_hash, -> { 'x' }] })

      expect(page[:props][:a][0]).to be(opaque_hash)
      expect(page[:props][:a][1]).to eq('x')
    end

    it 'honors it inside a produced hash' do
      value = opaque_hash
      page = resolve({ a: -> { { nested: value, x: -> { 1 } } } })

      expect(page[:props][:a][:nested]).to be(value)
      expect(page[:props][:a][:x]).to eq(1)
    end
  end

  # A container subclass may define its own `as_json`. Rebuilding it as a
  # plain `Hash` or `Array` drops that and exposes whatever it stores, so one
  # with nothing to resolve inside is handed over untouched.
  context 'with a container subclass that defines as_json' do
    let(:opaque_hash) do
      klass = Class.new(Hash) do
        def as_json(*) = { safe: true }
      end
      klass.new.tap { |hash| hash[:secret] = 'exposed' }
    end

    let(:opaque_array) do
      klass = Class.new(Array) do
        def as_json(*) = ['safe']
      end
      klass.new.tap { |array| array << 'exposed' }
    end

    it 'keeps a Hash subclass as it is' do
      expect(resolve({ a: opaque_hash })[:props][:a]).to be(opaque_hash)
    end

    it 'keeps an Array subclass as it is' do
      expect(resolve({ a: opaque_array })[:props][:a]).to be(opaque_array)
    end

    it 'keeps one nested inside an array that does need resolving' do
      page = resolve({ a: [opaque_hash, -> { 'x' }] })

      expect(page[:props][:a][0]).to be(opaque_hash)
      expect(page[:props][:a][1]).to eq('x')
    end

    # The walk cannot resolve inside a container that decides its own JSON,
    # and an `as_json` that decorates its contents (a key-transforming
    # subclass, say) would publish a producer unresolved. Refused, not leaked.
    it 'refuses one whose contents include a producer' do
      klass = Class.new(Hash) do
        def as_json(*) = { safe: true }
      end
      holder = klass.new.tap { |hash| hash[:secret] = -> { 'exposed' } }

      expect { resolve({ a: holder }) }
        .to raise_error(InertiaRails::ResolutionError, /defines its own `as_json`/)
    end

    it 'refuses one whose as_json decorates contents holding a prop type' do
      klass = Class.new(Hash) do
        def as_json(*args) = transform_keys(&:to_s).as_json(*args)
      end
      holder = klass.new.tap { |hash| hash[:stats] = InertiaRails.defer { 'expensive' } }

      expect { resolve({ a: holder }) }
        .to raise_error(InertiaRails::ResolutionError, /defines its own `as_json`/)
    end

    it 'refuses an opaque array whose contents include a producer' do
      klass = Class.new(Array) do
        def as_json(*) = ['safe']
      end
      holder = klass.new.push(-> { 'exposed' })

      expect { resolve({ a: holder }) }
        .to raise_error(InertiaRails::ResolutionError, /defines its own `as_json`/)
    end

    it 'refuses one a producer hands back with a producer still inside' do
      klass = Class.new(Hash) do
        def as_json(*) = { safe: true }
      end
      holder = klass.new.tap { |hash| hash[:secret] = -> { 'exposed' } }

      expect { resolve({ a: -> { holder } }) }
        .to raise_error(InertiaRails::ResolutionError, /defines its own `as_json`/)
    end

    # Inheriting `Hash#as_json` is not an override. `HashWithIndifferentAccess`
    # sends exactly what a `Hash` would, so partial paths still address it.
    it 'filters a subclass that only inherits container serialization' do
      props = { user: { name: 'n', secret: 's' }.with_indifferent_access }

      expect(resolve(props, visit: { partial: true, only: ['user.name'] })[:props][:user])
        .to eq({ 'name' => 'n' })
    end

    it 'filters a bare Hash subclass the same way' do
      props = { user: Class.new(Hash).new.merge({ name: 'n', secret: 's' }) }

      expect(resolve(props, visit: { partial: true, except: ['user.secret'] })[:props][:user])
        .to eq({ name: 'n' })
    end

    it 'keeps one a closure produced' do
      row = opaque_hash

      expect(resolve({ a: -> { { row: row } } })[:props][:a][:row]).to be(row)
    end
  end

  it 'gives an as_json-overriding hash at an unrequested index a nil slot' do
    opaque = Class.new(Hash) do
      def as_json(*) = 'opaque'
    end
    page = resolve_partial(
      { rows: [{ name: 'First' }, opaque.new] },
      'rows.0.name'
    )

    expect(page[:props][:rows]).to eq([{ name: 'First' }, nil])
  end

  # Copying the target strips a singleton `as_json`, so the raw contents
  # would ship in place of the container's own serialization.
  it 'refuses to write into a container with its own as_json' do
    secret = { secret: 'raw' }
    def secret.as_json(*) = { safe: true }

    expect { resolve({ :user => secret, 'user.age' => 1 }) }
      .to raise_error(InertiaRails::ResolutionError, /defines its own `as_json`/)
  end
end
