# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'timecop'

RSpec.describe CookstyleRunner::CacheStats do
  let(:cache_data) do
    {
      'repositories' => {
        'repo1' => {
          'commit_sha' => '0123456789abcdef0123456789abcdef01234567',
          'had_issues' => true,
          'result' => '{"example": "result"}',
          'processing_time' => 2.5,
          'timestamp' => Time.now.utc.iso8601
        },
        'repo2' => {
          'commit_sha' => 'abcdef0123456789abcdef0123456789abcdef01',
          'had_issues' => false,
          'result' => '{"example": "clean_result"}',
          'processing_time' => 3.5,
          'timestamp' => Time.now.utc.iso8601
        }
      },
      'last_updated' => Time.now.utc.iso8601
    }
  end

  describe '#initialize' do
    it 'initializes with default values' do
      stats = described_class.new
      expect(stats.hits).to eq(0)
      expect(stats.misses).to eq(0)
      expect(stats.updates).to eq(0)
      expect(stats.time_saved).to eq(0.0)
      expect(stats.start_time).to be_a(Time)
    end

    it 'accepts cache_data parameter' do
      stats = described_class.new(cache_data)
      # Should not throw errors
      expect(stats).to be_a(described_class)
    end
  end

  describe '#record_hit' do
    let(:stats) { described_class.new }

    it 'increments hits counter' do
      expect { stats.record_hit(2.5) }.to change(stats, :hits).from(0).to(1)
    end

    it 'adds to time_saved' do
      expect { stats.record_hit(2.5) }.to change(stats, :time_saved).from(0.0).to(2.5)
    end

    it 'returns the current time_saved value' do
      expect(stats.record_hit(2.5)).to eq(2.5)
      expect(stats.record_hit(3.0)).to eq(5.5) # 2.5 + 3.0
    end
  end

  describe '#record_miss' do
    let(:stats) { described_class.new }

    it 'increments misses counter' do
      expect { stats.record_miss }.to change(stats, :misses).from(0).to(1)
    end

    it 'returns the current misses count' do
      expect(stats.record_miss).to eq(1)
      expect(stats.record_miss).to eq(2)
    end
  end

  describe '#record_update' do
    let(:stats) { described_class.new }

    it 'increments updates counter' do
      expect { stats.record_update }.to change(stats, :updates).from(0).to(1)
    end

    it 'returns the current updates count' do
      expect(stats.record_update).to eq(1)
      expect(stats.record_update).to eq(2)
    end
  end

  describe '#runtime_stats' do
    let(:stats) { described_class.new }

    it 'returns a hash with expected keys' do
      stats_hash = stats.runtime_stats
      expect(stats_hash).to be_a(Hash)
      expect(stats_hash).to include(
        'cache_hits',
        'cache_misses',
        'cache_updates',
        'cache_hit_rate',
        'estimated_time_saved',
        'runtime'
      )
    end

    it 'calculates cache hit rate correctly with activity' do
      # Record 3 hits and 2 misses (60% hit rate)
      3.times { stats.record_hit(1.0) }
      2.times { stats.record_miss }

      stats_hash = stats.runtime_stats
      expect(stats_hash['cache_hits']).to eq(3)
      expect(stats_hash['cache_misses']).to eq(2)
      expect(stats_hash['cache_hit_rate']).to eq(60.0)
    end

    it 'handles zero requests correctly' do
      stats_hash = stats.runtime_stats
      expect(stats_hash['cache_hit_rate']).to eq(0)
    end

    it 'calculates runtime correctly' do
      start_time = Time.parse('2023-01-01T12:00:00Z')
      end_time = Time.parse('2023-01-01T12:00:10Z') # 10 seconds later

      Timecop.freeze(start_time) do
        @stats = described_class.new
      end

      Timecop.freeze(end_time) do
        stats_hash = @stats.runtime_stats
        expect(stats_hash['runtime']).to eq(10.0)
      end
    end
  end

  describe '#cache_stats' do
    it 'returns empty stats when no cache_data is provided' do
      stats = described_class.new
      stats_hash = stats.cache_stats
      expect(stats_hash).to include(
        'total_repositories',
        'repositories_with_issues',
        'last_updated'
      )
      expect(stats_hash['total_repositories']).to eq(0)
      expect(stats_hash['repositories_with_issues']).to eq(0)
    end

    it 'returns correct repository counts when cache_data is provided' do
      stats = described_class.new
      stats.cache_data = cache_data

      stats_hash = stats.cache_stats
      expect(stats_hash['total_repositories']).to eq(2)
      expect(stats_hash['repositories_with_issues']).to eq(1) # Only repo1 has issues
      expect(stats_hash['last_updated']).to eq(cache_data['last_updated'])
    end
  end
end
