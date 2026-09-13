# frozen_string_literal: true

# `ScrollProp` is covered in the core suite
# (`gems/inertia-core/spec/scroll_prop_spec.rb`). What stays here is the prop
# fed a real paginator, which only the adapter gems can build.
RSpec.describe InertiaRails::ScrollProp do
  # What the client receives in scrollProps, minus the per-request reset flag.
  def scroll_metadata(prop)
    metadata = announced(prop, path: 'items', visit: { partial: true, only: ['items'] })
    metadata[:scrollProps].fetch('items').except(:reset)
  end

  it 'resolves metadata from Pagy paginator' do
    collection = Array.new(100) { |i| "item#{i}" }
    pagy, = (defined?(Pagy::Offset) ? Pagy::Offset : Pagy).new(
      count: collection.size, page: 1, items: 20
    )

    prop = described_class.new(metadata: pagy) { collection }
    metadata = scroll_metadata(prop)

    expect(metadata).to eq(
      pageName: 'page',
      previousPage: nil,
      nextPage: 2,
      currentPage: 1
    )
  end

  it 'resolves metadata from Kaminari paginator' do
    collection = Array.new(100) { |i| "item#{i}" }
    collection = Kaminari.paginate_array(collection).page(1).per(20)

    prop = described_class.new(metadata: collection) { collection }
    metadata = scroll_metadata(prop)

    another_prop = described_class.new(metadata: collection, page_name: 'another_pagination') { collection }
    another_metadata = scroll_metadata(another_prop)

    expect(metadata).to eq(
      pageName: 'page',
      previousPage: nil,
      nextPage: 2,
      currentPage: 1
    )
    expect(another_metadata).to eq(
      pageName: 'another_pagination',
      previousPage: nil,
      nextPage: 2,
      currentPage: 1
    )
  end
end
