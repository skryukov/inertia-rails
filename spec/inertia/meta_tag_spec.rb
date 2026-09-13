# frozen_string_literal: true

# The tag's wire form and markup are specified in the core suite
# (spec/core/meta_tag_spec.rb); this is the Rails signature.
RSpec.describe InertiaRails::MetaTag do
  let(:meta_tag) { described_class.new(head_key: dummy_head_key, name: 'description', content: 'Inertia rules') }
  let(:dummy_head_key) { 'meta-12345678' }
  let(:tag_helper) { ActionController::Base.helpers.tag }

  it 'is the core tag' do
    expect(meta_tag).to be_a(Inertia::Core::MetaTag)
  end

  describe '#to_tag' do
    it 'returns an html_safe string meta tag' do
      tag = meta_tag.to_tag(tag_helper)
      expect(tag).to be_a(String)
      expect(tag).to be_html_safe
      expect(tag).to eq('<meta name="description" content="Inertia rules" inertia="meta-12345678">')
    end

    it 'defaults to a standalone tag builder when no helper is given' do
      tag = meta_tag.to_tag
      expect(tag).to eq('<meta name="description" content="Inertia rules" inertia="meta-12345678">')
    end

    context 'with an explicit inertia_attribute' do
      it 'marks the tag with the given attribute' do
        tag = meta_tag.to_tag(tag_helper, inertia_attribute: :'data-inertia')
        expect(tag).to eq('<meta name="description" content="Inertia rules" data-inertia="meta-12345678">')
      end

      context 'when the global configuration says otherwise' do
        with_inertia_config use_data_inertia_head_attribute: true

        it 'takes precedence over the global configuration' do
          tag = meta_tag.to_tag(tag_helper, inertia_attribute: :inertia)
          expect(tag).to eq('<meta name="description" content="Inertia rules" inertia="meta-12345678">')
        end
      end
    end

    context 'with use_data_inertia_head_attribute set to true' do
      with_inertia_config use_data_inertia_head_attribute: true

      it 'returns a string meta tag' do
        tag = meta_tag.to_tag(tag_helper)
        expect(tag).to be_a(String)
        expect(tag).to eq('<meta name="description" content="Inertia rules" data-inertia="meta-12345678">')
      end

      it 'renders kebab case' do
        meta_tag = described_class.new(tag_name: :meta, head_key: dummy_head_key, http_equiv: 'X-UA-Compatible',
                                       content: 'IE=edge')

        tag = meta_tag.to_tag(tag_helper)

        expect(tag).to eq('<meta http-equiv="X-UA-Compatible" content="IE=edge" data-inertia="meta-12345678">')
      end
    end

    it 'prints a string Rails marked safe as it is' do
      meta_tag = described_class.new(tag_name: :div, head_key: dummy_head_key, inner_content: '<b>bold</b>'.html_safe)

      expect(meta_tag.to_tag).to eq('<div inertia="meta-12345678"><b>bold</b></div>')
    end
  end
end

RSpec.describe InertiaRails::MetaTagBuilder do
  it 'builds Rails tags, so each answers to_tag' do
    tag = described_class.new.add(title: 'T').meta_tags.first

    expect(tag).to be_a(InertiaRails::MetaTag)
    expect(tag.to_tag).to eq('<title inertia="title">T</title>')
  end
end
