# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Inertia::Core::MetaTag do
  let(:meta_tag) { described_class.new(head_key: dummy_head_key, name: 'description', content: 'Inertia rules') }
  let(:dummy_head_key) { 'meta-12345678' }

  def html(tag)
    tag.to_html(inertia_attribute: :inertia)
  end

  describe '#to_json' do
    it 'returns the meta tag as JSON' do
      expected_json = {
        tagName: :meta,
        headKey: dummy_head_key,
        name: 'description',
        content: 'Inertia rules',
      }.to_json

      expect(meta_tag.to_json).to eq(expected_json)
    end

    it 'transforms snake_case keys to camelCase' do
      meta_tag = described_class.new(head_key: dummy_head_key, http_equiv: 'content-security-policy',
                                     content: "default-src 'self'")

      expected_json = {
        tagName: :meta,
        headKey: dummy_head_key,
        httpEquiv: 'content-security-policy',
        content: "default-src 'self'",
      }.to_json

      expect(meta_tag.to_json).to eq(expected_json)
    end

    it 'handles JSON LD content' do
      meta_tag = described_class.new(tag_name: 'script', head_key: dummy_head_key, type: 'application/ld+json',
                                     inner_content: { '@context': 'https://schema.org' })

      expected_json = {
        tagName: :script,
        headKey: dummy_head_key,
        type: 'application/ld+json',
        innerContent: { '@context': 'https://schema.org' },
      }.to_json

      expect(meta_tag.to_json).to eq(expected_json)
    end

    it 'marks executable script tags with text/plain' do
      meta_tag = described_class.new(tag_name: 'script', head_key: dummy_head_key,
                                     inner_content: '<script>alert("XSS")</script>', type: 'application/javascript')

      expected_json = {
        tagName: :script,
        headKey: dummy_head_key,
        type: 'text/plain',
        innerContent: '<script>alert("XSS")</script>',
      }.to_json

      expect(meta_tag.to_json).to eq(expected_json)
    end

    it 'drops blank attributes, false included' do
      meta_tag = described_class.new(tag_name: :script, head_key: dummy_head_key, src: '/a.js', async: false,
                                     defer: nil, crossorigin: '')

      expect(meta_tag.as_json).to eq(tagName: :script, headKey: dummy_head_key, type: 'text/plain', src: '/a.js')
    end
  end

  describe 'generated head keys' do
    it 'generates a headKey of the format {tag name}-{hexdigest of tag content}' do
      meta_tag = described_class.new(some_name: 'description', content: 'Inertia rules')
      expected_head_key = "meta-#{Digest::SHA256.hexdigest('content=Inertia rules&some_name=description')[0, 8]}"

      expect(meta_tag.as_json[:headKey]).to eq(expected_head_key)
    end

    it 'generates the same headKey regardless of hash data order' do
      first_tags = described_class.new(some_name: 'description', content: 'Inertia rules').as_json
      first_head_key = first_tags[:headKey]

      second_tags = described_class.new(content: 'Inertia rules', some_name: 'description').as_json
      second_head_key = second_tags[:headKey]

      expect(first_head_key).to eq(second_head_key)
    end

    it 'generates a different headKey for different content' do
      first_tags = described_class.new(some_name: 'thing', content: 'Inertia rules').as_json
      first_head_key = first_tags[:headKey]

      second_tags = described_class.new(some_name: 'thing', content: 'Inertia rocks').as_json
      second_head_key = second_tags[:headKey]

      expect(first_head_key).not_to eq(second_head_key)
    end

    it 'respects a user specified head_key' do
      custom_head_key = 'blah'
      meta_tag = described_class.new(head_key: custom_head_key, name: 'description', content: 'Inertia rules')

      expect(meta_tag.as_json[:headKey]).to eq(custom_head_key)
    end

    it 'generates a head key by the name attribute if no head_key is provided' do
      meta_tag = described_class.new(name: 'description', content: 'Inertia rules')

      expect(meta_tag.as_json[:headKey]).to eq('meta-name-description')
    end

    it 'generates a head key by the http_equiv attribute if no head_key is provided' do
      meta_tag = described_class.new(http_equiv: 'content-security-policy', content: "default-src 'self'")

      expect(meta_tag.as_json[:headKey]).to eq('meta-http_equiv-content-security-policy')
    end

    it 'generates a head key by the property attribute if no head_key is provided' do
      meta_tag = described_class.new(property: 'og:title', content: 'Inertia Rocks')

      expect(meta_tag.as_json[:headKey]).to eq('meta-property-og-title')
    end

    it 'slugs the attribute down to letters, digits, dashes and underscores' do
      meta_tag = described_class.new(property: 'og:Título  Largo', content: 'x')

      expect(meta_tag.as_json[:headKey]).to eq('meta-property-og-t-tulo-largo')
    end

    it 'names a charset tag after the charset' do
      expect(described_class.new(charset: 'utf-8').as_json[:headKey]).to eq('meta-charset')
    end

    context 'with allow_duplicates set to true' do
      it 'generates a head key with a unique suffix' do
        meta_tag = described_class.new(name: 'description', content: 'Inertia rules', allow_duplicates: true)
        expected_hash = Digest::SHA256.hexdigest('content=Inertia rules&name=description')[0, 8]

        expect(meta_tag.as_json[:headKey]).to eq("meta-name-description-#{expected_hash}")
      end
    end
  end

  describe '#to_html' do
    it 'renders kebab case' do
      meta_tag = described_class.new(tag_name: :meta, head_key: dummy_head_key, http_equiv: 'X-UA-Compatible',
                                     content: 'IE=edge')

      expect(html(meta_tag)).to eq('<meta http-equiv="X-UA-Compatible" content="IE=edge" inertia="meta-12345678">')
    end

    it 'marks the tag with the attribute it is given' do
      expect(meta_tag.to_html(inertia_attribute: 'data-inertia'))
        .to eq('<meta name="description" content="Inertia rules" data-inertia="meta-12345678">')
    end

    it 'escapes attribute values' do
      meta_tag = described_class.new(head_key: dummy_head_key, name: 'description', content: %(a "quoted" <b> & c))

      expect(html(meta_tag))
        .to eq('<meta name="description" content="a &quot;quoted&quot; &lt;b&gt; &amp; c" inertia="meta-12345678">')
    end

    it 'prints a boolean attribute bare and leaves false and nil out' do
      meta_tag = described_class.new(tag_name: :script, head_key: dummy_head_key, src: '/a.js', async: true,
                                     defer: false, nonce: nil)

      expect(html(meta_tag)).to eq('<script src="/a.js" async type="text/plain" inertia="meta-12345678"></script>')
    end

    it 'joins an array attribute with spaces' do
      meta_tag = described_class.new(tag_name: :link, head_key: dummy_head_key, rel: %w[preload modulepreload],
                                     href: '/a.js')

      expect(html(meta_tag)).to eq('<link rel="preload modulepreload" href="/a.js" inertia="meta-12345678">')
    end

    describe 'script tag rendering' do
      it 'renders JSON LD content correctly' do
        meta_tag = described_class.new(tag_name: :script, head_key: dummy_head_key, type: 'application/ld+json',
                                       inner_content: { '@context': 'https://schema.org' })

        expect(html(meta_tag)).to eq(
          '<script type="application/ld+json" inertia="meta-12345678">{"@context":"https://schema.org"}</script>'
        )
      end

      it 'escapes the JSON so it cannot close the element' do
        meta_tag = described_class.new(tag_name: :script, head_key: dummy_head_key, type: 'application/ld+json',
                                       inner_content: { name: '</script><b>&' })

        expect(html(meta_tag)).to include('{"name":"\u003c/script\u003e\u003cb\u003e\u0026"}')
      end

      it 'adds text/plain and escapes all other script tags' do
        meta_tag = described_class.new(tag_name: :script, head_key: dummy_head_key, type: 'application/javascript',
                                       inner_content: 'alert("XSS")')

        expect(html(meta_tag))
          .to eq('<script type="text/plain" inertia="meta-12345678">alert(&quot;XSS&quot;)</script>')
      end
    end

    describe 'rendering unary tags' do
      described_class::UNARY_TAGS.each do |tag_name|
        it "renders a content attribute for a #{tag_name} tag" do
          meta_tag = described_class.new(tag_name: tag_name, head_key: dummy_head_key, content: 'Inertia rules')

          expect(html(meta_tag)).to include("<#{tag_name} content=\"Inertia rules\" inertia=\"meta-12345678\">")
        end
      end
    end

    it 'escapes inner content for non-script tags' do
      meta_tag = described_class.new(tag_name: :div, head_key: dummy_head_key,
                                     inner_content: '<script>alert("XSS")</script>')

      expect(html(meta_tag))
        .to eq('<div inertia="meta-12345678">&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;</div>')
    end

    it 'prints a string a framework marked safe as it is' do
      safe = Class.new(String) { def html_safe? = true }.new('<b>bold</b>')
      meta_tag = described_class.new(tag_name: :div, head_key: dummy_head_key, inner_content: safe)

      expect(html(meta_tag)).to eq('<div inertia="meta-12345678"><b>bold</b></div>')
    end
  end

  describe 'title tag rendering' do
    it 'renders a title tag if only a title key is provided' do
      meta_tag = described_class.new(tag_name: :title, head_key: dummy_head_key, inner_content: 'Inertia Page Title')

      expect(html(meta_tag)).to eq('<title inertia="title">Inertia Page Title</title>')
    end

    context 'when only a title key is provided' do
      let(:title_tag) { described_class.new(title: 'Inertia Is Great', head_key: 'title') }

      it 'renders JSON correctly' do
        expect(title_tag.to_json).to eq({
          tagName: :title,
          headKey: 'title',
          innerContent: 'Inertia Is Great',
        }.to_json)
      end

      it 'renders a title tag' do
        expect(html(title_tag)).to eq('<title inertia="title">Inertia Is Great</title>')
      end
    end
  end
