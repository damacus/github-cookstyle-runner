# frozen_string_literal: true

require 'spec_helper'
require 'timecop'
require 'fileutils'
require 'json'

RSpec.describe CookstyleRunner::Cache do
  let(:cache_dir) { File.join(Dir.tmpdir, 'cookstyle-runner-test', 'cache') }
  let(:cache_file) { File.join(cache_dir, 'cache.json') }
  let(:logger) { instance_double(Logger, debug: nil, info: nil, warn: nil, error: nil) }
  let(:repo_name) { 'test/repo' }
  let(:commit_sha) { '0123456789abcdef0123456789abcdef01234567' }
  let(:cache) { described_class.new(cache_dir, logger) }

  before do
    # Clear and recreate cache directory before each test
    FileUtils.rm_rf(cache_dir)
    FileUtils.mkdir_p(cache_dir)
  end

  after do
    # Clean up cache directory after all tests
    FileUtils.rm_rf(cache_dir)
  end

  describe '#initialize' do
    it 'creates cache directory if it does not exist' do
      FileUtils.rm_rf(cache_dir)
      expect(Dir.exist?(cache_dir)).to be false
      described_class.new(cache_dir, logger)
      expect(Dir.exist?(cache_dir)).to be true
    end

    it 'loads cache from disk if it exists' do
      # Create a dummy cache file
      FileUtils.mkdir_p(cache_dir)
      File.write(cache_file, JSON.generate({
                                             'repositories' => {
                                               repo_name => {
                                                 'commit_sha' => commit_sha,
                                                 'had_issues' => true,
                                                 'result' => '{"example": "result"}',
                                                 'processing_time' => 2.5,
                                                 'timestamp' => Time.now.utc.iso8601
                                               }
                                             },
                                             'last_updated' => Time.now.utc.iso8601
                                           }))

      # Initialize cache and check that it loaded existing data
      cache = described_class.new(cache_dir, logger)
      expect(cache.data['repositories']).to have_key(repo_name)
    end

    it 'initializes a new cache if no cache file exists' do
      FileUtils.rm_rf(cache_dir)
      FileUtils.mkdir_p(cache_dir)

      # Initialize cache with no existing file
      cache = described_class.new(cache_dir, logger)
      expect(cache.data).to include('repositories', 'last_updated')
      expect(cache.data['repositories']).to be_empty
    end
  end

  describe '#load_cache' do
    it 'parses and loads an existing cache file' do
      # Create a dummy cache file
      cache_data = {
        'repositories' => {
          repo_name => {
            'commit_sha' => commit_sha,
            'had_issues' => true,
            'result' => '{"example": "result"}',
            'processing_time' => 2.5,
            'timestamp' => Time.now.utc.iso8601
          }
        },
        'last_updated' => Time.now.utc.iso8601
      }
      File.write(cache_file, JSON.generate(cache_data))

      # Load the cache and verify
      result = cache.load_cache
      expect(result).to eq(cache_data)
      expect(cache.data).to eq(cache_data)
    end

    it 'initializes a new cache if the cache file is invalid JSON' do
      # Write invalid JSON to the cache file
      File.write(cache_file, 'This is not valid JSON')

      # Load the cache and verify it creates a new one
      result = cache.load_cache
      expect(result).to include('repositories', 'last_updated')
      expect(result['repositories']).to be_empty
    end

    it 'initializes a new cache if the file does not exist' do
      FileUtils.rm_f(cache_file)

      # Load the cache and verify
      result = cache.load_cache
      expect(result).to include('repositories', 'last_updated')
      expect(result['repositories']).to be_empty
    end
  end

  describe '#save' do
    it 'writes the cache to disk' do
      # Update cache data and save
      cache.data['repositories'][repo_name] = {
        'commit_sha' => commit_sha,
        'had_issues' => true,
        'result' => '{"example": "result"}',
        'processing_time' => 2.5,
        'timestamp' => Time.now.utc.iso8601
      }
      cache.save

      # Verify file was written
      expect(File.exist?(cache_file)).to be true

      # Verify file contents
      saved_data = JSON.parse(File.read(cache_file))
      expect(saved_data['repositories']).to have_key(repo_name)
    end

    it 'updates the last_updated timestamp' do
      freeze_time = Time.parse('2023-01-01T12:00:00Z')
      Timecop.freeze(freeze_time) do
        cache.save
        saved_data = JSON.parse(File.read(cache_file))
        expect(saved_data['last_updated']).to eq(freeze_time.utc.iso8601)
      end
    end

    it 'initializes data structure if it is empty' do
      cache.instance_variable_set(:@data, {})
      cache.save
      saved_data = JSON.parse(File.read(cache_file))
      expect(saved_data).to include('repositories', 'last_updated')
    end
  end

  describe '#up_to_date?' do
    let(:repo_data) do
      {
        'commit_sha' => commit_sha,
        'had_issues' => true,
        'result' => '{"example": "result"}',
        'processing_time' => 2.5,
        'timestamp' => Time.now.utc.iso8601
      }
    end

    before do
      # Setup cache with a repository entry
      cache.data['repositories'][repo_name] = repo_data
    end

    it 'returns true when repo entry exists, SHA matches, and is not expired' do
      # Should be up to date
      expect(cache.up_to_date?(repo_name, commit_sha)).to be true
    end

    it 'returns false when repo entry does not exist' do
      # Should not be up to date for non-existent repo
      expect(cache.up_to_date?('nonexistent/repo', commit_sha)).to be false
    end

    it 'returns false when SHA does not match' do
      # Should not be up to date for different SHA
      expect(cache.up_to_date?(repo_name, 'different_sha')).to be false
    end

    it 'returns false when entry is expired' do
      # Set entry timestamp to 8 days ago (default max age is 7 days)
      eight_days_ago = Time.now.utc - (8 * 24 * 60 * 60)
      cache.data['repositories'][repo_name]['timestamp'] = eight_days_ago.iso8601

      # Should not be up to date due to expiration
      expect(cache.up_to_date?(repo_name, commit_sha)).to be false
    end

    it 'respects custom max_age option' do
      # Set entry timestamp to 2 days ago
      two_days_ago = Time.now.utc - (2 * 24 * 60 * 60)
      cache.data['repositories'][repo_name]['timestamp'] = two_days_ago.iso8601

      # Should be up to date with 3-day max age
      expect(cache.up_to_date?(repo_name, commit_sha, max_age: 3 * 24 * 60 * 60)).to be true

      # Should not be up to date with 1-day max age
      expect(cache.up_to_date?(repo_name, commit_sha, max_age: 1 * 24 * 60 * 60)).to be false
    end

    it 'increments the stats hit counter when up to date' do
      expect(cache.stats).to receive(:record_hit).with(2.5).and_return(2.5)
      cache.up_to_date?(repo_name, commit_sha)
    end
  end

  describe '#get_result' do
    let(:repo_data) do
      {
        'commit_sha' => commit_sha,
        'had_issues' => true,
        'result' => '{"example": "result"}',
        'processing_time' => 2.5,
        'timestamp' => Time.now.utc.iso8601
      }
    end

    it 'returns nil when repo entry does not exist' do
      expect(cache.get_result('nonexistent/repo')).to be_nil
    end

    it 'returns the cache entry hash when repo entry exists' do
      cache.data['repositories'][repo_name] = repo_data
      result = cache.get_result(repo_name)
      expect(result).to be_a(Hash)
      expect(result['commit_sha']).to eq(commit_sha)
    end
  end

  describe '#update' do
    it 'adds a new repository entry to the cache' do
      # Verify repo doesn't exist initially
      expect(cache.data['repositories']).not_to have_key(repo_name)

      # Update cache
      cache.update(repo_name, commit_sha, true, '{"example": "result"}', 2.5)

      # Verify repo exists now
      expect(cache.data['repositories']).to have_key(repo_name)
      expect(cache.data['repositories'][repo_name]['commit_sha']).to eq(commit_sha)
      expect(cache.data['repositories'][repo_name]['had_issues']).to be true
    end

    it 'updates an existing repository entry' do
      # Add initial entry
      cache.update(repo_name, commit_sha, true, '{"example": "result"}', 2.5)

      # Update with new data
      new_sha = 'new_sha'
      cache.update(repo_name, new_sha, false, '{"new": "result"}', 1.5)

      # Verify data updated
      expect(cache.data['repositories'][repo_name]['commit_sha']).to eq(new_sha)
      expect(cache.data['repositories'][repo_name]['had_issues']).to be false
    end

    it 'updates stats and saves the cache' do
      expect(cache.stats).to receive(:record_update)
      expect(cache.stats).to receive(:record_miss)
      expect(cache).to receive(:save)

      cache.update(repo_name, commit_sha, true, '{"example": "result"}', 2.5)
    end
  end

  describe '#clear_repo' do
    it 'removes a repository from the cache' do
      # Add repo to cache
      cache.data['repositories'][repo_name] = {
        'commit_sha' => commit_sha,
        'had_issues' => true,
        'result' => '{"example": "result"}',
        'processing_time' => 2.5,
        'timestamp' => Time.now.utc.iso8601
      }

      # Verify repo exists
      expect(cache.data['repositories']).to have_key(repo_name)

      # Clear repo
      cache.clear_repo(repo_name)

      # Verify repo no longer exists
      expect(cache.data['repositories']).not_to have_key(repo_name)
    end

    it 'saves the cache after removing the repository' do
      cache.data['repositories'][repo_name] = {
        'commit_sha' => commit_sha,
        'had_issues' => true,
        'result' => '{"example": "result"}',
        'processing_time' => 2.5,
        'timestamp' => Time.now.utc.iso8601
      }

      expect(cache).to receive(:save)
      cache.clear_repo(repo_name)
    end
  end

  describe '#clear_all' do
    it 'clears all repository entries from the cache' do
      # Add multiple repos to cache
      cache.data['repositories'][repo_name] = { 'commit_sha' => commit_sha }
      cache.data['repositories']['another/repo'] = { 'commit_sha' => 'another_sha' }

      # Verify repos exist
      expect(cache.data['repositories'].keys.size).to eq(2)

      # Clear all
      cache.clear_all

      # Verify repos no longer exist
      expect(cache.data['repositories']).to be_empty
    end

    it 'initializes a new cache and saves it' do
      # NOTE: initialize_cache itself calls save, so we don't need to check for that separately
      expect(cache).to receive(:initialize_cache).and_call_original
      cache.clear_all
    end
  end

  describe '#cache_stats' do
    it 'returns cache statistics from the stats object' do
      # Add some test data
      cache.data['repositories'][repo_name] = {
        'commit_sha' => commit_sha,
        'had_issues' => true,
        'result' => '{"example": "result"}',
        'processing_time' => 2.5,
        'timestamp' => Time.now.utc.iso8601
      }

      stats = cache.cache_stats
      expect(stats).to be_a(Hash)
      expect(stats).to include('total_repositories', 'repositories_with_issues', 'last_updated')
      expect(stats['total_repositories']).to eq(1)
      expect(stats['repositories_with_issues']).to eq(1)
    end
  end

  describe '#runtime_stats' do
    it 'returns runtime statistics from the stats object' do
      # Record some stats
      cache.stats.record_hit(2.5)
      cache.stats.record_miss

      stats = cache.runtime_stats
      expect(stats).to be_a(Hash)
      expect(stats).to include('cache_hits', 'cache_misses', 'cache_updates', 'cache_hit_rate', 'runtime')
      expect(stats['cache_hits']).to eq(1)
      expect(stats['cache_misses']).to eq(1)
    end
  end

  describe '#average_processing_time' do
    it 'returns the average processing time from all repository entries' do
      # Add multiple repos with different processing times
      cache.data['repositories']['repo1'] = {
        'commit_sha' => commit_sha,
        'had_issues' => true,
        'result' => '{"example": "result"}',
        'processing_time' => 2.0,
        'timestamp' => Time.now.utc.iso8601
      }

      cache.data['repositories']['repo2'] = {
        'commit_sha' => commit_sha,
        'had_issues' => true,
        'result' => '{"example": "result"}',
        'processing_time' => 4.0,
        'timestamp' => Time.now.utc.iso8601
      }

      # Expected average: (2.0 + 4.0) / 2 = 3.0
      expect(cache.average_processing_time).to eq(3.0)
    end

    it 'returns 5.0 when there are no repositories' do
      cache.data['repositories'] = {}
      expect(cache.average_processing_time).to eq(5.0)
    end
  end
end
