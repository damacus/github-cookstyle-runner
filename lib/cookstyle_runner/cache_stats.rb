# frozen_string_literal: true
# typed: true

require 'pp'
require 'sorbet-runtime'

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - CacheStats
  # =============================================================================
  #
  # This class encapsulates runtime and cache statistics for the Cookstyle Runner.
  # It tracks cache hits, misses, updates, estimated time saved, and runtime.
  #

  # CacheStats encapsulates runtime and cache statistics for the Cookstyle Runner.
  # It tracks cache hits, misses, updates, estimated time saved, and runtime.
  # It also provides statistics about the repositories in the cache.
  class CacheStats
    extend T::Sig

    attr_reader :hits, :misses, :updates, :time_saved, :start_time
    attr_writer :cache_data

    # Initialize a new CacheStats object
    # @param cache_data [Hash, nil] Optional reference to the cache data
    sig { params(cache_data: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def initialize(cache_data = nil)
      @hits = 0
      @misses = 0
      @updates = 0
      @time_saved = 0.0 # seconds
      @start_time = Time.now.utc
      @cache_data = cache_data
    end

    # Record a cache hit
    sig { params(avg_processing_time: Float).returns(Float) }
    def record_hit(avg_processing_time)
      @hits += 1
      @time_saved += avg_processing_time
      @time_saved
    end

    # Record a cache miss
    sig { returns(Integer) }
    def record_miss
      @misses += 1
    end

    # Record a cache update
    sig { returns(Integer) }
    def record_update
      @updates += 1
    end

    # Get runtime statistics
    sig { returns(T::Hash[String, T.untyped]) }
    def runtime_stats
      total_requests = @hits + @misses
      hit_rate = total_requests.positive? ? (@hits.to_f / total_requests * 100).round(2) : 0
      {
        'cache_hits' => @hits,
        'cache_misses' => @misses,
        'cache_updates' => @updates,
        'cache_hit_rate' => hit_rate,
        'estimated_time_saved' => @time_saved.round(2),
        'runtime' => (Time.now.utc - @start_time).round(2)
      }
    end

    # Get cache statistics
    # @return [Hash] Cache statistics
    sig { returns(T::Hash[String, T.untyped]) }
    def cache_stats
      return { 'total_repositories' => 0, 'repositories_with_issues' => 0, 'last_updated' => Time.now.utc.iso8601 } unless @cache_data

      {
        'total_repositories' => @cache_data['repositories'].size,
        'repositories_with_issues' => @cache_data['repositories'].count do |_, repo_data|
          entry = CacheEntry.from_hash(repo_data)
          entry.had_issues
        end,
        'last_updated' => @cache_data['last_updated']
      }
    end
  end
end
