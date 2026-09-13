# frozen_string_literal: true

RSpec.describe InertiaRails::Renderer do
  describe 'deep merging shared data' do
    def merged_props(shared:, props:)
      configuration = double('configuration', encrypt_history: false, deep_merge_shared_data: true,
                                              clear_history: false, expose_shared_prop_keys: true, layout: true)
      controller = double('controller', inertia_configuration: configuration, inertia_view_assigns: {},
                                        session: {}, inertia_shared_data: shared)
      renderer = described_class.new('Component', controller, double(headers: {}), double(headers: {}),
                                     ->(args) {}, props: props)
      renderer.instance_variable_get(:@props)
    end

    it 'deep merges and symbolizes literal hashes' do
      merged = merged_props(shared: { nested: { 'goals' => 100 } }, props: { 'nested' => { assists: 200 } })

      expect(merged).to eq(nested: { goals: 100, assists: 200 })
    end

    # `deep_symbolize_keys`/`deep_merge!` rebuilt every container, stripping a
    # serializer's own `to_inertia`/`as_json` and leaking its raw contents.
    it 'keeps a Hash to_inertia serializer whole' do
      secret = { secret: 'raw' }
      def secret.to_inertia = { safe: true }

      merged = merged_props(shared: { user: { name: 'A' } }, props: { user: { profile: secret } })

      expect(merged[:user][:profile]).to respond_to(:to_inertia)
    end

    it 'keeps a Hash with its own as_json whole' do
      secret = { secret: 'raw' }
      def secret.as_json(*) = { safe: true }

      merged = merged_props(shared: { user: { name: 'A' } }, props: { user: { profile: secret } })

      expect(merged[:user][:profile].as_json).to eq({ safe: true })
    end

    it 'keeps an Array to_inertia serializer whole' do
      list = [{ secret: 'raw' }]
      def list.to_inertia = [{ safe: true }]

      merged = merged_props(shared: { feed: { page: 1 } }, props: { feed: { items: list } })

      expect(merged[:feed][:items]).to respond_to(:to_inertia)
    end

    it 'keeps an Array with its own as_json whole' do
      list = [{ secret: 'raw' }]
      def list.as_json(*) = [{ safe: true }]

      merged = merged_props(shared: { feed: { page: 1 } }, props: { feed: { items: list } })

      expect(merged[:feed][:items].as_json).to eq([{ safe: true }])
    end
  end

  let(:deprecator) do
    double(warn: nil).tap do |deprecator|
      allow(InertiaRails).to receive(:deprecator).and_return(deprecator)
    end
  end

  %i[component configuration controller props view_data encrypt_history clear_history].each do |method_name|
    it "has a deprecated #{method_name} accessor" do
      configuration = double('configuration',
                             encrypt_history: true,
                             deep_merge_shared_data: false,
                             clear_history: false,
                             expose_shared_prop_keys: true,
                             layout: true)

      controller = double('controller',
                          inertia_configuration: configuration,
                          inertia_view_assigns: {},
                          session: {},
                          inertia_shared_data: {})

      request = double('request', headers: {})
      response = double('response', headers: {}, set_header: nil)
      render_method = ->(args) {}

      renderer = InertiaRails::Renderer.new('MyComponent', controller, request, response, render_method)

      expect(deprecator).to receive(:warn)
        .with(
          "[DEPRECATION] Accessing `InertiaRails::Renderer##{method_name}` is deprecated and will be removed in v4.0"
        )

      renderer.send(method_name)
    end
  end
end
