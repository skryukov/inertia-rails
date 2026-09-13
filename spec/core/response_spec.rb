# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::Response do
  def env(inertia: true, **headers)
    base = { 'REQUEST_METHOD' => 'GET', 'SCRIPT_NAME' => '', 'PATH_INFO' => '/dashboard', 'QUERY_STRING' => 'q=1' }
    base['HTTP_X_INERTIA'] = 'true' if inertia
    headers.each { |name, value| base["HTTP_#{name.to_s.upcase.tr('-', '_')}"] = value }
    base
  end

  def response(props = { name: 'Ada' }, configuration: Inertia::Core::Configuration.new(version: 'v1'),
               component: 'Dashboard', **options)
    described_class.new(component, props, env: options.delete(:env) || env, configuration: configuration,
                                          evaluator: evaluator, **options)
  end

  def meta(page)
    page[:props][:_inertia_meta].map(&:as_json)
  end

  # Rack 3 wants lowercase response header names; the core follows whichever is loaded.
  def header(name)
    Inertia::Core::Rack.header_name(name)
  end

  it 'answers an Inertia request with the page as JSON' do
    inertia = response

    expect(inertia.json?).to be true
    expect(inertia.content_type).to eq 'application/json'
    expect(inertia.headers('Accept')).to eq(header('Vary') => 'Accept, X-Inertia', header('X-Inertia') => 'true')
    expect(JSON.parse(inertia.json)).to include('component' => 'Dashboard', 'props' => { 'name' => 'Ada' },
                                                'url' => '/dashboard?q=1', 'version' => 'v1')
  end

  it 'answers a first load with the root element the configuration describes' do
    configuration = Inertia::Core::Configuration.new(version: 'v1', use_script_element_for_initial_page: true)
    inertia = response(env: env(inertia: false), configuration: configuration)

    expect(inertia.json?).to be false
    expect(inertia.content_type).to eq 'text/html'
    expect(inertia.headers).to eq(header('Vary') => 'X-Inertia')
    expect(inertia.html(nonce: 'abc')).to eq(
      Inertia::Core::Protocol.root_element(inertia.page, id: 'app', script: true, nonce: 'abc')
    )
    expect(inertia.ssr?).to be false
    expect(inertia.head).to be_nil
  end

  it 'reads the partial reload off the request and resolves the page once' do
    calls = 0
    name = lambda do
      calls += 1
      'Ada'
    end
    inertia = response({ name: name, count: -> { 1 } },
                       env: env('X-Inertia-Partial-Component' => 'Dashboard',
                                'X-Inertia-Partial-Data' => 'name'))

    expect(inertia.partial?).to be true
    expect(inertia.page[:props]).to eq(name: 'Ada')
    inertia.json
    inertia.metadata
    expect(calls).to eq 1
    expect(host.events).to include([:resolve_props, { component: 'Dashboard', partial: true }])
  end

  it 'never reads an absent partial header as a partial reload of a render without a component name' do
    inertia = response({ name: 'Ada', count: 1 }, component: nil, env: env('X-Inertia-Partial-Data' => 'name'))

    expect(inertia.partial?).to be false
    expect(inertia.page[:props]).to eq(name: 'Ada', count: 1)
  end

  it 'always ships the errors prop, on a partial reload too' do
    inertia = response({ errors: { name: 'taken' }, name: 'Ada' },
                       env: env('X-Inertia-Partial-Component' => 'Dashboard', 'X-Inertia-Partial-Data' => 'name'))

    expect(inertia.page[:props]).to eq(name: 'Ada', errors: { name: 'taken' })
  end

  it 'fills the page envelope from what the host hands over' do
    inertia = response(url: '/custom', flash: { notice: 'hi' }, shared_keys: ['name'], encrypt_history: true,
                       clear_history: true, preserve_fragment: true)

    expect(inertia.page).to include(url: '/custom', flash: { notice: 'hi' }, sharedProps: ['name'],
                                    encryptHistory: true, clearHistory: true, preserveFragment: true)
  end

  it 'runs the prop transformer before adding the head tags' do
    configuration = Inertia::Core::Configuration.new(prop_transformer: lambda { |props:|
      props.transform_keys { |key| :"x_#{key}" }
    })
    head = Inertia::Core::MetaTagBuilder.new.add(title: 'T')
    page = response(head: head, configuration: configuration).page

    expect(page[:props].keys).to eq %i[x_name _inertia_meta]
    expect(meta(page)).to eq [{ tagName: :title, headKey: 'title', innerContent: 'T' }]
  end

  it 'ships the head as markup under server_head, and refuses a prop that takes its name' do
    configuration = Inertia::Core::Configuration.new(server_head: true)
    head = Inertia::Core::MetaTagBuilder.new.add(title: 'T')

    expect(response(head: head, configuration: configuration).page[:props][:head])
      .to eq ['<title data-inertia="title">T</title>']
    expect { response({ head: 1 }, configuration: configuration).page }
      .to raise_error(Inertia::Core::Error, /`head` prop is reserved/)
  end

  it 'runs the title template in the evaluator context, with the current title' do
    configuration = Inertia::Core::Configuration.new(
      meta_title_template: ->(title) { "#{title || 'Home'} | #{controller_method}" }
    )

    expect(meta(response(configuration: configuration).page))
      .to eq [{ tagName: :title, headKey: 'title', innerContent: 'Home | controller_method value' }]

    head = Inertia::Core::MetaTagBuilder.new.add(title: 'T')
    expect(meta(response(head: head, configuration: configuration).page).first[:innerContent])
      .to eq 'T | controller_method value'
  end

  describe 'SSR' do
    let(:configuration) { Inertia::Core::Configuration.new(ssr_enabled: true) }

    def ssr_answers(result)
      client = instance_double(Inertia::Core::SSR::Client, render: result)
      allow(Inertia::Core::SSR::Client).to receive(:new).and_return(client)
    end

    it 'renders through the SSR server on a first load and hands over head and body' do
      ssr_answers('head' => ['<title>S</title>', '<meta>'], 'body' => '<div id="app">ssr</div>')
      inertia = response(env: env(inertia: false), configuration: configuration)

      expect(inertia.ssr?).to be true
      expect(inertia.head).to eq '<title>S</title><meta>'
      expect(inertia.html).to eq '<div id="app">ssr</div>'
      expect(Inertia::Core::SSR::Client).to have_received(:new)
        .with(configuration, page: inertia.page, host: host, cache: nil)
    end

    it 'falls back to the root element when the server does not answer' do
      ssr_answers(nil)
      inertia = response(env: env(inertia: false), configuration: configuration)

      expect(inertia.ssr?).to be false
      expect(inertia.html).to include('<div id="app" data-page=')
    end

    it 'never renders SSR for an Inertia request' do
      allow(Inertia::Core::SSR::Client).to receive(:new)
      response(configuration: configuration).json

      expect(Inertia::Core::SSR::Client).not_to have_received(:new)
    end
  end
end
