# frozen_string_literal: true

# =============================================================================
# GitHub Cookstyle Runner - CacheStats
# =============================================================================
#
# This class encapsulates runtime and cache statistics for the Cookstyle Runner.
# It tracks cache hits, misses, updates, estimated time saved, and runtime.
#

# CacheStats encapsulates runtime and cache statistics for the Cookstyle Runner.
# It tracks cache hits, misses, updates, estimated time saved, and runtime.
class CacheStats
  attr_reader :hits, :misses, :updates, :time_saved, :start_time

  def initialize
    @hits = 0
    @misses = 0
    @updates = 0
    @time_saved = 0.0 # seconds
    @start_time = Time.now.utc
  end

  def record_hit(avg_processing_time)
    @hits += 1
    @time_saved += avg_processing_time
  end

  def record_miss
    @misses += 1
  end

  def record_update
    @updates += 1
  end

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
end
