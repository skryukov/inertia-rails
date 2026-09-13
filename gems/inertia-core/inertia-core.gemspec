# frozen_string_literal: true

require_relative 'lib/inertia/core/version'

Gem::Specification.new do |spec|
  spec.name          = 'inertia-core'
  spec.version       = Inertia::Core::VERSION
  spec.authors       = ['Svyatoslav Kryukov']
  spec.email         = ['s.g.kryukov@yandex.ru']

  spec.summary       = 'The framework-agnostic half of the Inertia.js server protocol'
  spec.description   = 'Prop types, their resolution against a visit, the page object, and the ' \
                       'request/response decisions every Inertia.js adapter makes the same way. ' \
                       'Plain Ruby, stdlib only; inertia_rails is one adapter built on it.'
  spec.homepage      = 'https://github.com/inertiajs/inertia-rails'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.0'

  spec.metadata = {
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'changelog_uri' => "#{spec.homepage}/blob/master/gems/inertia-core/CHANGELOG.md",
    'documentation_uri' => "#{spec.homepage}/blob/master/gems/inertia-core/README.md",
    'homepage_uri' => spec.homepage,
    'source_code_uri' => "#{spec.homepage}/tree/master/gems/inertia-core",
    'rubygems_mfa_required' => 'true',
  }

  spec.files = Dir['lib/**/*', 'CHANGELOG.md', 'LICENSE.txt', 'README.md']
  spec.require_paths = ['lib']

  # The host matrix (spec/hosts): the real non-Rails apps the core is mounted in.
  # Only a floor is named, so every Ruby resolves a set that agrees on one Rack:
  # the older ones land on hanami-router 2.x and Sinatra 3 over Rack 2, the newer
  # on Rack 3.
  # rubocop:disable Gemspec/DevelopmentDependencies
  spec.add_development_dependency 'hanami-router', '>= 2.0'
  spec.add_development_dependency 'rack-test', '>= 2.0'
  spec.add_development_dependency 'sinatra', '>= 3.0'
  # rubocop:enable Gemspec/DevelopmentDependencies
end
