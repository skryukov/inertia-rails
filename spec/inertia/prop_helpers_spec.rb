# frozen_string_literal: true

require 'rails_helper'

# The Rails spelling of the prop presets. What each prop then does is the core
# suite's business; this pins only that the helper builds the right core class
# and forwards its options.
RSpec.describe InertiaRails, 'prop helpers' do
  it 'builds the core prop each preset names' do
    expect(described_class.optional { 1 }).to be_an_instance_of(Inertia::Core::OptionalProp)
    expect(described_class.always { 1 }).to be_an_instance_of(Inertia::Core::AlwaysProp)
    expect(described_class.once { 1 }).to be_an_instance_of(Inertia::Core::OnceProp)
    expect(described_class.merge { 1 }).to be_an_instance_of(Inertia::Core::MergeProp)
    expect(described_class.defer { 1 }).to be_an_instance_of(Inertia::Core::DeferProp)
    expect(described_class.cache('k') { 1 }).to be_an_instance_of(Inertia::Core::CachedProp)
    expect(described_class.lazy(1)).to be_an_instance_of(InertiaRails::LazyProp)
  end

  it 'forwards the options each helper shapes' do
    page = { page_name: 'page', previous_page: nil, next_page: 2, current_page: 1 }

    expect(announced(described_class.deep_merge(match_on: 'id') { [] }))
      .to include(deepMergeProps: ['key'], matchPropsOn: ['key.id'])
    expect(announced(described_class.scroll(page, wrapper: 'data') { [] })[:scrollProps])
      .to eq('key' => { pageName: 'page', previousPage: nil, nextPage: 2, currentPage: 1, reset: false })
    expect(announced(described_class.defer(group: 'sidebar') { 1 }))
      .to include(deferredProps: { 'sidebar' => ['key'] })
  end
end
