# frozen_string_literal: true

require_relative '../spec_helper'
require_relative 'support/inertia_host_examples'

require 'hanami/router'

# The endpoint a route resolves to: one per request, and the context prop blocks
# run inside.
class HanamiDashboard
  # What the core asks of its host. Hanami::Router has no cache of its own, so
  # `cache:` props keep their JSON in a Hash that lives as long as the process.
  class InertiaHost < Inertia::Core::Host
    class Store
      def initialize
        @entries = {}
      end

      def fetch(key, **_options)
        @entries.fetch(key) { @entries[key] = yield }
      end
    end

    def cache_store
      @cache_store ||= Store.new
    end

    def expand_cache_key(key)
      "hanami/#{Array(key).join('/')}"
    end
  end

  CONFIGURATION = Inertia::Core::Configuration.new(version: 'v1', use_script_element_for_initial_page: true)
  HOST = InertiaHost.new
  COMPONENT = 'Dashboard'

  def initialize(env)
    @env = env
  end

  # The protocol decides the form; the endpoint writes the Rack triple,
  # wrapping a first load in its own layout.
  def call
    evaluator = Inertia::Core::PropEvaluator.new(self, host: HOST)
    inertia = Inertia::Core::Response.new(COMPONENT, props, env: @env, configuration: CONFIGURATION,
                                                            evaluator: evaluator)
    body = inertia.json? ? inertia.json : "<!DOCTYPE html><html><body>#{inertia.html}</body></html>"

    [200, inertia.headers.merge('content-type' => inertia.content_type), [body]]
  end

  private

  def signed_in_user
    'Ada'
  end

  def props
    {
      user: -> { { name: signed_in_user, bio: 'writes </script> tags' } },
      notifications: Inertia::Core::AlwaysProp.new { 2 },
      stats: Inertia::Core::DeferProp.new(group: 'metrics') { { visits: 42 } },
      settings: Inertia::Core::OnceProp.new(key: 'settings') { { theme: 'dark' } },
      feed: Inertia::Core::MergeProp.new { [1, 2] },
      clock: Inertia::Core::LiveProp.new(on: 'tick', channel: 'clock') { '12:00' },
      menu: Inertia::Core::CachedProp.new('menu') { %w[Home Billing] },
    }
  end
end

RSpec.describe 'Inertia::Core in a Hanami::Router app' do
  let(:router) do
    Hanami::Router.new do
      get '/dashboard', to: ->(env) { HanamiDashboard.new(env).call }
      # A 302 after a PUT would replay the PUT on the target; the protocol
      # rewrites it to 303.
      put '/dashboard', to: ->(_env) { [302, { 'location' => '/dashboard' }, []] }
      get '/billing', to: lambda { |_env|
        [302, { 'location' => 'https://billing.test/checkout', 'set-cookie' => 'checkout=started; path=/' }, []]
      }
    end
  end

  let(:app) { Inertia::Core::Rack::Middleware.new(router, configuration: HanamiDashboard::CONFIGURATION) }

  it_behaves_like 'an Inertia host'
end
