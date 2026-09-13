# frozen_string_literal: true

require_relative 'spec_helper'

# Exact examples cover the compositions someone thought of. This generates them
# instead: a recipe is a tree of producers and containers, built at random and
# interpreted into props. Recipes are plain data, so a failure prints the shape
# that caused it and can be replayed by pasting it back.
#
# The oracle is what makes this worth running. Every serializer carries a marker
# that only its unserialized form exposes, so a leak is visible no matter where
# in the tree it happened.
module PropShapes
  MARKER = 'LEAKMARKER'

  # Producers wrap one child. Containers hold children at a key or an index.
  WRAPPERS = %i[closure serializer hash_serializer array_serializer].freeze
  PROP_TYPES = %i[defer optional merge always once cache].freeze
  CONTAINERS = %i[hash array nested_array].freeze
  # Leaves whose own JSON representation must survive resolution. The walk
  # hands such a container back untouched (see `container_spec.rb`), but this
  # oracle is the json gem's `to_json`, which never consults `as_json`, so the
  # marker they store would show whatever the walk did. Only an encoder that
  # asks `as_json` can tell — `spec/inertia/opaque_container_spec.rb` does.
  CUSTOM_JSON = [].freeze
  # Self-referential producers: resolution must refuse them, not exhaust the stack.
  CYCLES = %i[cycle_hash cycle_array].freeze

  ALL = (WRAPPERS + PROP_TYPES + CONTAINERS + CUSTOM_JSON + CYCLES).freeze

  VISITS = [
    {},
    { partial: true, only: ['a'] },
    { partial: true, except: ['a.b'] }
  ].freeze
end

