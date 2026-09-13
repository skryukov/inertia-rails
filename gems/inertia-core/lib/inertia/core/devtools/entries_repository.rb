# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'

module Inertia
  module Core
    module Devtools
      # Entry storage shared across processes: one JSON file per entry and an
      # index of their `__meta`, so listing does not read every entry. Pruned
      # by TTL, capped per tab and overall. A disk that fails is reported once
      # and left alone for a while instead of retried on every request.
      class EntriesRepository
        INDEX_FILE = '_meta.json'
        LOCK_FILE = '_meta.lock'
        LAST_PRUNE_FILE = '_last_prune'
        SUPPRESS_SECONDS = 30

        def initialize(path:, ttl_hours: 24, prune_interval: 300, host: Host.new)
          @path = path
          @ttl_hours = ttl_hours
          @prune_interval = prune_interval
          @host = host
          @suppressed_until = nil
        end

        def get(id)
          read_json(entry_path(id)) if Ulid.valid?(id)
        end

        # Newest first: ids sort by time.
        def all
          index = read_index || update_index { [] }
          index.values.sort_by { |meta| meta['id'] }.reverse
        end

        def record(id, data, tab_uuid: nil, limit: 100, max_entries: 0)
          raise ArgumentError, 'Invalid Inertia DevTools entry id.' unless Ulid.valid?(id)

          guarded do
            ensure_directory
            write(entry_path(id), JSON.generate(data))
            update_index do |index|
              index[id] = index_meta(data['__meta'] || data[:__meta] || {})
              overflow(index, tab_uuid, limit, max_entries)
            end
          end
        end

        def prune_if_due
          guarded do
            next prune if @prune_interval <= 0

            ensure_directory
            last = read_last_pruned_at
            next if last && Time.now.to_i - last < @prune_interval

            prune
            write(File.join(@path, LAST_PRUNE_FILE), Time.now.to_i.to_s)
          end
        end

        protected

        # Where a failure goes; a host routes it into its own reporting.
        def report(error)
          @host.report_error(error, devtools: true)
        end

        private

        def prune
          cutoff = Time.now.to_f - (@ttl_hours * 3600)
          update_index { |index| index.select { |_id, meta| meta['utime'] < cutoff }.keys }
        end

        # Newest kept, per tab first (no tab is a tab of its own), then overall.
        def overflow(index, tab_uuid, limit, max_entries)
          newest = index.values.sort_by { |meta| meta['id'] }.reverse
          dropped = []
          if limit.positive?
            dropped |= newest.select { |meta| meta['tabUuid'] == tab_uuid }.drop(limit).map { |meta| meta['id'] }
          end
          dropped |= newest.drop(max_entries).map { |meta| meta['id'] } if max_entries.positive?
          dropped
        end

        def guarded
          return if suppressed?

          yield
          @suppressed_until = nil
        rescue StandardError => e
          report(e) if @suppressed_until.nil?
          @suppressed_until = monotonic + SUPPRESS_SECONDS
        end

        def suppressed?
          @suppressed_until && monotonic < @suppressed_until
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        # Under the lock: the block gets the index (rebuilt from the entry
        # files when the file is missing or corrupt) and answers the ids to
        # drop. Their files go once the index no longer lists them.
        def update_index
          ensure_directory

          File.open(File.join(@path, LOCK_FILE), File::WRONLY | File::CREAT, 0o600) do |lock|
            lock.flock(File::LOCK_EX)

            index = read_index || meta_from_files
            dropped = yield(index)
            index = index.except(*dropped)
            write(index_path, JSON.generate(index))
            dropped.each { |id| FileUtils.rm_f(entry_path(id)) }
            index
          end
        end

        def read_index
          index = read_json(index_path)
          index&.each_with_object({}) { |(id, meta), result| result[id] = index_meta(meta) if meta.is_a?(Hash) }
        end

        def meta_from_files
          Dir.glob(File.join(@path, '*.json')).each_with_object({}) do |file, index|
            next if File.basename(file) == INDEX_FILE

            meta = read_json(file)&.[]('__meta')
            index[meta['id']] = index_meta(meta) if meta.is_a?(Hash) && meta['id']
          end
        end

        def index_meta(meta)
          meta = meta.transform_keys(&:to_s)
          tab = meta['tabUuid']

          meta.merge(
            'id' => meta['id'].to_s,
            'tabUuid' => tab.is_a?(String) && !tab.empty? ? tab : nil,
            'utime' => meta['utime'] ? meta['utime'].to_f : Time.now.to_f
          )
        end

        def read_json(path)
          parsed = JSON.parse(File.read(path))
          parsed if parsed.is_a?(Hash)
        rescue SystemCallError, JSON::ParserError
          nil
        end

        def read_last_pruned_at
          Integer(File.read(File.join(@path, LAST_PRUNE_FILE)), exception: false)
        rescue SystemCallError
          nil
        end

        # Published by rename: a reader sees the old file or the whole new one.
        def write(path, contents)
          temp = Tempfile.new(File.basename(path), File.dirname(path))
          temp.binmode
          temp.write(contents)
          temp.close
          File.chmod(0o600, temp.path)
          File.rename(temp.path, path)
        ensure
          temp&.close!
        end

        def ensure_directory
          FileUtils.mkdir_p(@path, mode: 0o700)
          gitignore = File.join(@path, '.gitignore')
          File.write(gitignore, "*\n") unless File.exist?(gitignore)
        end

        def entry_path(id)
          File.join(@path, "#{id}.json")
        end

        def index_path
          File.join(@path, INDEX_FILE)
        end
      end
    end
  end
end
