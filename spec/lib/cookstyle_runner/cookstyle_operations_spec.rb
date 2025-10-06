# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/cookstyle_operations'
require 'cookstyle_runner/git'
require 'logger'

RSpec.describe CookstyleRunner::CookstyleOperations do
  # Sample Cookstyle JSON output fixtures
  let(:clean_json) do
    {
      'files' => [],
      'summary' => { 'offense_count' => 0 }
    }
  end

  let(:correctable_offenses_json) do
    {
      'files' => [
        {
          'path' => 'recipes/default.rb',
          'offenses' => [
            {
              'message' => 'Layout/TrailingWhitespace: Trailing whitespace detected.',
              'cop_name' => 'Layout/TrailingWhitespace',
              'correctable' => true
            },
            {
              'message' => 'Style/StringLiterals: Prefer single-quoted strings.',
              'cop_name' => 'Style/StringLiterals',
              'correctable' => true
            }
          ]
        }
      ],
      'summary' => { 'offense_count' => 2 }
    }
  end

  let(:uncorrectable_offenses_json) do
    {
      'files' => [
        {
          'path' => 'recipes/server.rb',
          'offenses' => [
            {
              'message' => 'Chef/Deprecations/ResourceWithoutUnifiedTrue: Set `unified_mode true`',
              'cop_name' => 'Chef/Deprecations/ResourceWithoutUnifiedTrue',
              'correctable' => false
            }
          ]
        }
      ],
      'summary' => { 'offense_count' => 1 }
    }
  end

  let(:mixed_offenses_json) do
    {
      'files' => [
        {
          'path' => 'recipes/default.rb',
          'offenses' => [
            {
              'message' => 'Layout/TrailingWhitespace: Trailing whitespace detected.',
              'cop_name' => 'Layout/TrailingWhitespace',
              'correctable' => true
            }
          ]
        },
        {
          'path' => 'recipes/server.rb',
          'offenses' => [
            {
              'message' => 'Chef/Deprecations/ResourceWithoutUnifiedTrue: Set `unified_mode true`',
              'cop_name' => 'Chef/Deprecations/ResourceWithoutUnifiedTrue',
              'correctable' => false
            }
          ]
        }
      ],
      'summary' => { 'offense_count' => 2 }
    }
  end

  describe '.offenses?' do
    it 'returns false when no files have offenses' do
      expect(described_class.offenses?(clean_json)).to be false
    end

    it 'returns true when files have offenses' do
      expect(described_class.offenses?(correctable_offenses_json)).to be true
    end

    it 'returns false when files array is missing' do
      expect(described_class.offenses?({})).to be false
    end

    it 'returns false when files have empty offenses arrays' do
      json = { 'files' => [{ 'path' => 'test.rb', 'offenses' => [] }] }
      expect(described_class.offenses?(json)).to be false
    end
  end

  describe '.count_correctable_offences' do
    it 'returns 0 for clean code' do
      expect(described_class.count_correctable_offences(clean_json)).to eq(0)
    end

    it 'counts correctable offenses correctly' do
      expect(described_class.count_correctable_offences(correctable_offenses_json)).to eq(2)
    end

    it 'ignores uncorrectable offenses' do
      expect(described_class.count_correctable_offences(uncorrectable_offenses_json)).to eq(0)
    end

    it 'counts only correctable offenses in mixed output' do
      expect(described_class.count_correctable_offences(mixed_offenses_json)).to eq(1)
    end

    it 'handles missing files key' do
      expect(described_class.count_correctable_offences({})).to eq(0)
    end
  end

  describe '.count_uncorrectable_offences' do
    it 'returns 0 for clean code' do
      expect(described_class.count_uncorrectable_offences(clean_json)).to eq(0)
    end

    it 'counts uncorrectable offenses correctly' do
      expect(described_class.count_uncorrectable_offences(uncorrectable_offenses_json)).to eq(1)
    end

    it 'ignores correctable offenses' do
      expect(described_class.count_uncorrectable_offences(correctable_offenses_json)).to eq(0)
    end

    it 'counts only uncorrectable offenses in mixed output' do
      expect(described_class.count_uncorrectable_offences(mixed_offenses_json)).to eq(1)
    end

    it 'handles missing files key' do
      expect(described_class.count_uncorrectable_offences({})).to eq(0)
    end
  end

  describe '.format_pr_summary' do
    it 'formats summary with all auto-corrected' do
      summary = described_class.format_pr_summary(5, 5)
      expect(summary).to include('Total Offenses Detected:** 5')
      expect(summary).to include('Auto-corrected:** 5')
      expect(summary).to include('Manual Review Needed:** 0')
    end

    it 'formats summary with mixed corrections' do
      summary = described_class.format_pr_summary(10, 7)
      expect(summary).to include('Total Offenses Detected:** 10')
      expect(summary).to include('Auto-corrected:** 7')
      expect(summary).to include('Manual Review Needed:** 3')
    end

    it 'formats summary with no corrections' do
      summary = described_class.format_pr_summary(0, 0)
      expect(summary).to include('Total Offenses Detected:** 0')
      expect(summary).to include('Auto-corrected:** 0')
      expect(summary).to include('Manual Review Needed:** 0')
    end
  end

  describe '.format_pr_description' do
    it 'returns empty string when no auto-correctable offenses' do
      expect(described_class.format_pr_description(clean_json, 0)).to eq('')
    end

    it 'formats offense details when auto-correctable offenses exist' do
      description = described_class.format_pr_description(correctable_offenses_json, 2)
      expect(description).to include('### Offences')
      expect(description).to include('recipes/default.rb')
      expect(description).to include('Trailing whitespace detected')
    end
  end

  describe '.format_offenses' do
    it 'returns empty string for clean code' do
      expect(described_class.format_offenses(clean_json)).to eq('')
    end

    it 'formats offenses as bullet list' do
      offenses = described_class.format_offenses(correctable_offenses_json)
      expect(offenses).to include('* recipes/default.rb:')
      expect(offenses).to include('Trailing whitespace detected')
      expect(offenses).to include('Prefer single-quoted strings')
    end

    it 'handles missing files key' do
      expect(described_class.format_offenses({})).to eq('')
    end
  end

  describe '.format_issue_summary' do
    it 'returns empty string when no manual fixes needed' do
      expect(described_class.format_issue_summary(5, 0)).to eq('')
    end

    it 'formats summary when manual fixes are needed' do
      summary = described_class.format_issue_summary(10, 3)
      expect(summary).to include('Cookstyle Manual Review Summary')
      expect(summary).to include('Total Offenses Detected:** 10')
      expect(summary).to include('Manual Review Needed:** 3')
    end
  end

  describe '.format_issue_description' do
    it 'returns empty string for clean code' do
      expect(described_class.format_issue_description(clean_json)).to eq('')
    end

    it 'formats manual offense details' do
      description = described_class.format_issue_description(uncorrectable_offenses_json)
      expect(description).to include('### Manual Intervention Required')
      expect(description).to include('recipes/server.rb')
      expect(description).to include('Chef/Deprecations/ResourceWithoutUnifiedTrue')
    end

    it 'excludes correctable offenses' do
      description = described_class.format_issue_description(correctable_offenses_json)
      expect(description).to eq('')
    end
  end

  describe '.manual_offenses' do
    it 'returns empty array for clean code' do
      expect(described_class.manual_offenses(clean_json)).to eq([])
    end

    it 'returns only uncorrectable offenses' do
      offenses = described_class.manual_offenses(mixed_offenses_json)
      expect(offenses.size).to eq(1)
      expect(offenses.first).to include('recipes/server.rb')
      expect(offenses.first).to include('Chef/Deprecations/ResourceWithoutUnifiedTrue')
    end

    it 'excludes correctable offenses' do
      offenses = described_class.manual_offenses(correctable_offenses_json)
      expect(offenses).to be_empty
    end

    it 'handles missing files key' do
      expect(described_class.manual_offenses({})).to eq([])
    end
  end

  describe '.format_manual_offense' do
    let(:file) { { 'path' => 'recipes/default.rb' } }
    let(:offense) do
      {
        'cop_name' => 'Chef/Deprecations/ResourceWithoutUnifiedTrue',
        'message' => "Set `unified_mode true`\nin your resource"
      }
    end

    it 'formats offense with file path and cop name' do
      result = described_class.format_manual_offense(file, offense)
      expect(result).to include('recipes/default.rb')
      expect(result).to include('Chef/Deprecations/ResourceWithoutUnifiedTrue')
    end

    it 'handles multi-line messages' do
      result = described_class.format_manual_offense(file, offense)
      expect(result).to include('Set `unified_mode true` in your resource')
      expect(result).not_to include("\n")
    end

    it 'handles missing message' do
      offense_no_msg = { 'cop_name' => 'TestCop', 'message' => nil }
      result = described_class.format_manual_offense(file, offense_no_msg)
      expect(result).to include('No message')
    end
  end

  describe 'CookstyleRunner::Report' do
    it 'initializes with default values' do
      report = CookstyleRunner::Report.new
      expect(report.num_auto).to eq(0)
      expect(report.num_manual).to eq(0)
      expect(report.total_correctable).to eq(0)
      expect(report.pr_description).to eq('')
      expect(report.issue_description).to eq('')
      expect(report.error).to be false
      expect(report.status).to eq(:no_issues)
      expect(report.changes_committed).to be false
    end

    it 'calculates total_correctable correctly' do
      report = CookstyleRunner::Report.new(num_auto: 5, num_manual: 3)
      expect(report.total_correctable).to eq(8)
    end

    it 'accepts custom values' do
      report = CookstyleRunner::Report.new(
        num_auto: 10,
        num_manual: 5,
        pr_description: 'PR desc',
        issue_description: 'Issue desc',
        error: true,
        status: :has_issues,
        changes_committed: true
      )
      expect(report.num_auto).to eq(10)
      expect(report.num_manual).to eq(5)
      expect(report.pr_description).to eq('PR desc')
      expect(report.issue_description).to eq('Issue desc')
      expect(report.error).to be true
      expect(report.status).to eq(:has_issues)
      expect(report.changes_committed).to be true
    end
  end

  describe '.run_cookstyle' do
    let(:logger) { instance_double(Logger, debug: nil, error: nil, info: nil) }
    let(:context) { instance_double(CookstyleRunner::Git::RepoContext, repo_name: 'test-repo', repo_dir: '/tmp/test-repo') }
    let(:cmd) { instance_double(TTY::Command) }

    before do
      allow(TTY::Command).to receive(:new).and_return(cmd)
    end

    context 'when cookstyle command fails with exit status 2' do
      let(:failed_result) do
        instance_double(
          TTY::Command::Result,
          exit_status: 2,
          out: '',
          err: 'Error: unrecognized cop or department Naming/PredicateMethod found in /app/.rubocop_todo.yml'
        )
      end

      it 'returns DEFAULT_ERROR_RETURN when cookstyle fails' do
        allow(cmd).to receive(:run!).and_return(failed_result)

        result = described_class.run_cookstyle(context, logger)

        expect(result[:parsed_json]).to be_nil
        expect(result[:report]).to be_a(CookstyleRunner::Report)
        expect(result[:report].error).to be true
      end

      it 'logs error details when cookstyle fails' do
        allow(cmd).to receive(:run!).and_return(failed_result)

        described_class.run_cookstyle(context, logger)

        expect(logger).to have_received(:error).with('Cookstyle command failed unexpectedly.')
        expect(logger).to have_received(:error).with('Exit Status: 2')
        expect(logger).to have_received(:error).with(/unrecognized cop/)
      end
    end

    context 'when cookstyle returns invalid JSON' do
      let(:invalid_json_result) do
        instance_double(
          TTY::Command::Result,
          exit_status: 0,
          out: 'not valid json',
          err: ''
        )
      end

      it 'returns DEFAULT_ERROR_RETURN when JSON parsing fails' do
        allow(cmd).to receive(:run!).and_return(invalid_json_result)

        result = described_class.run_cookstyle(context, logger)

        expect(result[:parsed_json]).to be_nil
        expect(result[:report]).to be_a(CookstyleRunner::Report)
        expect(result[:report].error).to be true
      end

      it 'logs missing parsed_json error' do
        allow(cmd).to receive(:run!).and_return(invalid_json_result)

        described_class.run_cookstyle(context, logger)

        expect(logger).to have_received(:error).with(/Missing parsed_json/)
      end
    end

    context 'when cookstyle succeeds with no offenses' do
      let(:clean_result) do
        instance_double(
          TTY::Command::Result,
          exit_status: 0,
          out: clean_json.to_json,
          err: ''
        )
      end

      it 'returns parsed results with no offenses' do
        allow(cmd).to receive(:run!).and_return(clean_result)

        result = described_class.run_cookstyle(context, logger)

        expect(result[:parsed_json]).to eq(clean_json)
        expect(result[:report].num_auto).to eq(0)
        expect(result[:report].num_manual).to eq(0)
        expect(result[:report].error).to be false
      end
    end
  end
end