RSpec.describe 'prop resolution properties' do
  # -- recipes ---------------------------------------------------------------

  # While a known defect is being fixed its shapes drown out everything else.
  # `EXCLUDE_KINDS=cycle_hash,cycle_array` narrows the generator to the rest.
  def kinds
    @kinds ||= PropShapes::ALL - ENV.fetch('EXCLUDE_KINDS', '').split(',').map(&:to_sym)
  end

  def random_recipe(random, depth)
    return [%i[scalar nil_value plain_hash].sample(random: random)] if depth.zero?

    kind = kinds.sample(random: random)

    case kind
    when *PropShapes::CYCLES then [kind]
    when :hash then [:hash, { a: random_recipe(random, depth - 1), b: random_recipe(random, depth - 1) }]
    when :array then [:array, [random_recipe(random, depth - 1), random_recipe(random, depth - 1)]]
    when :nested_array then [:nested_array, random_recipe(random, depth - 1)]
    else [kind, random_recipe(random, depth - 1)]
    end
  end

  def children_of(recipe)
    kind, child = recipe
    return [] if child.nil?

    case kind
    when :hash then child.values
    when :array then child
    else [child]
    end
  end

  def recipe_uses?(recipe, kinds)
    return true if kinds.include?(recipe.first)

    children_of(recipe).any? { |c| recipe_uses?(c, kinds) }
  end

  # -- interpretation --------------------------------------------------------

  def serializer(value)
    object = Object.new
    object.instance_variable_set(:@marker, PropShapes::MARKER)
    object.define_singleton_method(:to_inertia) { value }
    object
  end

  def container_serializer(base, value)
    klass = Class.new(base) { define_method(:to_inertia) { value } }
    base == Hash ? klass.new.tap { |h| h[:marker] = PropShapes::MARKER } : klass.new.tap { |a| a << PropShapes::MARKER }
  end

  # Overrides `as_json`, so nothing it stores should ever reach the payload —
  # including a child that would otherwise resolve.
  def custom_json(base, value)
    klass = Class.new(base) { def as_json(*) = { safe: true } }
    if base == Hash
      klass.new.tap do |h|
        h[:marker] = PropShapes::MARKER
        h[:child] = value
      end
    else
      klass.new.tap { |a| a.push(PropShapes::MARKER, value) }
    end
  end

  def cyclic(base)
    object = Object.new
    object.define_singleton_method(:to_inertia) { base == Hash ? { child: object } : [object] }
    object
  end

  def interpret(recipe)
    kind, child = recipe
    inner = -> { interpret(child) }

    case kind
    when :scalar then 'value'
    when :nil_value then nil
    when :plain_hash then { id: 1 }
    when :hash then child.transform_values { |c| interpret(c) }
    when :array then child.map { |c| interpret(c) }
    when :nested_array then [[interpret(child)]]
    when :closure then -> { inner.call }
    when :serializer then serializer(inner.call)
    when :hash_serializer then container_serializer(Hash, inner.call)
    when :array_serializer then container_serializer(Array, inner.call)
    when :hash_as_json then custom_json(Hash, inner.call)
    when :array_as_json then custom_json(Array, inner.call)
    when :cycle_hash then cyclic(Hash)
    when :cycle_array then cyclic(Array)
    when :defer then Inertia::Core::DeferProp.new { inner.call }
    when :optional then Inertia::Core::OptionalProp.new { inner.call }
    when :merge then Inertia::Core::MergeProp.new { inner.call }
    when :always then Inertia::Core::AlwaysProp.new { inner.call }
    when :once then Inertia::Core::OnceProp.new { inner.call }
    when :cache then Inertia::Core::CachedProp.new("k#{rand(1 << 32)}") { inner.call }
    end
  end

  # The shapes resolution refuses: a producer that never settles, a prop type
  # stored in a cached value, a prop type used as an array element (`cache`
  # excepted — caching is invisible to the client), and an opaque container
  # holding anything that would need resolving.
  def refusal_expected?(recipe)
    recipe_uses?(recipe, PropShapes::CYCLES) ||
      cached_prop_type?(recipe, inside_cache: false) ||
      array_element_prop_type?(recipe, inside_element: false) ||
      stacked_prop_types?(recipe) ||
      opaque_holding_resolvable?(recipe)
  end

  # A prop type below another prop type on one spine is refused stacking.
  # Over-approximating is safe: the oracle checks that a refusal was
  # allowed, not that one must happen.
  def stacked_prop_types?(recipe, saw_prop: false)
    kind, = recipe
    if (PropShapes::WRAPPERS + PropShapes::PROP_TYPES).include?(kind)
      return true if saw_prop && PropShapes::PROP_TYPES.include?(kind)

      saw = saw_prop || PropShapes::PROP_TYPES.include?(kind)
      children_of(recipe).any? { |c| stacked_prop_types?(c, saw_prop: saw) }
    else
      children_of(recipe).any? { |c| stacked_prop_types?(c) }
    end
  end

  def cached_prop_type?(recipe, inside_cache:)
    kind, = recipe
    return true if inside_cache && PropShapes::PROP_TYPES.include?(kind)

    inside_cache ||= kind == :cache
    children_of(recipe).any? { |c| cached_prop_type?(c, inside_cache: inside_cache) }
  end

  # Wrappers (closures, serializers) keep the position they sit in; a hash gives
  # its children prop keys again, so it resets the element context.
  def array_element_prop_type?(recipe, inside_element:)
    kind, = recipe
    return true if inside_element && (PropShapes::PROP_TYPES - [:cache]).include?(kind)

    case kind
    when :hash
      children_of(recipe).any? { |c| array_element_prop_type?(c, inside_element: false) }
    when :array, :nested_array
      children_of(recipe).any? { |c| array_element_prop_type?(c, inside_element: true) }
    else
      children_of(recipe).any? { |c| array_element_prop_type?(c, inside_element: inside_element) }
    end
  end

  # Mirrors `needs_resolving?`: anything below an opaque container that would
  # need resolving makes the container itself a refusal.
  def opaque_holding_resolvable?(recipe)
    kind, child = recipe
    return resolvable?(child) if PropShapes::CUSTOM_JSON.include?(kind)

    children_of(recipe).any? { |c| opaque_holding_resolvable?(c) }
  end

  def resolvable?(recipe)
    kind, child = recipe
    return true if (PropShapes::WRAPPERS + PropShapes::PROP_TYPES + PropShapes::CYCLES).include?(kind)
    return resolvable?(child) if PropShapes::CUSTOM_JSON.include?(kind)

    children_of(recipe).any? { |c| resolvable?(c) }
  end

  # -- the properties --------------------------------------------------------

  def resolve(props, visit)
    Inertia::Core::PropsResolver.new(props, evaluator: evaluator, visit: visit).resolve
  end

  # Returns [outcome, payload]: either [:resolved, json] or [:refused, nil].
  # Any other ending is a property violation and is raised to the caller.
  def outcome_for(recipe, visit)
    resolved, = resolve({ a: interpret(recipe) }, visit)
    [:resolved, resolved.to_json]
  rescue Inertia::Core::Error
    [:refused, nil]
  end

  it 'never leaks an unserialized value, whatever the shape' do
    random = Random.new(RSpec.configuration.seed)
    failures = []

    400.times do
      recipe = random_recipe(random, random.rand(1..4))
      visit = PropShapes::VISITS.sample(random: random)

      begin
        outcome, json = outcome_for(recipe, visit)

        # A refusal is only allowed for shapes the library documents as invalid:
        # a value that produces itself, or a prop type below a cached block.
        if outcome == :refused && !refusal_expected?(recipe)
          failures << ["refused a valid shape on #{visit}", recipe]
          next
        end

        failures << ["leaked the marker on #{visit}", recipe] if json&.include?(PropShapes::MARKER)
        failures << ["left a prop type unresolved on #{visit}", recipe] if json&.match?(/Inertia::Core::\w+Prop/)
      rescue SystemStackError
        failures << ["exhausted the stack on #{visit}", recipe]
      rescue StandardError => e
        failures << ["raised #{e.class} on #{visit}", recipe]
      end
    end

    expect(failures).to be_empty, -> { report(failures) }
  end

  it 'resolves to the same payload twice, whatever the shape' do
    random = Random.new(RSpec.configuration.seed + 1)
    failures = []

    200.times do
      recipe = random_recipe(random, random.rand(1..4))
      next if recipe_uses?(recipe, PropShapes::CYCLES)

      visit = PropShapes::VISITS.sample(random: random)
      props = { a: interpret(recipe) }

      begin
        first, = resolve(props, visit)
        second, = resolve(props, visit)
        failures << ['differed between resolutions', recipe] if first.to_json != second.to_json
      rescue Inertia::Core::Error
        next
      rescue SystemStackError, StandardError => e
        failures << ["raised #{e.class}", recipe]
      end
    end

    expect(failures).to be_empty, -> { report(failures) }
  end

  # Whether a key is filtered out must follow from the visit, not from whether
  # its neighbours happen to need resolving.
  it 'filters an indexed path regardless of what else the container holds' do
    random = Random.new(RSpec.configuration.seed + 2)
    failures = []

    200.times do
      recipe = random_recipe(random, random.rand(0..3))
      next if recipe_uses?(recipe, PropShapes::CYCLES)

      plain = { drop: 'DROPME', other: interpret(recipe) }

      # A container that does not override `as_json` sends what it stores, so it
      # is filtered like the container it extends however it is wrapped.
      containers = {
        'a hash' => plain,
        'a hash subclass' => Class.new(Hash).new.merge(plain),
      }

      containers.each do |container_name, element|
        resolved, = resolve({ a: [element] }, { partial: true, except: ['a.0.drop'] })
        failures << ["kept an excluded path in #{container_name}", recipe] if resolved.to_json.include?('DROPME')

        nested, = resolve({ a: [[element]] }, { partial: true, except: ['a.0.0.drop'] })
        if nested.to_json.include?('DROPME')
          failures << ["kept an excluded path below two arrays in #{container_name}",
                       recipe]
        end
      rescue Inertia::Core::Error
        next
      rescue SystemStackError, StandardError => e
        failures << ["raised #{e.class} for #{container_name}", recipe]
      end
    end

    expect(failures).to be_empty, -> { report(failures) }
  end

  # A chain that is too deep at a prop key is too deep as an array element.
  it 'enforces the same depth limit wherever a chain sits' do
    failures = []

    [12, 126, 130].each do |levels|
      chain = levels.times.reduce('end') do |inner, i|
        i.even? ? serializer(inner) : -> { inner }
      end

      at_key = begin
        resolve({ a: chain }, {}) && :resolved
      rescue Inertia::Core::Error
        :refused
      end

      in_array = begin
        resolve({ a: [chain] }, {}) && :resolved
      rescue Inertia::Core::Error
        :refused
      end

      failures << ["#{at_key} at a key but #{in_array} in an array", [:chain, levels]] if at_key != in_array
    end

    expect(failures).to be_empty, -> { report(failures) }
  end

  # `rescue:` is for a failing data source. A shape the library itself refuses
  # must keep raising, not become a quietly dropped prop.
  it 'never converts a structural refusal into a rescued prop' do
    random = Random.new(RSpec.configuration.seed + 3)
    visit = { partial: true, only: ['a'] }
    failures = []

    200.times do
      recipe = random_recipe(random, random.rand(1..3))
      next if recipe_uses?(recipe, PropShapes::CYCLES)

      refused = begin
        resolve({ a: interpret(recipe) }, visit)
        false
      rescue Inertia::Core::Error
        true
      rescue StandardError
        next
      end
      next unless refused

      begin
        # Built outside the block: a prop block is `instance_exec`'d on the
        # controller, where the generator's own methods do not exist.
        value = interpret(recipe)
        _, metadata = resolve({ a: Inertia::Core::DeferProp.new(rescue: true) { value } }, visit)
        failures << ['swallowed a refusal as rescuedProps', recipe] if metadata[:rescuedProps]
      rescue Inertia::Core::Error
        next
      rescue StandardError => e
        failures << ["raised #{e.class}", recipe]
      end
    end

    expect(failures).to be_empty, -> { report(failures) }
  end

  def report(failures)
    grouped = failures.group_by(&:first)
    lines = grouped.map do |reason, entries|
      "#{entries.size}x #{reason}\n    e.g. #{entries.first.last.inspect}"
    end
    "#{failures.size} property violations (seed #{RSpec.configuration.seed}):\n  #{lines.join("\n  ")}"
  end
end
