# frozen_string_literal: true
# typed: strict

require 'time'
require 'sorbet-runtime'

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - Cache Entry
  # =============================================================================
  #
  # This class encapsulates individual cache entries for repository states and
  # Cookstyle results. It provides methods for expiration checking, SHA matching,
  # and serialization/deserialization.
  #
  class CacheEntry
    extend T::Sig

    sig { returns(String) }
    attr_reader :commit_sha

    sig { returns(T::Boolean) }
    attr_reader :had_issues

    sig { returns(T.nilable(String)) }
    attr_reader :result

    sig { returns(Float) }
    attr_reader :processing_time

    sig { returns(String) }
    attr_reader :timestamp

    # Initialize a new cache entry
    # @param commit_sha [String] Git commit SHA
    # @param had_issues [Boolean] Whether Cookstyle found issues
    # @param result [String, nil] Cookstyle result JSON string or nil
    # @param processing_time [Float] Time taken to process the repository in seconds
    # @param timestamp [String, nil] ISO-8601 timestamp or nil for current time
    sig do
      params(
        commit_sha: String,
        had_issues: T::Boolean,
        result: T.nilable(String),
        processing_time: Float,
        timestamp: T.nilable(String)
      ).void
    end
    def initialize(commit_sha:, had_issues:, result:, processing_time:, timestamp: nil)
      @commit_sha = commit_sha
      @had_issues = had_issues
      @result = result
      @processing_time = processing_time
      @timestamp = timestamp || Time.now.utc.iso8601
    end

    # Check if this cache entry matches a given SHA
    # @param sha [String] Git commit SHA to check against
    # @return [Boolean] True if SHA matches
    sig { params(sha: String).returns(T::Boolean) }
    def matches_sha?(sha)
      @commit_sha == sha
    end

    # Check if this cache entry has expired based on age
    # @param max_age [Integer] Maximum age in seconds
    # @return [Boolean] True if entry has expired
    sig { params(max_age: Integer).returns(T::Boolean) }
    def expired?(max_age)
      # Default to 7 days if max_age is 0 or invalid
      max_age = 7 * 24 * 60 * 60 if max_age <= 0

      entry_time = Time.parse(@timestamp)
      age_in_seconds = Time.now.utc - entry_time
      age_in_seconds > max_age
    end

    # Convert the cache entry to a hash for serialization
    # @return [Hash] Hash representation of the cache entry
    sig { returns(T::Hash[String, T.untyped]) }
    def to_h
      {
        'commit_sha' => @commit_sha,
        'had_issues' => @had_issues,
        'result' => @result,
        'processing_time' => @processing_time,
        'timestamp' => @timestamp
      }
    end

    # Create a CacheEntry from a hash
    # @param hash [Hash] Hash representation of a cache entry
    # @return [CacheEntry] New CacheEntry instance
    sig { params(hash: T::Hash[String, T.untyped]).returns(CacheEntry) }
    def self.from_hash(hash)
      new(
        commit_sha: hash['commit_sha'],
        had_issues: hash['had_issues'],
        result: hash['result'],
        processing_time: hash['processing_time'] || 0.0,
        timestamp: hash['timestamp']
      )
    rescue StandardError
      # If deserialization fails, create a placeholder entry
      new(
        commit_sha: 'invalid',
        had_issues: false,
        result: nil,
        processing_time: 0.0
      )
    end
  end
end
