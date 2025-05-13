# frozen_string_literal: true
# typed: true

require 'json'
require 'fileutils'
require 'time'
require_relative 'cache_stats'
require_relative 'cache_entry'
require 'sorbet-runtime'

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - Cache
  # =============================================================================
  #
  # This class manages the caching of repository states and Cookstyle results
  # to avoid reprocessing repositories that haven't changed.
  #
  # The Cache uses CacheEntry objects internally to store repository-specific data
  # and provides a consistent interface for cache operations.
  #
  class Cache
    extend T::Sig
    attr_reader :dir, :file, :data, :logger, :stats

    # Initialize the cache manager
    # @param dir [String] Directory to store cache files
    # @param logger [Logger] Logger instance
    def initialize(dir, logger)
      @dir = dir
      @file = File.join(dir, 'cache.json')
      @logger = logger

      # Create cache directory if it doesn't exist
      FileUtils.mkdir_p(dir)

      # Initialize statistics helper
      @stats = CacheStats.new

      load_cache

      # Give the stats object access to our data
      @stats.cache_data = @data
    end

    # Load cache from disk or initialize a new cache
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def load_cache
      @data = if File.exist?(@file)
                parse_cache_file
              else
                # Initialize cache and handle nil return
                result = initialize_cache
                if result.nil?
                  # Default hash
                  {
                    'repositories' => {},
                    'last_updated' => Time.now.utc.iso8601
                  }
                else
                  result
                end
              end
      @data
    end

    # Save cache to disk
    sig { returns(NilClass) }
    def save
      @data ||= {
        'repositories' => {},
        'last_updated' => Time.now.utc.iso8601
      }

      @data['last_updated'] = Time.now.utc.iso8601
      File.write(@file, JSON.pretty_generate(@data))
      logger.debug("Saved cache to #{@file}")
      nil
    end

    # Check if a repository is up to date in cache
    # @param repo_name [String] Repository name
    # @param current_sha [String] Current commit SHA
    # @param options [Hash] Options hash
    # @option options [Integer] :max_age Maximum age in seconds (default: 7 days)
    # @return [Boolean] True if repository is up to date
    def up_to_date?(repo_name, current_sha, options = {})
      # Default max_age to 7 days
      max_age = options[:max_age] || (7 * 24 * 60 * 60) # 7 days in seconds

      # Get cached repo data
      repo_data = @data['repositories'][repo_name]
      return false if repo_data.nil?

      # Convert hash data to CacheEntry object
      entry = CacheEntry.from_hash(repo_data)

      # Check if the commit SHA matches
      return false unless entry.matches_sha?(current_sha)

      # Check if cache entry is too old
      is_recent = !entry.expired?(max_age)

      if is_recent
        # Use the actual processing time from the entry instead of the SHA
        @stats.record_hit(entry.processing_time)
        true
      else
        false
      end
    end

    # Get cached result for a repository
    # @param repo_name [String] Repository name
    # @return [Hash, nil] Cached result or nil if not found
    def get_result(repo_name)
      repo_data = @data['repositories'][repo_name]
      return nil if repo_data.nil?

      CacheEntry.from_hash(repo_data).to_h
    end

    # Update the cache with repository processing results
    # @param repo_name [String] Repository name
    # @param commit_sha [String] Commit SHA
    # @param had_issues [Boolean] Whether issues were found
    # @param result [String] Processing result
    # @param processing_time [Float] Processing time in seconds
    # @return [nil]
    def update(repo_name, commit_sha, had_issues, result, processing_time)
      # Create a new CacheEntry object
      entry = CacheEntry.new(
        commit_sha: commit_sha,
        had_issues: had_issues,
        result: result,
        processing_time: processing_time
      )

      # Store the serialized entry in the cache
      @data['repositories'][repo_name] = entry.to_h

      # Update stats
      @stats.record_update
      @stats.record_miss
      save
    end

    # Clear the cache for a specific repository
    # @param repo_name [String] Repository name
    sig { params(repo_name: String).returns(NilClass) }
    def clear_repo(repo_name)
      @data['repositories'].delete(repo_name)
      save
    end

    # Clear the entire cache
    sig { returns(NilClass) }
    def clear_all
      @data = initialize_cache
      save
      nil
    end

    # Get cache statistics - delegates to the CacheStats object
    # @return [Hash] Cache statistics
    sig { returns(Hash) }
    def cache_stats
      # Ensure stats has up-to-date cache data
      @stats.cache_data = @data
      @stats.cache_stats
    end

    # Get runtime statistics
    sig { returns(Hash) }
    def runtime_stats
      @stats.runtime_stats
    end

    # Get average processing time from cache
    sig { returns(Float) }
    def average_processing_time
      times = @data['repositories'].values.map do |repo_data|
        entry = CacheEntry.from_hash(repo_data)
        entry.processing_time
      end.compact

      return 5.0 if times.empty?

      times.sum / times.size
    end

    private

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def parse_cache_file
      logger.debug("Loading cache from #{@file}")
      begin
        JSON.parse(File.read(@file))
      rescue JSON::ParserError => e
        logger.warn("Failed to parse cache file: #{e.message}")
        initialize_cache
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def initialize_cache
      @data = {
        'repositories' => {},
        'last_updated' => Time.now.utc.iso8601
      }
      logger.debug('Initialized new cache')
      save
      @data
    end
  end
end