end

RSpec.describe Inertia::Core::MetaTagBuilder do
  subject(:head) { described_class.new }

  it 'keeps one tag per head key, the latest winning, and one title' do
    head.add(title: 'First').add([{ name: 'description', content: 'a' }, { title: 'Second' }])
    head.add(name: 'description', content: 'b')

    expect(head.title).to eq 'Second'
    expect(head.meta_tags.map { |tag| [tag[:head_key], tag[:inner_content] || tag[:content]] })
      .to eq [%w[title Second], %w[meta-name-description b]]
  end

  it 'removes by head key or by block, and clears' do
    head.add([{ title: 'T' }, { name: 'a', content: '1' }, { name: 'b', content: '2' }])

    expect(head.remove('title').meta_tags.map { |tag| tag[:head_key] }).to eq %w[meta-name-a meta-name-b]
    expect(head.remove { |tag| tag[:name] == 'a' }.meta_tags.map { |tag| tag[:head_key] }).to eq %w[meta-name-b]
    expect(head.clear.meta_tags).to be_empty
    expect { head.remove }.to raise_error(ArgumentError, /either head_key or a block/)
    expect { head.remove('x') { true } }.to raise_error(ArgumentError, /both/)
    expect { head.add('title') }.to raise_error(ArgumentError, /Hash or Array/)
  end

  it 'builds tags of the class it is given' do
    tag_class = Class.new(Inertia::Core::MetaTag)

    expect(described_class.new(tag_class: tag_class).add(title: 'T').meta_tags.first).to be_a(tag_class)
  end
end
