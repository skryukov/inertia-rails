# frozen_string_literal: true

# The core's promise to other hosts: it loads and resolves on plain Ruby, with
# the default Host, and ActiveSupport never enters the process. The suite runs
# under Rails, so this runs a child Ruby.
RSpec.describe 'Inertia::Core on bare Ruby' do
  let(:script) { <<~RUBY }
    require 'inertia/core'
    require 'json'

    class Store
      def initialize = @entries = {}
      def fetch(key, **) = @entries[key] ||= yield
    end

    class Host < Inertia::Core::Host
      attr_reader :rescued
      def initialize = @rescued = []
      def cache_store = @store ||= Store.new
      def expand_cache_key(key) = key.to_s
      def report_error(error, **) = @rescued << error.class.name
    end

    host = Host.new
    evaluator = Inertia::Core::PropEvaluator.new(Object.new, host: host)
    props = {
      plain: -> { { at: Time.at(0).utc } },
      safe: Inertia::Core::DeferProp.new(rescue: true) { { list: Inertia::Core::CachedProp.new('k') { [1] }, at: Time.at(0).utc } },
      broken: Inertia::Core::DeferProp.new(rescue: true) { raise 'boom' },
    }
    visit = Inertia::Core::Visit.from_env(
      { 'HTTP_X_INERTIA_PARTIAL_COMPONENT' => 'C', 'HTTP_X_INERTIA_PARTIAL_DATA' => 'plain,safe,broken' },
      component: 'C'
    )
    resolved, metadata = Inertia::Core::PropsResolver.new(props, evaluator: evaluator, visit: visit).resolve

    puts JSON.generate(
      active_support: defined?(ActiveSupport) ? true : false,
      page: JSON.parse(JSON.generate(props: resolved, **metadata)),
      rescued: host.rescued
    )
  RUBY

  it 'resolves, caches and rescues with the default host, without ActiveSupport' do
    lib = File.expand_path('../lib', __dir__)
    output = IO.popen(['ruby', '-I', lib, '-e', script], err: %i[child out], &:read)
    expect($?).to be_success, output # rubocop:disable Style/SpecialGlobalVars

    result = JSON.parse(output)
    expect(result['active_support']).to be false
    # A rescued value crosses the same JSON boundary as the page: what the page
    # would ship (a Time as its string form, a cached value inline) survives.
    expect(result['page']).to eq(
      'props' => {
        'plain' => { 'at' => '1970-01-01 00:00:00 UTC' },
        'safe' => { 'list' => [1], 'at' => '1970-01-01 00:00:00 UTC' },
      },
      'rescuedProps' => ['broken']
    )
    expect(result['rescued']).to eq(['RuntimeError'])
  end
end
