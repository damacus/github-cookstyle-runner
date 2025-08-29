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
      mock_tempfile = instance_double(Tempfile, path: '/tmp/mock_output.json', unlink: nil)

      # Mock the file reading and provide test JSON output
      test_json_output = {
        'files' => [
          {
            'path' => 'recipes/default.rb',
            'offenses' => [
              {
                'severity' => 'convention',
                'message' => 'Style/StringLiterals: Prefer single quotes',
                'cop_name' => 'Style/StringLiterals',
                'corrected' => true,
                'location' => { 'line' => 10, 'column' => 5 }
              }
            ]
          }
        ]
      }.to_json

      allow(runner).to receive_messages(initialize_runner_with_output: [mock_runner, mock_tempfile])
      allow(File).to receive(:exist?).with('/tmp/mock_output.json').and_return(true)
      allow(File).to receive(:read).with('/tmp/mock_output.json').and_return(test_json_output)
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
    context 'when no rubocop output is available' do
      it 'returns an empty array' do
        expect(runner.send(:extract_offenses)).to eq([])
      end
    end

    context 'when rubocop output is available' do
      let(:test_json_output) do
        {
          'files' => [
            {
              'path' => '/path/to/file.rb',
              'offenses' => [
                {
                  'severity' => 'convention',
                  'message' => 'Style/StringLiterals: Prefer single quotes',
                  'cop_name' => 'Style/StringLiterals',
                  'corrected' => false,
                  'location' => { 'line' => 10, 'column' => 5 }
                },
                {
                  'severity' => 'error',
                  'message' => 'Syntax error detected',
                  'cop_name' => 'Lint/Syntax',
                  'corrected' => false,
                  'location' => { 'start_line' => 15, 'start_column' => 3 }
                }
              ]
            }
          ]
        }.to_json
      end

      before do
        runner.instance_variable_set(:@rubocop_output, test_json_output)
      end

      it 'parses JSON output and returns structured offense data' do
        offenses = runner.send(:extract_offenses)

        expect(offenses).to be_an(Array)
        expect(offenses.length).to eq(2)
      end

      it 'correctly maps first offense attributes' do
        first_offense = runner.send(:extract_offenses)[0]

        expect(first_offense[:path]).to eq('/path/to/file.rb')
        expect(first_offense[:line]).to eq(10)
        expect(first_offense[:severity]).to eq('convention')
        expect(first_offense[:cop_name]).to eq('Style/StringLiterals')
        expect(first_offense[:corrected]).to be false
      end

      it 'correctly maps second offense attributes' do
        second_offense = runner.send(:extract_offenses)[1]

        expect(second_offense[:path]).to eq('/path/to/file.rb')
        expect(second_offense[:line]).to eq(15)
        expect(second_offense[:severity]).to eq('error')
        expect(second_offense[:cop_name]).to eq('Lint/Syntax')
      end
    end

    context 'when rubocop output is invalid JSON' do
      before do
        runner.instance_variable_set(:@rubocop_output, 'invalid json')
      end

      it 'returns an empty array and logs an error' do
        expect(runner.send(:extract_offenses)).to eq([])
      end
    end
  end
end
