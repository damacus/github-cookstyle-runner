#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# GitHub Cookstyle Runner - Cache Manager
# =============================================================================
#
# This class manages the caching of repository states and Cookstyle results
# to avoid reprocessing repositories that haven't changed.
#

require 'json'
require 'fileutils'
require 'time'
require_relative 'cache_stats'

class CacheManager
  attr_reader :cache_dir, :cache_file, :cache_data, :logger, :stats

  # Initialize the cache manager
  # @param cache_dir [String] Directory to store cache files
  # @param logger [Logger] Logger instance
  def initialize(cache_dir, logger)
    @cache_dir = cache_dir
    @cache_file = File.join(cache_dir, 'cache.json')
    @logger = logger

    # Create cache directory if it doesn't exist
    FileUtils.mkdir_p(cache_dir) unless Dir.exist?(cache_dir)

    # Initialize statistics helper
    @stats = CacheStats.new

    # Load or initialize cache
    load_cache
  end

  # Load cache from disk or initialize a new cache
  def load_cache
    if File.exist?(@cache_file)
      parse_cache_file
    else
      initialize_cache
    end
  end

  private

  def parse_cache_file
    @cache_data = JSON.parse(File.read(@cache_file))
    logger.debug("Loaded cache from #{@cache_file}")
  rescue JSON::ParserError => e
    logger.warn("Failed to parse cache file: #{e.message}")
    initialize_cache
  end

  def initialize_cache
    @cache_data = {
      'repositories' => {},
      'last_updated' => Time.now.utc.iso8601
    }
    logger.debug('Initialized new cache')
    save_cache
  end

  # Save cache to disk
  def save_cache
    @cache_data['last_updated'] = Time.now.utc.iso8601
    File.write(@cache_file, JSON.pretty_generate(@cache_data))
    logger.debug("Saved cache to #{@cache_file}")
  end

  # Check if a repository is cached and up-to-date
  # @param repo_name [String] Repository name
  # @param current_sha [String] Current commit SHA
  # @param max_age [Integer] Maximum age of cache in seconds (default: 7 days)
  # @param avg_processing_time [Float] Average time to process a repository (for stats)
  # @return [Boolean] True if the repository is cached and up-to-date
  def up_to_date?(repo_name, current_sha, max_age = 7 * 24 * 60 * 60, avg_processing_time = 5.0)
    return false unless @cache_data['repositories'][repo_name]

    repo_cache = @cache_data['repositories'][repo_name]

    # Check if the commit SHA matches
    return false unless repo_cache['last_commit_sha'] == current_sha

    # Check if the cache is not too old
    last_check_time = Time.parse(repo_cache['last_check_time'])
    return false if Time.now.utc - last_check_time > max_age

    # Repository is up-to-date - update stats
    @stats.record_hit(avg_processing_time)

    logger.debug("Repository #{repo_name} is up-to-date in cache (SHA: #{current_sha})")
    true
  end

  # Get the cached result for a repository
  # @param repo_name [String] Repository name
  # @return [Hash, nil] Cached result or nil if not found
  def get_result(repo_name)
    return nil unless @cache_data['repositories'][repo_name]

    @cache_data['repositories'][repo_name]
  end

  # Update the cache with a new result
  # @param repo_name [String] Repository name
  # @param commit_sha [String] Current commit SHA
  # @param had_issues [Boolean] Whether the repository had Cookstyle issues
  # @param result [String] Result message
  # @param processing_time [Float] Time taken to process the repository (in seconds)
  def update(repo_name, commit_sha, had_issues, result, processing_time = nil)
    @cache_data['repositories'][repo_name] = {
      'last_commit_sha' => commit_sha,
      'last_check_time' => Time.now.utc.iso8601,
      'had_issues' => had_issues,
      'last_result' => result,
      'processing_time' => processing_time
    }

    # Update stats
    @stats.record_update
    @stats.record_miss

    save_cache
  end

  # Get the latest commit SHA for a repository
  # @param repo_dir [String] Repository directory
  # @return [String, nil] Latest commit SHA or nil if not found
  def self.get_latest_commit_sha(repo_dir)
    return nil unless Dir.exist?(repo_dir)

    # Get the latest commit SHA
    stdout, _stderr, status = Open3.capture3("cd #{repo_dir} && git rev-parse HEAD")
    return nil unless status.success?

    stdout.strip
  end

  private_class_method :get_latest_commit_sha

  # Clear the cache for a specific repository
  # @param repo_name [String] Repository name
  def clear_repo(repo_name)
    @cache_data['repositories'].delete(repo_name)
    save_cache
  end

  # Clear the entire cache
  def clear_all
    initialize_cache
  end

  # Get cache statistics
  # @return [Hash] Cache statistics
  def cache_stats
    {
      'total_repositories' => @cache_data['repositories'].size,
      'repositories_with_issues' => @cache_data['repositories'].count { |_, v| v['had_issues'] },
      'last_updated' => @cache_data['last_updated']
    }
  end

  # Get runtime statistics
  # @return [Hash] Runtime statistics
  def runtime_stats
    @stats.runtime_stats
  end

  # Get average processing time from cache
  # @return [Float] Average processing time in seconds
  def average_processing_time
    times = @cache_data['repositories'].values.map { |v| v['processing_time'] }.compact
    return 5.0 if times.empty? # Default if no data

    times.sum / times.size
  end
end
