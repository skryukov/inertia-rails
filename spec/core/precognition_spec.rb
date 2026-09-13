# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::Precognition do
  def env(precognition: true, only: nil)
    env = {}
    env['HTTP_PRECOGNITION'] = 'true' if precognition
    env['HTTP_PRECOGNITION_VALIDATE_ONLY'] = only if only
    env
  end

  it 'reads the request headers' do
    expect(described_class.request?(env)).to be true
    expect(described_class.request?(env(precognition: false))).to be false
    expect(described_class.validate_only(env(only: 'name, email'))).to eq %w[name email]
    expect(described_class.validate_only(env)).to be_nil
  end

  it 'is nil for a request that is not precognitive' do
    expect(described_class.validate(env(precognition: false), { name: ['blank'] })).to be_nil
  end

  it 'normalizes a model, a hash-like, a to_h and a hash' do
    model = Class.new do
      def valid? = false
      def errors = { name: ['blank'] }
    end.new
    hash_like = Class.new { def to_hash = { email: ['bad'] } }.new

    expect(described_class.validate(env, model)).to eq(name: ['blank'])
    expect(described_class.validate(env, hash_like)).to eq(email: ['bad'])
    expect(described_class.validate(env, Struct.new(:phone).new(['short']))).to eq(phone: ['short'])
    expect(described_class.validate(env, { a: 1 })).to eq(a: 1)
    expect { described_class.validate(env, 42) }.to raise_error(ArgumentError, /Expected a Hash/)
  end

  it 'keeps only the fields Validate-Only names, whichever key type the errors use' do
    errors = { name: ['a'], 'email' => ['b'], phone: ['c'] }

    expect(described_class.validate(env(only: 'name,email'), errors)).to eq(name: ['a'], 'email' => ['b'])
  end

  it 'refuses a second validation in one request, precognitive or not' do
    plain = env(precognition: false)
    described_class.validate(plain, {})

    expect { described_class.validate(plain, {}) }
      .to raise_error(Inertia::Core::DoublePrecognitionError, /once per action/)
  end

  it 'answers 204 with Precognition-Success on a pass, 422 with the errors otherwise' do
    expect(described_class.status({})).to eq 204
    expect(described_class.headers({})).to eq('Precognition' => 'true', 'Precognition-Success' => 'true')
    expect(described_class.body({})).to be_nil

    expect(described_class.status(name: ['x'])).to eq 422
    expect(described_class.headers(name: ['x'])).to eq('Precognition' => 'true')
    expect(described_class.body(name: ['x'])).to eq(errors: { name: ['x'] })
  end
end
