# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in inertia_rails.gemspec
gemspec

version = ENV.fetch('RAILS_VERSION', '8.1')
gem 'rails', "~> #{version}.0"

gem 'debug'
gem 'generator_spec', '~> 0.10'
gem 'json', '< 3' if version.to_f <= 8.1
gem 'puma', version.to_f < 7 ? '< 7' : '>= 7'
gem 'rails-controller-testing'
gem 'rake', '~> 13.0'
gem 'responders'
gem 'rspec-rails', '~> 6.0'
gem 'rubocop', '~> 1.21'
gem 'sqlite3', version.to_f < 7.1 ? '~> 1.4' : '>= 2.0'

gem 'kaminari'
gem 'pagy'

# The host matrix (spec/core/hosts): the real non-Rails apps the core is mounted
# in. Only a floor is named, so every Ruby/Rails pair resolves a set that agrees
# on one Rack — the older ones land on Sinatra 3 over Rack 2, the newer on Rack 3.
gem 'hanami-router', '>= 2.0'
gem 'rack-test', '>= 2.0'
gem 'sinatra', '>= 3.0'
