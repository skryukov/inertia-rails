# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Inertia::Core::Devtools::EntriesRepository do
  around do |example|
    Dir.mktmpdir('inertia-devtools') do |path|
      @path = path
      example.run
    end
  end

  # An entry as it is stored: the index is built from `__meta` alone.
  def record(repository, tab_uuid: nil, utime: Time.now.to_f, **limits)
    id = Inertia::Core::Devtools::Ulid.generate
    repository.record(id, { '__meta' => { 'id' => id, 'tabUuid' => tab_uuid, 'utime' => utime } },
                      tab_uuid: tab_uuid, **limits)
    id
  end

  subject(:repository) { described_class.new(path: @path, host: host) }

  let(:host) { TestHost.new }

  it 'stores an entry under its id and lists the index newest first' do
    ids = Array.new(3) { record(repository) }

    expect(repository.get(ids.last)['__meta']).to include('id' => ids.last)
    expect(repository.all.map { |meta| meta['id'] }).to eq ids.reverse
    expect(File.stat(@path).mode & 0o777).to eq 0o700
  end

  it 'refuses an id that is not a ULID, so nothing can be written outside the directory' do
    expect { repository.record('../secret', {}) }.to raise_error(ArgumentError, /Invalid/)
    expect(repository.get('../secret')).to be_nil
  end

  it 'keeps only the newest entries of a tab, and of the tab-less ones' do
    kept = Array.new(2) { record(repository, tab_uuid: 'tab-1', limit: 2) }.last
    other = record(repository, tab_uuid: 'tab-2', limit: 2)
    record(repository, tab_uuid: 'tab-1', limit: 2)

    expect(repository.all.map { |meta| meta['id'] }).to include(kept, other)
    expect(repository.all.length).to eq 3
    expect(Dir.glob(File.join(@path, '*.json')).length).to eq 4 # the three entries and the index
  end

  it 'caps the entries of every tab together' do
    3.times { record(repository, max_entries: 2) }

    expect(repository.all.length).to eq 2
  end

  it 'prunes what outlived the TTL' do
    repository = described_class.new(path: @path, ttl_hours: 1, prune_interval: 0, host: host)
    stale = record(repository, utime: Time.now.to_f - 7200)
    fresh = record(repository)

    repository.prune_if_due

    expect(repository.all.map { |meta| meta['id'] }).to eq [fresh]
    expect(repository.get(stale)).to be_nil
  end

  it 'waits out the prune interval before scanning again' do
    repository = described_class.new(path: @path, ttl_hours: 0, prune_interval: 3600, host: host)
    id = record(repository)

    repository.prune_if_due
    expect(repository.all).to be_empty

    other = record(repository)
    repository.prune_if_due
    expect(repository.all.map { |meta| meta['id'] }).to eq [other]
    expect(repository.get(id)).to be_nil
  end

  it 'rebuilds a corrupt index from the entry files it still has' do
    id = record(repository)
    File.write(File.join(@path, '_meta.json'), '{ invalid json')

    expect(repository.all.map { |meta| meta['id'] }).to eq [id]
    expect(JSON.parse(File.read(File.join(@path, '_meta.json')))).to have_key(id)
  end

  it 'reports a write failure once and stops touching storage for a while' do
    repository = described_class.new(path: File.join(@path, 'nested'), host: host)
    allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES)

    3.times do
      repository.record(Inertia::Core::Devtools::Ulid.generate, {})
      repository.prune_if_due
    end

    expect(host.reported.length).to eq 1
    expect(host.reported.first).to match([an_instance_of(Errno::EACCES), { devtools: true }])
  end
end

RSpec.describe Inertia::Core::Devtools::Ulid do
  it 'sorts by the time it was generated, and never repeats within a millisecond' do
    ids = Array.new(50) { described_class.generate(Time.at(1_700_000_000)) }

    expect(ids.uniq.length).to eq 50
    expect(ids).to eq ids.sort
  end

  it 'keeps later ids sorting after earlier ones' do
    early = described_class.generate(Time.at(1_700_000_000))
    late = described_class.generate(Time.at(1_700_000_001))

    expect(late).to be > early
  end

  it 'is 26 Crockford characters, and validates as one' do
    id = described_class.generate

    expect(id).to match(/\A[0-7][0-9A-HJKMNP-TV-Z]{25}\z/)
    expect(described_class.valid?(id)).to be true
    expect(described_class.valid?('../secret')).to be false
    expect(described_class.valid?(nil)).to be false
  end
end
