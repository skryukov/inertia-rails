# frozen_string_literal: true

require_relative '../spec_helper'
require_relative 'support/inertia_host_examples'

require 'sinatra/base'

class SinatraDashboard < Sinatra::Base
  # What the core asks of its host. Sinatra has no cache of its own, so `cache:`
  # props keep their JSON in a Hash that lives as long as the process.
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
      "sinatra/#{Array(key).join('/')}"
    end
  end

  CONFIGURATION = Inertia::Core::Configuration.new(version: 'v1', use_script_element_for_initial_page: true)
  HOST = InertiaHost.new

  # An error in a route must fail the example, not become Sinatra's debug page —
  # and Sinatra 4 only serves the development host allowlist under :development.
  set :environment, :test

  get '/dashboard' do
    render_inertia 'Dashboard', dashboard_props
  end

  # A 302 after a PUT would replay the PUT on the target, so Sinatra's own
  # method-aware status is passed over: the protocol is what makes this a 303.
  put '/dashboard' do
    redirect '/dashboard', 302
  end

  get '/billing' do
    response.set_cookie('checkout', value: 'started', path: '/')
    redirect 'https://billing.test/checkout', 302
  end

  private

  def signed_in_user
    'Ada'
  end

  # Prop blocks run inside this app instance, so they reach its own methods.
  def dashboard_props
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

  # The protocol decides the form; Sinatra writes it out, wrapping a first
  # load in its own layout.
  def render_inertia(component, props)
    evaluator = Inertia::Core::PropEvaluator.new(self, host: HOST)
    inertia = Inertia::Core::Response.new(component, props, env: request.env, configuration: CONFIGURATION,
                                                            evaluator: evaluator)
    headers inertia.headers(response.headers['Vary'])
    content_type inertia.content_type
    inertia.json? ? inertia.json : "<!DOCTYPE html><html><body>#{inertia.html}</body></html>"
  end
end

RSpec.describe 'Inertia::Core in a Sinatra app' do
  let(:app) do
    Inertia::Core::Rack::Middleware.new(SinatraDashboard, configuration: SinatraDashboard::CONFIGURATION)
  end

  it_behaves_like 'an Inertia host'
end
