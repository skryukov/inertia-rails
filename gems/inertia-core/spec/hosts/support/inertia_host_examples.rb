# frozen_string_literal: true

require 'rack/test'

# What a host owes the client, asserted against the Rack app the framework under
# test builds. Every app in spec/hosts renders the same `Dashboard` page from the
# same props, so one set of expectations answers for all of them.
RSpec.shared_examples 'an Inertia host' do
  include Rack::Test::Methods

  def inertia_get(path, headers = {})
    get(path, {}, { 'HTTP_X_INERTIA' => 'true', 'HTTP_X_INERTIA_VERSION' => 'v1' }.merge(headers))
  end

  def page
    JSON.parse(last_response.body)
  end

  def embedded_page
    JSON.parse(last_response.body[%r{<script data-page="app" type="application/json">(.*?)</script>}m, 1])
  end

  it 'embeds the page in a script element on a first load' do
    get '/dashboard'

    expect(last_response.status).to eq 200
    expect(last_response['Content-Type']).to start_with 'text/html'
    expect(last_response['Vary']).to eq 'X-Inertia'
    expect(last_response.body).to include '<div id="app"></div>'
    expect(embedded_page).to include('component' => 'Dashboard', 'url' => '/dashboard', 'version' => 'v1')
    # A raw `</` inside the JSON would end the element early. Whichever encoder
    # the process loaded escapes it — `<\/script>` from the json gem, and
    # `</script>` once ActiveSupport is in — and it survives the trip.
    expect(last_response.body).not_to include '</script> tags'
    expect(embedded_page['props']['user']).to eq('name' => 'Ada', 'bio' => 'writes </script> tags')
  end

  it 'answers an X-Inertia request with the page as JSON' do
    inertia_get '/dashboard'

    expect(last_response.status).to eq 200
    expect(last_response['X-Inertia']).to eq 'true'
    expect(last_response['Content-Type']).to start_with 'application/json'
    expect(last_response['Vary']).to eq 'X-Inertia'

    expect(page['props'].keys).to contain_exactly('user', 'notifications', 'settings', 'feed', 'clock', 'menu')
    expect(page['props']).to include('user' => { 'name' => 'Ada', 'bio' => 'writes </script> tags' },
                                     'notifications' => 2,
                                     'menu' => %w[Home Billing])
    expect(page['deferredProps']).to eq('metrics' => ['stats'])
    expect(page['mergeProps']).to eq ['feed']
    expect(page['onceProps']).to eq('settings' => { 'prop' => 'settings' })
    expect(page['liveProps']).to eq(
      'clock' => { 'listeners' => [{ 'channel' => { 'name' => 'clock', 'type' => 'public' }, 'events' => ['tick'] }] }
    )
  end

  it 'answers a partial reload with the props it named, plus the always props' do
    inertia_get '/dashboard', 'HTTP_X_INERTIA_PARTIAL_COMPONENT' => 'Dashboard',
                              'HTTP_X_INERTIA_PARTIAL_DATA' => 'stats'

    expect(page['props'].keys).to contain_exactly('stats', 'notifications')
    expect(page['props']['stats']).to eq('visits' => 42)
    # The reload is the fetch the announcement asked for.
    expect(page).not_to have_key 'deferredProps'

    inertia_get '/dashboard', 'HTTP_X_INERTIA_PARTIAL_COMPONENT' => 'Dashboard',
                              'HTTP_X_INERTIA_PARTIAL_EXCEPT' => 'user'

    expect(page['props'].keys).to contain_exactly('notifications', 'stats', 'settings', 'feed', 'clock', 'menu')
  end

  it 'turns a stale version into a location response' do
    inertia_get '/dashboard', 'HTTP_X_INERTIA_VERSION' => 'stale'

    expect(last_response.status).to eq 409
    expect(last_response['X-Inertia-Location']).to eq 'http://example.org/dashboard'
    expect(last_response['X-Inertia-Version']).to eq 'v1'
    expect(last_response.body).to be_empty
  end

  it 'turns an external redirect into a location response, keeping the cookie' do
    inertia_get '/billing'

    expect(last_response.status).to eq 409
    expect(last_response['X-Inertia-Location']).to eq 'https://billing.test/checkout'
    expect(last_response['Location']).to be_nil
    expect(Array(last_response['Set-Cookie']).join("\n")).to include 'checkout=started'
  end

  it 'rewrites a redirect after a PUT to 303' do
    put '/dashboard'

    expect(last_response.status).to eq 302

    put '/dashboard', {}, 'HTTP_X_INERTIA' => 'true', 'HTTP_X_INERTIA_VERSION' => 'v1'

    expect(last_response.status).to eq 303
    expect(last_response['Location']).to end_with '/dashboard'
  end
end
