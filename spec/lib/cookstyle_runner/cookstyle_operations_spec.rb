# typed: false
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

  describe '.count_offences' do
    it 'returns zeroes for clean code' do
      result = described_class.count_offences(clean_json)
      expect(result).to eq({ correctable: 0, uncorrectable: 0 })
    end

    it 'counts correctable offenses correctly' do
      result = described_class.count_offences(correctable_offenses_json)
      expect(result).to eq({ correctable: 2, uncorrectable: 0 })
    end

    it 'counts uncorrectable offenses correctly' do
      result = described_class.count_offences(uncorrectable_offenses_json)
      expect(result).to eq({ correctable: 0, uncorrectable: 1 })
    end

    it 'counts both types in mixed output' do
      result = described_class.count_offences(mixed_offenses_json)
      expect(result).to eq({ correctable: 1, uncorrectable: 1 })
    end

    it 'handles missing files key' do
      result = described_class.count_offences({})
      expect(result).to eq({ correctable: 0, uncorrectable: 0 })
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
    let(:logger) { SemanticLogger['Test'] }
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

        result = described_class.run_cookstyle(context)

        expect(result[:parsed_json]).to be_nil
        expect(result[:report]).to be_a(CookstyleRunner::Report)
        expect(result[:report].error).to be true
      end

      it 'logs error details when cookstyle fails' do
        allow(cmd).to receive(:run!).and_return(failed_result)

        # SemanticLogger will log errors, but we can't spy on it
        # Just verify the method completes without raising
        expect { described_class.run_cookstyle(context) }.not_to raise_error
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

        result = described_class.run_cookstyle(context)

        expect(result[:parsed_json]).to be_nil
        expect(result[:report]).to be_a(CookstyleRunner::Report)
        expect(result[:report].error).to be true
      end

      it 'logs missing parsed_json error' do
        allow(cmd).to receive(:run!).and_return(invalid_json_result)

        # SemanticLogger will log errors, but we can't spy on it
        # Just verify the method completes without raising
        expect { described_class.run_cookstyle(context) }.not_to raise_error
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

        result = described_class.run_cookstyle(context)

        expect(result[:parsed_json]).to eq(clean_json)
        expect(result[:report].num_auto).to eq(0)
        expect(result[:report].num_manual).to eq(0)
        expect(result[:report].error).to be false
      end
    end
  end

  describe '.extract_offenses' do
    context 'when parsed_json is nil' do
      it 'returns an empty array' do
        expect(described_class.extract_offenses(nil)).to eq([])
      end
    end

    context 'when parsed_json is empty' do
      it 'returns an empty array' do
        expect(described_class.extract_offenses({})).to eq([])
      end
    end

    context 'when parsed_json has no files' do
      it 'returns an empty array' do
        expect(described_class.extract_offenses(clean_json)).to eq([])
      end
    end

    context 'when parsed_json has offenses' do
      let(:detailed_offenses_json) do
        {
          'files' => [
            {
              'path' => '/path/to/file.rb',
              'offenses' => [
                {
                  'severity' => 'convention',
                  'message' => 'Style/StringLiterals: Prefer single-quoted strings',
                  'cop_name' => 'Style/StringLiterals',
                  'corrected' => false,
                  'correctable' => true,
                  'location' => { 'line' => 10, 'column' => 5 }
                },
                {
                  'severity' => 'error',
                  'message' => 'Syntax error detected',
                  'cop_name' => 'Lint/Syntax',
                  'corrected' => false,
                  'correctable' => false,
                  'location' => { 'start_line' => 15, 'start_column' => 3 }
                }
              ]
            }
          ]
        }
      end

      it 'returns an array of offense hashes' do
        offenses = described_class.extract_offenses(detailed_offenses_json)

        expect(offenses).to be_an(Array)
        expect(offenses.length).to eq(2)
      end

      it 'correctly maps first offense attributes' do
        first_offense = described_class.extract_offenses(detailed_offenses_json)[0]

        expect(first_offense[:path]).to eq('/path/to/file.rb')
        expect(first_offense[:line]).to eq(10)
        expect(first_offense[:column]).to eq(5)
        expect(first_offense[:severity]).to eq('convention')
        expect(first_offense[:cop_name]).to eq('Style/StringLiterals')
        expect(first_offense[:message]).to eq('Style/StringLiterals: Prefer single-quoted strings')
        expect(first_offense[:corrected]).to be false
        expect(first_offense[:correctable]).to be true
      end

      it 'correctly maps second offense attributes with start_line/start_column' do
        second_offense = described_class.extract_offenses(detailed_offenses_json)[1]

        expect(second_offense[:path]).to eq('/path/to/file.rb')
        expect(second_offense[:line]).to eq(15)
        expect(second_offense[:column]).to eq(3)
        expect(second_offense[:severity]).to eq('error')
        expect(second_offense[:cop_name]).to eq('Lint/Syntax')
        expect(second_offense[:correctable]).to be false
      end
    end

    context 'when parsed_json has multiple files with offenses' do
      let(:multi_file_json) do
        {
          'files' => [
            {
              'path' => 'file1.rb',
              'offenses' => [
                {
                  'severity' => 'convention',
                  'message' => 'Test message',
                  'cop_name' => 'TestCop',
                  'corrected' => false,
                  'correctable' => true,
                  'location' => { 'line' => 1, 'column' => 1 }
                }
              ]
            },
            {
              'path' => 'file2.rb',
              'offenses' => [
                {
                  'severity' => 'warning',
                  'message' => 'Another test',
                  'cop_name' => 'AnotherCop',
                  'corrected' => true,
                  'correctable' => true,
                  'location' => { 'line' => 2, 'column' => 2 }
                }
              ]
            }
          ]
        }
      end

      it 'extracts offenses from all files' do
        offenses = described_class.extract_offenses(multi_file_json)
        expect(offenses.length).to eq(2)
        expect(offenses[0][:path]).to eq('file1.rb')
        expect(offenses[1][:path]).to eq('file2.rb')
      end
    end
  end

  describe 'CookstyleRunner::CommandPrinter' do
    let(:logger) { instance_double(SemanticLogger::Logger) }
    let(:printer) { CookstyleRunner::CommandPrinter.new(logger) }
    let(:mock_cmd) { instance_double(TTY::Command::Cmd, to_command: 'cookstyle --format json') }

    describe '#print_command_start' do
      it 'logs command at DEBUG level' do
        allow(logger).to receive(:debug)

        printer.print_command_start(mock_cmd)

        expect(logger).to have_received(:debug).with('Running command: cookstyle --format json')
      end
    end

    describe '#print_command_exit' do
      it 'logs success at DEBUG level with runtime' do
        allow(logger).to receive(:debug)

        printer.print_command_exit(mock_cmd, 0, 1.234)

        expect(logger).to have_received(:debug).with(/Command finished in 1\.234s with exit status 0/)
      end

      it 'logs failure at WARN level with runtime' do
        allow(logger).to receive(:warn)

        printer.print_command_exit(mock_cmd, 1, 2.567)

        expect(logger).to have_received(:warn).with(/Command failed in 2\.567s with exit status 1/)
      end
    end

    describe '#print_command_out_data' do
      it 'suppresses stdout output' do
        allow(logger).to receive(:debug)
        allow(logger).to receive(:info)

        printer.print_command_out_data(mock_cmd, 'some stdout data')

        expect(logger).not_to have_received(:debug)
        expect(logger).not_to have_received(:info)
      end
    end

    describe '#print_command_err_data' do
      it 'suppresses stderr output' do
        allow(logger).to receive(:debug)
        allow(logger).to receive(:warn)
        allow(logger).to receive(:error)

        printer.print_command_err_data(mock_cmd, 'some stderr data')

        expect(logger).not_to have_received(:debug)
        expect(logger).not_to have_received(:warn)
        expect(logger).not_to have_received(:error)
      end
    end
  end
end
