# frozen_string_literal: true

class InertiaDevtoolsTestController < ApplicationController
  inertia_share app_name: 'Dummy'

  def props
    render inertia: 'DevtoolsComponent', props: {
      name: 'Brandon',
      password: 'hunter2',
      ssn: '123-45-6789',
      always: InertiaRails.always { 'always param' },
      optional: InertiaRails.optional { 'optional param' },
      deferred: InertiaRails.defer(group: 'stats') { 'deferred param' },
      items: InertiaRails.merge { [1, 2] },
      prepended: InertiaRails.merge(prepend: true) { [0] },
      matched: InertiaRails.merge(match_on: 'id') { [{ id: 1 }] },
      deep: InertiaRails.deep_merge { { count: 1 } },
      settings: InertiaRails.once { 'once param' },
      users: InertiaRails.scroll(pagy) { [{ id: 1, name: 'User 1' }] },
      nested: { first: 'first nested param' },
      secrets: { token: InertiaRails.always { 'nested secret' } },
    }
  end

  def rescued
    render inertia: 'DevtoolsComponent', props: {
      name: 'Brandon',
      permissions: InertiaRails.defer(rescue: true) { raise 'boom' },
    }
  end

  def oversized
    render inertia: 'DevtoolsComponent', props: { blob: 'x' * 300_000 }
  end

  def plain
    render json: { ok: true, token: 'secret-value' }
  end

  def cached
    fresh_when(etag: 'devtools-stable', public: false)
    return if performed?

    render inertia: 'DevtoolsComponent', props: { name: 'Brandon' }
  end

  def create
    redirect_to devtools_props_path(token: 'leaked')
  end

  def boom
    raise 'devtools boom'
  end

  private

  def pagy
    (defined?(Pagy::Offset) ? Pagy::Offset : Pagy).new(next: 2, page: 1, count: 100)
  end
end
