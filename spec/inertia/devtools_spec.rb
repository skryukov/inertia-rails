# frozen_string_literal: true

require 'tmpdir'

RSpec.describe 'InertiaRails DevTools', type: :request do
  let(:storage_path) { Dir.mktmpdir('inertia-devtools') }

  around do |example|
    example.run
  ensure
    FileUtils.remove_entry(storage_path) if File.directory?(storage_path)
  end

  def entries
    InertiaRails::Devtools.repository.all
  end

  def entry
    InertiaRails::Devtools.repository.get(entries.first['id'])
  end

  def partial_headers(*only, **extra)
    {
      'X-Inertia' => true,
      'X-Inertia-Partial-Component' => 'DevtoolsComponent',
      'X-Inertia-Partial-Data' => only.join(','),
    }.merge(extra)
  end

  context 'when disabled' do
    with_inertia_config devtools: false

    it 'records nothing and stamps no headers' do
      get devtools_props_path

      expect(response.headers).not_to include('X-Inertia-Devtools-Id')
      expect(response.body).not_to include('data-inertia-devtools-id')
    end

    it 'does not claim the read API paths' do
      expect { get '/_inertia/devtools/entries' }.to raise_error(ActionController::RoutingError)
    end

    it 'rejects devtools options in inertia_config' do
      expect do
        Class.new(ApplicationController) { inertia_config(devtools: true) }
      end.to raise_error(ArgumentError, /cannot be set per controller/)
    end
  end

  context 'when left to the environment' do
    with_inertia_config devtools: nil

    it 'records only in development' do
      expect(InertiaRails.configuration.devtools_enabled?).to be(false)

      allow(Rails.env).to receive(:development?).and_return(true)
      expect(InertiaRails.configuration.devtools_enabled?).to be(true)
    end

    it 'reads boolean-ish strings from the environment' do
      %w[false 0 off no].each do |value|
        InertiaRails.configuration.devtools = value
        expect(InertiaRails.configuration.devtools_enabled?).to be(false)
      end

      InertiaRails.configuration.devtools = '1'
      expect(InertiaRails.configuration.devtools_enabled?).to be(true)
    end
  end

  context 'when enabled' do
    with_inertia_config devtools: true

    before { InertiaRails.configuration.devtools_storage_path = storage_path }

    describe 'discovery' do
      it 'stamps the entry id on every response' do
        get devtools_props_path

        expect(response.headers['X-Inertia-Devtools-Id']).to match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/)
      end

      it 'injects the id into the initial page load' do
        get devtools_props_path

        id = response.headers['X-Inertia-Devtools-Id']
        expect(response.body).to include(
          %(<script data-inertia-devtools-id="" type="application/json">"#{id}"</script>)
        )
      end

      it 'leaves the tag out of Inertia responses' do
        get devtools_props_path, headers: { 'X-Inertia' => true }

        expect(response.body).not_to include('data-inertia-devtools-id')
      end

      it 'leaves the tag out of plain HTML responses' do
        app = ->(_env) { [200, { 'content-type' => 'text/html' }, ['<html><body>Plain</body></html>']] }
        env = Rack::MockRequest.env_for('/plain')
        _status, _headers, body = InertiaRails::Middleware.new(app).call(env)

        expect(body.each.to_a.join).not_to include('data-inertia-devtools-id')
        body.close
      end

      it 'leaves a response carrying a validator alone' do
        get devtools_cached_path

        expect(response.headers['ETag']).to be_present
        expect(response.body).not_to include('data-inertia-devtools-id')
        expect(response.headers['X-Inertia-Devtools-Id']).to be_present
      end

      # What ActionDispatch::Response#body returns for `render stream:` on Rails 7.1+.
      it 'does not mistake an unbuffered response stream for a body' do
        stream = Object.new
        stream.define_singleton_method(:each) { |&block| block.call('<html><body>real</body></html>') }
        body = Object.new
        body.define_singleton_method(:body) { stream }

        expect(InertiaRails::Devtools.buffered_body({}, body)).to be_nil
      end

      it 'skips configured path patterns without a leading slash' do
        InertiaRails.configuration.devtools_except = ['devtools_plain']

        get devtools_plain_path

        expect(response.headers).not_to include('X-Inertia-Devtools-Id')
        expect(entries).to be_empty
      end

      # `map '/sub' { run Rails.application }` in config.ru: the extension
      # reads the prefix from the page and fetches the read API beneath it.
      it 'serves the extension under the prefix the app is mounted at' do
        InertiaRails.configuration.devtools_authorize = -> { true }
        mounted = Rack::MockRequest.new(Rack::URLMap.new('/sub' => Rails.application))

        page = mounted.get('/sub/devtools_props')
        id = page.headers['X-Inertia-Devtools-Id']

        expect(page.headers['X-Inertia-Devtools-Base-Path']).to eq '/sub'
        expect(page.body).to include(%(data-inertia-devtools-base-path="/sub"))

        fetched = mounted.get("/sub/_inertia/devtools/entries/#{id}")

        expect(fetched.status).to eq 200
        expect(JSON.parse(fetched.body)['__meta']['url']).to eq 'http://example.org/sub/devtools_props'
      end
    end

    describe 'batching' do
      it 'starts a new batch on a full page visit, ignoring the incoming parent' do
        get devtools_props_path, headers: { 'X-Inertia-Devtools-Parent' => 'ignored' }

        expect(response.headers['X-Inertia-Devtools-Parent-Out']).to eq response.headers['X-Inertia-Devtools-Id']
        expect(entries.first['batchId']).to be_nil
      end

      it 'continues the batch across Inertia requests' do
        get devtools_props_path, headers: { 'X-Inertia' => true, 'X-Inertia-Devtools-Parent' => 'batch-1' }

        expect(response.headers['X-Inertia-Devtools-Parent-Out']).to eq 'batch-1'
        expect(entries.first['batchId']).to eq 'batch-1'
      end

      it 'gives a prefetch its own batch root while recording it under the originating batch' do
        get devtools_props_path, headers: {
          'X-Inertia' => true,
          'X-Inertia-Devtools-Parent' => 'batch-1',
          'Purpose' => 'prefetch',
        }

        expect(response.headers['X-Inertia-Devtools-Parent-Out']).to eq response.headers['X-Inertia-Devtools-Id']
        expect(entries.first['batchId']).to eq 'batch-1'
      end
    end

    describe 'request types' do
      it 'records a full page load as initial' do
        get devtools_props_path

        expect(entries.first['requestType']).to eq 'initial'
      end

      it 'records a non-Inertia endpoint as http' do
        get devtools_plain_path

        expect(entries.first['requestType']).to eq 'http'
      end

      it 'records an Inertia visit as navigate' do
        get devtools_props_path, headers: { 'X-Inertia' => true }

        expect(entries.first['requestType']).to eq 'navigate'
      end

      it 'trusts the client for deferred and poll follow-ups' do
        get devtools_props_path, headers: partial_headers('deferred', 'X-Inertia-Devtools-Deferred' => '1')
        expect(entries.first['requestType']).to eq 'deferred'

        get devtools_props_path, headers: partial_headers('name', 'X-Inertia-Devtools-Poll' => '1')
        expect(entries.first['requestType']).to eq 'poll'
      end

      it 'falls back to partial without a devtools intent header' do
        get devtools_props_path, headers: partial_headers('name')

        expect(entries.first['requestType']).to eq 'partial'
      end

      it 'records a precognition request' do
        post precognition_basic_path, headers: { 'Precognition' => 'true' }

        expect(entries.first['requestType']).to eq 'precognition'
      end
    end

    describe 'the entry' do
      subject(:recorded) do
        get devtools_props_path, headers: { 'X-Inertia-Devtools-Tab' => 'tab-1', 'X-Inertia-Devtools-Visit' => 'v-1' }
        entry
      end

      it 'carries the protocol metadata' do
        expect(recorded['__meta']).to include(
          'component' => 'DevtoolsComponent',
          'method' => 'GET',
          'status' => 200,
          'tabUuid' => 'tab-1',
          'visitId' => 'v-1'
        )
        expect(recorded['__meta']['timestamp']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
        expect(recorded['__meta']['serverTimingMs']).to be_a(Numeric)
      end

      it 'leaves props omitted from a first load to the request that delivers them' do
        expect(recorded['props'].keys).not_to include('optional', 'deferred')
      end

      it 'flags a reset prop' do
        get devtools_props_path, headers: partial_headers('items', 'X-Inertia-Reset' => 'items')

        expect(entry['props']['items']).to include('reset' => true)
      end

      it 'flags a rescued prop without a value' do
        get devtools_rescued_path, headers: partial_headers('permissions', 'X-Inertia-Devtools-Deferred' => '1')

        expect(entry['props']['permissions']).to include('rescued' => true)
        expect(entry['propValues']).not_to have_key('permissions')
        expect(entry['http']['responseBody']['value']['rescuedProps']).to eq ['permissions']
      end

      it 'flags shared props' do
        expect(recorded['props']['app_name']).to include('shared' => true)
        expect(recorded['props']['name']).to include('shared' => false, 'inertiaType' => nil)
      end

      it 'records the resolved values' do
        expect(recorded['propValues']).to include('name' => 'Brandon', 'always' => 'always param')
      end

      it 'records the final keys after prop transformation' do
        get prop_transformer_test_path, headers: { 'X-Inertia' => true }
        transformed = entry

        expect(transformed['props'].keys).to include('LOWER_PROP', 'PARENT_HASH')
        expect(transformed['props'].keys).not_to include('lower_prop', 'parent_hash')
        expect(transformed['propValues']).to include(
          'LOWER_PROP' => 'lower_value',
          'PARENT_HASH' => { 'LOWER_CHILD_PROP' => 'lower_child_value' }
        )
      end

      it 'captures the page object as the response body' do
        expect(recorded['http']['responseBody']['value']).to include('component' => 'DevtoolsComponent')
      end
    end

    describe 'bodies' do
      it 'omits a non-Inertia response body it cannot redact by key' do
        get non_inertiafied_path

        expect(entry['http']['responseBody']).to eq('status' => 'omitted', 'reason' => 'non-inertia-response')
      end

      it 'omits an unstructured body rather than storing it raw' do
        post devtools_create_path, params: 'password=hunter2',
                                   headers: { 'X-Inertia' => true, 'CONTENT_TYPE' => 'text/plain' }

        expect(entry['http']['requestBody']).to eq('status' => 'omitted', 'reason' => 'unserializable')
      end
    end

    describe 'redirects' do
      it 'records the redirect target' do
        post devtools_create_path, headers: { 'X-Inertia' => true }

        expect(entries.first['status']).to eq 302
        expect(entry['__meta']['redirectLocation']).to include('/devtools_props')
      end

      it 'records the status the protocol rewrote' do
        put redirect_test_path, headers: { 'X-Inertia' => true }

        expect(response.status).to eq 303
        expect(entries.first['status']).to eq 303
      end

      it 'omits a non-Inertia write body' do
        post devtools_create_path, params: { password: 'hunter2' }

        expect(entry['http']['requestBody']).to eq('status' => 'omitted', 'reason' => 'non-inertia-request')
      end
    end

    describe 'the read API' do
      # Outside development the API is gated, and the test environment is no exception.
      before do
        InertiaRails.configuration.devtools_authorize = -> { true }
        get devtools_props_path
      end

      it 'forbids the request when no gate is configured' do
        InertiaRails.configuration.devtools_authorize = nil

        get '/_inertia/devtools/entries'

        expect(response.status).to eq 403
      end

      it 'forbids the request when the gate denies it' do
        InertiaRails.configuration.devtools_authorize = -> { session[:admin] }

        get '/_inertia/devtools/entries'

        expect(response.status).to eq 403
      end

      it 'opens up in development without a gate' do
        InertiaRails.configuration.devtools_authorize = nil
        allow(Rails.env).to receive(:development?).and_return(true)

        get '/_inertia/devtools/entries'

        expect(response.status).to eq 200
      end

      it 'lists entry metadata newest first' do
        get devtools_plain_path
        get '/_inertia/devtools/entries'

        listed = response.parsed_body
        expect(listed.length).to eq 2
        expect(listed.first['requestType']).to eq 'http'
        expect(listed.map { |item| item['id'] }).to eq(listed.map { |item| item['id'] }.sort.reverse)
      end

      it 'filters by component and type' do
        get devtools_plain_path

        get '/_inertia/devtools/entries', params: { component: 'DevtoolsComponent' }
        expect(response.parsed_body.length).to eq 1

        get '/_inertia/devtools/entries', params: { exclude: 'http' }
        expect(response.parsed_body.length).to eq 1

        get '/_inertia/devtools/entries', params: { type: 'http' }
        expect(response.parsed_body.length).to eq 1
      end

      it 'clamps numeric limits to at least one' do
        get devtools_plain_path

        get '/_inertia/devtools/entries', params: { limit: 1 }
        expect(response.parsed_body.length).to eq 1

        get '/_inertia/devtools/entries', params: { limit: 0 }
        expect(response.parsed_body.length).to eq 1

        get '/_inertia/devtools/entries', params: { limit: -1 }
        expect(response.parsed_body.length).to eq 1
      end

      it 'applies an offset' do
        get devtools_plain_path

        get '/_inertia/devtools/entries', params: { offset: 1 }

        expect(response.parsed_body.length).to eq 1
        expect(response.parsed_body.first['requestType']).to eq 'initial'
      end

      it 'keeps its own polling out of the log' do
        logged = capture_log { get '/_inertia/devtools/entries' }

        expect(response.status).to eq 200
        expect(logged).to be_empty
        expect(capture_log { get devtools_props_path }).to include('Started GET')
      end

      it 'logs the request when silencing is off' do
        InertiaRails.configuration.devtools_silence_logs = false

        logged = capture_log { get '/_inertia/devtools/entries' }

        expect(logged).to include('EntriesController#index')
      end

      it 'returns a single entry' do
        get "/_inertia/devtools/entries/#{entries.first['id']}"

        expect(response.parsed_body['__meta']['component']).to eq 'DevtoolsComponent'
      end

      it '404s an unknown entry' do
        get "/_inertia/devtools/entries/#{InertiaRails::Devtools::Ulid.generate}"

        expect(response.status).to eq 404
      end

      # The extension asks for an entry when the response headers arrive; the
      # entry is written when the body closes.
      it 'waits for an entry whose body has not closed yet' do
        recorded = entry
        repository = instance_double(InertiaRails::Devtools::EntriesRepository)
        allow(repository).to receive(:get).and_return(nil, recorded)
        allow(InertiaRails::Devtools).to receive(:repository).and_return(repository)

        get "/_inertia/devtools/entries/#{recorded['__meta']['id']}"

        expect(response.status).to eq 200
        expect(response.parsed_body['__meta']['id']).to eq recorded['__meta']['id']
        expect(repository).to have_received(:get).twice
      end

      it 'does not record itself' do
        get '/_inertia/devtools/entries'

        expect(entries.length).to eq 1
      end
    end

    describe 'storage limits' do
      it 'keeps only the newest entries for a tab' do
        InertiaRails.configuration.devtools_limit = 2
        3.times { get devtools_props_path, headers: { 'X-Inertia-Devtools-Tab' => 'tab-1' } }

        expect(entries.length).to eq 2
      end

      it 'keeps only the newest entries that arrived without a tab' do
        InertiaRails.configuration.devtools_limit = 2
        3.times { get devtools_props_path }

        expect(entries.length).to eq 2
      end

      it 'stops touching storage after a write failure' do
        repository = InertiaRails::Devtools::EntriesRepository.new(path: File.join(storage_path, 'nested'))
        allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES)
        allow(InertiaRails::Devtools).to receive(:report)

        3.times do
          repository.record(InertiaRails::Devtools::Ulid.generate, {})
          repository.prune_if_due
        end

        expect(InertiaRails::Devtools).to have_received(:report).once
      end

      it 'caps total entries even without a tab header' do
        InertiaRails.configuration.devtools_max_entries = 2
        3.times { get devtools_props_path }

        expect(entries.length).to eq 2
      end

      it 'preserves large Inertia page and prop payloads' do
        get devtools_oversized_path
        recorded = entry

        expect(recorded['http']['responseBody']['status']).to eq 'present'
        expect(recorded.dig('http', 'responseBody', 'value', 'props', 'blob').length).to eq 300_000
        expect(recorded['propValues']['blob'].length).to eq 300_000
        expect(recorded['props']).to include('blob')
      end

      it 'prunes expired entries' do
        InertiaRails.configuration.devtools_ttl = 0.5
        InertiaRails.configuration.devtools_prune_interval = 0
        get devtools_props_path

        travel 1.hour do
          get devtools_props_path
        end

        expect(entries.length).to eq 1
      end
    end

    describe 'exceptions' do
      it 'records a request whose action raises' do
        expect { get devtools_boom_path }.to raise_error(RuntimeError, 'devtools boom')

        expect(entries.first['status']).to eq 500
        expect(entry['__meta']['error']).to eq('class' => 'RuntimeError', 'message' => 'devtools boom')
        expect(entry['http']['responseBody']).to eq('status' => 'omitted', 'reason' => 'non-inertia-response')
      end

      it 'stamps the response rendered by Rails exception handling' do
        env_config = Rails.application.env_config
        original = env_config['action_dispatch.show_exceptions']
        env_config['action_dispatch.show_exceptions'] = Rails.version < '7.1' ? true : :all

        get devtools_boom_path

        id = response.headers['X-Inertia-Devtools-Id']

        expect(response).to have_http_status(:internal_server_error)
        expect(id).to match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/)
        expect(InertiaRails::Devtools.repository.get(id).dig('__meta', 'error', 'message')).to eq 'devtools boom'
      ensure
        env_config['action_dispatch.show_exceptions'] = original
      end
    end

    it 'emits an empty route object when no Rails route handled the response' do
      app = ->(_env) { [401, { 'content-type' => 'text/plain' }, ['blocked']] }
      env = Rack::MockRequest.env_for('/blocked')
      _status, headers, body = InertiaRails::Middleware.new(app).call(env)
      body.close

      id = headers[InertiaRails::Devtools::Headers.response_keys.first]
      expect(InertiaRails::Devtools.repository.get(id)['route']).to eq(
        'name' => nil, 'uri' => '', 'action' => nil
      )
    end

    it 'rebuilds a corrupt metadata index from entry files' do
      get devtools_props_path
      id = entries.first['id']
      File.write(File.join(storage_path, '_meta.json'), '{ invalid json')

      expect(entries.map { |meta| meta['id'] }).to include(id)
      expect(JSON.parse(File.read(File.join(storage_path, '_meta.json')))).to have_key(id)
    end

    it 'rejects invalid storage entry ids' do
      repository = InertiaRails::Devtools::EntriesRepository.new(path: storage_path)

      expect { repository.record('../secret', {}) }.to raise_error(ArgumentError, /Invalid/)
    end

    it 'never breaks the response when recording fails' do
      allow(InertiaRails::Devtools::EntryBuilder).to receive(:new).and_raise('boom')
      allow(InertiaRails.host).to receive(:report_error)

      get devtools_props_path

      expect(response.status).to eq 200
      expect(InertiaRails.host).to have_received(:report_error).with(an_instance_of(RuntimeError), devtools: true)
    end
  end
end
