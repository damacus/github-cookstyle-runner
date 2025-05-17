# frozen_string_literal: true

require 'spec_helper'
require 'time'
require 'timecop'

RSpec.describe CookstyleRunner::CacheEntry do
  let(:commit_sha) { '0123456789abcdef0123456789abcdef01234567' }
  let(:had_issues) { true }
  let(:result) { '{"example": "result"}' }
  let(:processing_time) { 2.5 }
  let(:timestamp) { '2023-01-01T12:00:00Z' }
  let(:entry) do
    described_class.new(commit_sha: commit_sha, had_issues: had_issues, result: result, processing_time: processing_time, timestamp: timestamp)
  end

  describe '#initialize' do
    it 'sets attributes correctly with all parameters' do
      expect(entry.commit_sha).to eq(commit_sha)
      expect(entry.had_issues).to eq(had_issues)
      expect(entry.result).to eq(result)
      expect(entry.processing_time).to eq(processing_time)
      expect(entry.timestamp).to eq(timestamp)
    end

    it 'sets timestamp to current time if not provided' do
      current_time = Time.parse('2023-02-01T12:00:00Z')
      Timecop.freeze(current_time) do
        new_entry = described_class.new(
          commit_sha: commit_sha,
          had_issues: had_issues,
          result: result,
          processing_time: processing_time
        )
        expect(new_entry.timestamp).to eq(current_time.utc.iso8601)
      end
    end

    it 'handles nil result correctly' do
      new_entry = described_class.new(
        commit_sha: commit_sha,
        had_issues: had_issues,
        result: nil,
        processing_time: processing_time,
        timestamp: timestamp
      )
      expect(new_entry.result).to be_nil
    end
  end

  describe '#matches_sha?' do
    it 'returns true when SHA matches' do
      expect(entry.matches_sha?(commit_sha)).to be true
    end

    it 'returns false when SHA does not match' do
      expect(entry.matches_sha?('different_sha')).to be false
    end
  end

  describe '#expired?' do
    let(:entry_time) { Time.parse(timestamp) }
    let(:one_week_in_seconds) { 7 * 24 * 60 * 60 }

    context 'when entry is older than max_age' do
      it 'returns true' do
        future_time = entry_time + one_week_in_seconds + 1
        Timecop.freeze(future_time) do
          expect(entry.expired?(one_week_in_seconds)).to be true
        end
      end
    end

    context 'when entry is newer than max_age' do
      it 'returns false' do
        future_time = entry_time + one_week_in_seconds - 1
        Timecop.freeze(future_time) do
          expect(entry.expired?(one_week_in_seconds)).to be false
        end
      end
    end

    context 'when max_age is 0 or negative' do
      it 'defaults to 7 days when max_age is 0' do
        future_time = entry_time + one_week_in_seconds - 1
        Timecop.freeze(future_time) do
          expect(entry.expired?(0)).to be false
        end

        future_time = entry_time + one_week_in_seconds + 1
        Timecop.freeze(future_time) do
          expect(entry.expired?(0)).to be true
        end
      end

      it 'defaults to 7 days when max_age is negative' do
        future_time = entry_time + one_week_in_seconds - 1
        Timecop.freeze(future_time) do
          expect(entry.expired?(-10)).to be false
        end

        future_time = entry_time + one_week_in_seconds + 1
        Timecop.freeze(future_time) do
          expect(entry.expired?(-10)).to be true
        end
      end
    end
  end

  describe '#to_h' do
    it 'returns a hash with all attributes' do
      hash = entry.to_h
      expect(hash).to be_a(Hash)
      expect(hash['commit_sha']).to eq(commit_sha)
      expect(hash['had_issues']).to eq(had_issues)
      expect(hash['result']).to eq(result)
      expect(hash['processing_time']).to eq(processing_time)
      expect(hash['timestamp']).to eq(timestamp)
    end
  end

  describe '.from_hash' do
    let(:hash) do
      {
        'commit_sha' => commit_sha,
        'had_issues' => had_issues,
        'result' => result,
        'processing_time' => processing_time,
        'timestamp' => timestamp
      }
    end

    it 'creates a CacheEntry from a valid hash' do
      entry = described_class.from_hash(hash)
      expect(entry).to be_a(described_class)
      expect(entry.commit_sha).to eq(commit_sha)
      expect(entry.had_issues).to eq(had_issues)
      expect(entry.result).to eq(result)
      expect(entry.processing_time).to eq(processing_time)
      expect(entry.timestamp).to eq(timestamp)
    end

    it 'handles missing processing_time by defaulting to 0.0' do
      hash_without_time = hash.dup
      hash_without_time.delete('processing_time')
      entry = described_class.from_hash(hash_without_time)
      expect(entry.processing_time).to eq(0.0)
    end

    it 'creates a placeholder entry when deserialization fails' do
      invalid_hash = { 'invalid' => 'data' }
      entry = described_class.from_hash(invalid_hash)
      expect(entry).to be_a(described_class)
      expect(entry.commit_sha).to eq('invalid')
      expect(entry.had_issues).to be false
      expect(entry.result).to be_nil
      expect(entry.processing_time).to eq(0.0)
    end
  end
end
