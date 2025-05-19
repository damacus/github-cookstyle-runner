# typed: false
# frozen_string_literal: true

require 'spec_helper'

# Simple class to allow verified doubles in tests
class TestRunner
  def run(_paths)
    true
  end
end

RSpec.describe CookstyleBot::Runner do
  let(:repo_path) { '/path/to/repo' }
  let(:runner) { described_class.new(repo_path) }
  let(:logger) { instance_spy(Logger) }

  before do
    allow(CookstyleBot::Logging).to receive(:logger).and_return(logger)
    # Prevent actual loading of cookstyle and running against real repos
    allow(runner).to receive(:require).with('cookstyle')
  end

  describe '#initialize' do
    it 'sets up with a repository path' do
      expect(runner.repo_path).to eq(repo_path)
    end

    describe 'with options' do
      it 'accepts optional configuration' do
        runner_with_options = described_class.new(repo_path, auto_correct: true, format: 'json')
        expect(runner_with_options.options[:auto_correct]).to be true
      end

      it 'accepts optional format' do
        runner_with_options = described_class.new(repo_path, format: 'json')
        expect(runner_with_options.options[:format]).to eq('json')
      end
    end
  end

  describe '#run' do
    # Only mock what we need to prevent actual execution
    before do
      # Instead of mocking RuboCop internals, mock our own method
      # that would create the runner
      mock_runner = instance_double(TestRunner, run: true)

      # Provide test offense data
      allow(runner).to receive_messages(initialize_runner: mock_runner, extract_offenses: [
                                          {
                                            path: 'recipes/default.rb',
                                            line: 10,
                                            column: 5,
                                            severity: 'convention',
                                            message: 'Style/StringLiterals: Prefer single quotes',
                                            corrected: true
                                          }
                                        ])
    end

    it 'logs the start and completion of the run' do
      runner.run
      expect(logger).to have_received(:info).with(/Starting Cookstyle run on/)
      expect(logger).to have_received(:info).with(/Completed Cookstyle run/)
    end

    it 'returns a structured result with offenses' do
      result = runner.run
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true
      expect(result[:offenses]).to be_an(Array)
      expect(result[:offenses].first[:path]).to eq('recipes/default.rb')
      expect(result).to have_key(:timestamp)
    end

    context 'when an error occurs' do
      before do
        # Simulate an error during execution
        allow(runner).to receive(:require).with('cookstyle').and_raise(StandardError.new('Test error'))
      end

      it 'logs the error and returns failure details' do
        result = runner.run

        # Verify logging
        expect(logger).to have_received(:error).with(/Error running Cookstyle: Test error/)

        # Verify error result structure
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Test error')
        expect(result).to have_key(:backtrace)
      end
    end
  end

  describe '#extract_offenses' do
    it 'is a placeholder method returning an empty array' do
      expect(runner.send(:extract_offenses)).to eq([])
    end
  end
end
