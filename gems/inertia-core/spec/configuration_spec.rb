# frozen_string_literal: true

RSpec.describe Inertia::Core::Configuration do
  it 'declares the framework-neutral options with their defaults' do
    config = described_class.new(**described_class.options)

    expect(config.version).to be_nil
    expect(config.encrypt_history).to be false
    expect(config.deep_merge_shared_data).to be false
    expect(config.component_path_resolver(path: 'users', action: 'index')).to eq 'users/index'
    expect(config.prop_transformer(props: { a: 1 })).to eq(a: 1)
  end

  it 'refuses options it does not declare' do
    expect { described_class.new(layout: true) }.to raise_error(ArgumentError, /Unknown options.*layout/)
  end

  it 'evaluates callables inside the bound context' do
    config = described_class.new(version: -> { assets_version })
    context = Class.new { def assets_version = 'ctx-v' }.new

    expect(config.bind(context).version).to eq 'ctx-v'
  end

  it 'evaluates callables with no context by calling them' do
    expect(described_class.new(version: -> { 'plain' }).version).to eq 'plain'
  end

  it 'overlays INERTIA_* environment values on the defaults, coercing booleans' do
    config = described_class.default({ 'INERTIA_VERSION' => '42', 'INERTIA_ENCRYPT_HISTORY' => 'true' })

    expect(config.version).to eq '42'
    expect(config.encrypt_history).to be true
  end

  it 'reads an environment value the way the declared default means it' do
    off = described_class.default({ 'INERTIA_SSR_ENABLED' => '0', 'INERTIA_VERSION' => '1' })
    on = described_class.default({ 'INERTIA_SSR_ENABLED' => 'on' })

    expect(off.ssr_enabled).to be false
    # A version is a string, so a digit stays one rather than turning boolean.
    expect(off.version).to eq '1'
    expect(on.ssr_enabled).to be true
  end

  it 'does not allow to modify options after frozen' do
    config = described_class.default({})
    config.ssr_enabled = true
    expect(config.ssr_enabled).to be true

    config.freeze
    expect { config.ssr_enabled = false }.to raise_error(FrozenError)
    expect { config.merge!(described_class.default({})) }.to raise_error(FrozenError)
    expect(config.merge(described_class.default({})).ssr_enabled).to be false
  end

  it 'raises for invalid xsrf_cookie_refresh values when read' do
    config = described_class.new(xsrf_cookie_refresh: :sometimes)

    expect do
      config.xsrf_cookie_refresh
    end.to raise_error(ArgumentError, /Invalid xsrf_cookie_refresh/)
  end

  it 'raises for invalid INERTIA_XSRF_COOKIE_REFRESH env values when read' do
    config = described_class.default({ 'INERTIA_XSRF_COOKIE_REFRESH' => 'garbage' })

    expect do
      config.xsrf_cookie_refresh
    end.to raise_error(ArgumentError, /Invalid xsrf_cookie_refresh/)
  end

  it 'symbolizes a valid xsrf_cookie_refresh string' do
    expect(described_class.new(xsrf_cookie_refresh: 'lazy').xsrf_cookie_refresh).to eq :lazy
  end

  describe '#head_attribute' do
    it 'defaults to :inertia' do
      expect(described_class.new.head_attribute).to eq :inertia
    end

    it 'returns :"data-inertia" when use_data_inertia_head_attribute is enabled' do
      config = described_class.new
      config.use_data_inertia_head_attribute = true

      expect(config.head_attribute).to eq :'data-inertia'
    end

    it 'returns :"data-inertia" when server_head is enabled, regardless of use_data_inertia_head_attribute' do
      config = described_class.new
      config.server_head = true
      config.use_data_inertia_head_attribute = false

      expect(config.head_attribute).to eq :'data-inertia'
    end
  end

  describe '#meta_prop' do
    it 'is :_inertia_meta when server_head is disabled' do
      expect(described_class.new.meta_prop).to eq :_inertia_meta
    end

    it 'is :head when server_head is true' do
      config = described_class.new
      config.server_head = true

      expect(config.meta_prop).to eq :head
    end

    it 'is the configured name when server_head is a string' do
      config = described_class.new
      config.server_head = 'custom_meta'

      expect(config.meta_prop).to eq :custom_meta
    end
  end

  it 'hands back an `evaluate: false` option without calling it' do
    handler = ->(error, page) { [error, page] }
    expect(described_class.new(on_ssr_error: handler).on_ssr_error).to be handler
  end

  it 'refuses a meta_title_template that is not callable' do
    expect { described_class.new(meta_title_template: 'x').meta_title_template }
      .to raise_error(ArgumentError, /meta_title_template must be callable/)
  end

  it 'lets a subclass add options and override a reader with super' do
    subclass = Class.new(described_class) do
      option :layout, true
      option :mode, 'plain'

      def mode
        super.upcase
      end
    end

    config = subclass.new(**subclass.options, mode: 'fancy')
    expect(config.layout).to be true
    expect(config.mode).to eq 'FANCY'
    expect(subclass.option_names).to include(:version, :layout, :mode)
    expect(described_class.option_names).not_to include(:layout)
  end

  it 'layers configurations: merge keeps both, with_defaults fills from the parent' do
    parent = described_class.new(version: 'p', encrypt_history: true)
    child = described_class.new(version: 'c')

    expect(parent.merge(child).version).to eq 'c'
    expect(parent.merge(child).encrypt_history).to be true

    child.with_defaults(parent)
    expect(child.version).to eq 'c'
    expect(child.encrypt_history).to be true
    expect(child).to be_frozen
  end
end
