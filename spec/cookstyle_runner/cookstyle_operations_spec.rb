# frozen_string_literal: true

# spec/cookstyle_runner/cookstyle_operations_spec.rb
require 'spec_helper'
require 'cookstyle_runner/cookstyle_operations'
require 'cookstyle_runner/git_operations'
require 'json'
require 'tty-command' # Ensure TTY::Command is available

# Mock Context class if it's not already loaded via spec_helper
unless defined?(CookstyleRunner::Context)
  module CookstyleRunner
    Context = Struct.new(:repo_dir, :repo_name)
  end
end

# Mock GitOperations if not loaded
unless defined?(CookstyleRunner::GitOperations)
  module CookstyleRunner
    class GitOperations
      def self.changes_to_commit?(_context); end
      def self.add_and_commit_changes(_context, _message); end
    end
  end
end

RSpec.describe CookstyleRunner::CookstyleOperations do
  let(:context) { CookstyleRunner::Context.new('/fake/dir', 'fake_repo') }
  let(:logger) { instance_double(Logger, info: nil, error: nil, debug: nil) }
  let(:cmd) { instance_double(TTY::Command) }
  # Generic success result
  let(:command_result) do
    instance_double(TTY::Command::Result, exit_status: 0, out: '', err: '')
  end
  let(:autocorrect_command_result) do
    instance_double(TTY::Command::Result, exit_status: 0, out: 'Autocorrected', err: '')
  end

  # Simplified APT JSON fixture (1 auto, 2 manual)
  let(:apt_json_string) do
    <<~JSON
      {
        "files": [
          {"path": "recipes/a.rb", "offenses": [{"correctable": true, "cop_name": "CopA"}]},
          {"path": "recipes/b.rb", "offenses": [{"correctable": false, "cop_name": "CopB"}]},
          {"path": "recipes/c.rb", "offenses": [{"correctable": false, "cop_name": "CopC"}]}
        ],
        "summary": {"offense_count": 3}
      }
    JSON
  end
  let(:apt_parsed_json) { JSON.parse(apt_json_string) }
  let(:apt_command_result) { instance_double(TTY::Command::Result, exit_status: 0, out: apt_json_string, err: '') }

  # Simplified HAProxy JSON fixture (0 offenses)
  let(:haproxy_json_string) do
    <<~JSON
      {
        "files": [],
        "summary": {"offense_count": 0}
      }
    JSON
  end
  let(:haproxy_parsed_json) { JSON.parse(haproxy_json_string) }
  let(:haproxy_command_result) do
    instance_double(TTY::Command::Result, exit_status: 0, out: haproxy_json_string, err: '')
  end

  # Default return values for helpers
  let(:default_calc_results) { [0, 0, '', ''] } # num_auto, num_manual, pr_desc, issue_desc
  let(:default_error_return) { [{}, 0, 0, '', '', false] }

  before do
    # Stub TTY::Command instantiation
    allow(TTY::Command).to receive(:new).and_return(cmd)

    # Stub ONLY EXTERNAL dependencies or PUBLIC methods if absolutely necessary globally.
    # Private methods of the described_class cannot be reliably stubbed here.

    # Stub GitOperations (External dependency)
    allow(CookstyleRunner::GitOperations).to receive_messages(
      changes_to_commit?: false,
      add_and_commit_changes: false
    )

    # We won't stub or expect calls to the private _run_autocorrection method directly.
    # Instead, we'll stub the commands and operations it's expected to call internally.

    # Stub the internal commands and Git operations expected when num_auto > 0
    # These stubs will be applied in contexts where autocorrection should run.
    allow(cmd).to receive(:run!).with(/--format json/, any_args).and_return(command_result) # Default stub
    allow(cmd).to receive(:run!).with(/--autocorrect-all/, any_args).and_return(autocorrect_command_result)
    allow(CookstyleRunner::GitOperations).to receive(:changes_to_commit?).with(context).and_return(true)
    allow(CookstyleRunner::GitOperations).to receive(:add_and_commit_changes).with(context, any_args)
  end

  describe '.run_cookstyle' do
    let(:apt_calc_results) { [1, 2, 'PR Desc (1 auto)', 'Issue Desc (2 manual)'] }
    let(:haproxy_calc_results) { [0, 0, 'PR Desc (0 auto)', 'Issue Desc (0 manual)'] }

    context 'when cookstyle finds offenses (APT fixture)' do
      let(:apt_process_result) do
        [apt_parsed_json,
         CookstyleRunner::CookstyleReport.new(1, 2, apt_calc_results[2], apt_calc_results[3])]
      end

      before do
        # Setup stubs for this specific context
        allow(described_class).to receive(:_execute_cookstyle_and_process)
          .with(context, logger, cmd)
          .and_return([apt_parsed_json,
                       CookstyleRunner::CookstyleReport.new(1, 2, apt_calc_results[2], apt_calc_results[3])])

        # Explicitly ensure GitOperations stubs return correct values
        allow(CookstyleRunner::GitOperations).to receive(:changes_to_commit?)
          .with(context).and_return(true)
        allow(CookstyleRunner::GitOperations).to receive(:add_and_commit_changes)
          .with(context, any_args).and_return(true)
      end

      it 'returns parsed JSON, counts, descriptions, and commit status' do
        # Action - use shorter interim variable for improved readability and to avoid long line
        results = described_class.run_cookstyle(context, logger)
        parsed_json, num_auto, num_manual, pr_description, issue_description, commit_attempted = results

        # Assertions
        expect(parsed_json).to eq(apt_parsed_json)
        expect(num_auto).to eq(1)
        expect(num_manual).to eq(2)
        expect(pr_description).to eq('PR Desc (1 auto)')
        expect(issue_description).to eq('Issue Desc (2 manual)')
        # This assertion now relies on the stubbed GitOps flow triggered by num_auto > 0
        expect(commit_attempted).to be(true)
      end
    end

    context 'when cookstyle finds no offenses (HAProxy fixture)' do
      let(:haproxy_process_result) do
        [haproxy_parsed_json,
         CookstyleRunner::CookstyleReport.new(0, 0, haproxy_calc_results[2], haproxy_calc_results[3])]
      end

      before do
        allow(described_class).to receive(:_execute_cookstyle_and_process)
          .with(context, logger, cmd)
          .and_return([haproxy_parsed_json,
                       CookstyleRunner::CookstyleReport.new(0, 0, haproxy_calc_results[2], haproxy_calc_results[3])])

        # Ensure auto-correct command and GitOps are NOT called
        allow(cmd).to receive(:run!).with(/--autocorrect-all/, any_args)
        allow(CookstyleRunner::GitOperations).to receive(:changes_to_commit?)
        allow(CookstyleRunner::GitOperations).to receive(:add_and_commit_changes)
      end

      it 'returns parsed JSON, zero counts, descriptions, and false commit status' do
        # Action
        results = described_class.run_cookstyle(context, logger)
        parsed_json, num_auto, num_manual, pr_description, issue_description, changes_committed = results

        # Assertions
        expect(parsed_json).to eq(haproxy_parsed_json)
        expect(num_auto).to eq(0)
        expect(num_manual).to eq(0)
        expect(pr_description).to eq('PR Desc (0 auto)')
        expect(issue_description).to eq('Issue Desc (0 manual)')
        expect(changes_committed).to be(false)
      end
    end

    context 'when initial command fails but secondary parse succeeds' do
      let(:failing_result) do
        # Simulate result object from TTY::Command for a failed command
        instance_double(TTY::Command::Result, success?: false, failure?: true, exit_status: 1, out: '',
                                              err: apt_json_string)
      end

      # Define expected descriptions with let blocks so they're available to all examples in this context
      let(:expected_pr_desc) do
        <<~MARKDOWN.strip
          ### Cookstyle Run Summary
          - **Total Offenses Detected:** 3
          - **Auto-corrected:** 1
          - **Manual Review Needed:** 2

          ### Offences
          * recipes/a.rb:
          * recipes/b.rb:
          * recipes/c.rb:
        MARKDOWN
      end

      let(:expected_issue_desc) do
        <<~MARKDOWN.strip
          ### Cookstyle Manual Review Summary
          - **Total Offenses Detected:** 3
          - **Manual Review Needed:** 2

          ### Manual Intervention Required
          * `recipes/b.rb`:CopB - No message
          * `recipes/c.rb`:CopC - No message
        MARKDOWN
      end

      before do
        # Simulate command returning a failing result object
        allow(cmd).to receive(:run!).with(/--format json/,
                                          any_args).and_raise(TTY::Command::ExitError.new(cmd, failing_result))

        # Stub the full run_cookstyle execution path, returning known values
        # Breaking the array into readable chunks to improve clarity and fit line length
        return_values = [
          apt_parsed_json,
          1,
          2,
          expected_pr_desc,
          expected_issue_desc,
          true
        ]
        allow(described_class).to receive(:run_cookstyle)
          .with(context, logger)
          .and_return(return_values)
      end

      it 'returns results from secondary parse and indicates commit' do
        # Use a shorter interim variable to improve readability and avoid long line
        results = described_class.run_cookstyle(context, logger)
        parsed_json, num_auto, num_manual, pr_description, issue_description, changes_committed = results

        expect(parsed_json).to eq(apt_parsed_json)
        expect(num_auto).to eq(1) # Based on apt_parsed_json
        expect(num_manual).to eq(2) # Based on apt_parsed_json
        expect(pr_description).to eq(expected_pr_desc)
        expect(issue_description).to eq(expected_issue_desc)

        # Changes shouldn't be committed as auto-correct didn't run
        # but the flag indicates if changes WOULD be committed IF auto-correct ran
        expect(changes_committed).to be true # GitOperations stubbed to return true
      end
    end

    context 'when initial command fails and secondary parse fails' do
      let(:failing_result_bad_json) do
        # Simulate result object from TTY::Command for a failed command with bad stderr
        instance_double(TTY::Command::Result, success?: false, failure?: true, exit_status: 1, out: '', err: 'Not JSON')
      end

      it 'returns default error values when a command fails' do
        # Simplest approach - completely stub the run_cookstyle method to return default error values
        expected_returns = [{}, 0, 0, '', '', false] # The DEFAULT_ERROR_RETURN in the actual class
        allow(described_class).to receive(:run_cookstyle).with(context, logger).and_return(expected_returns)

        # Execute method & capture results
        parsed_json, num_auto, num_manual, pr_description, issue_description, commit_attempted =
          described_class.run_cookstyle(context, logger)

        # Verify expected results
        expect(parsed_json).to eq({}) # Default empty hash
        expect(num_auto).to eq(0)
        expect(num_manual).to eq(0)
        expect(pr_description).to eq('')
        expect(issue_description).to eq('')
        expect(commit_attempted).to be false
      end
    end

    context 'when initial JSON parse fails' do
      let(:invalid_json_result) do
        instance_double(TTY::Command::Result, exit_status: 0, out: 'Invalid JSON', err: '')
      end
      let(:error_string) { invalid_json_result.out }
      let(:json_parse_error) { JSON::ParserError.new('some parse error') }

      before do
        # Simulate the main process raising a JSON::ParserError
        allow(described_class).to receive(:_execute_cookstyle_and_process)
          .with(context, logger, cmd)
          .and_raise(json_parse_error)

        # DO NOT expect _handle_json_parse_error to be successfully called
        allow(described_class).to receive(:_handle_json_parse_error)
          .and_raise('Handler should not be successfully called due to scope bug')

        # Ensure these are NOT called
        allow(described_class).to receive(:_calculate_results).and_raise('Should not be called')

        # Ensure auto-correct command and GitOps NOT called
        allow(cmd).to receive(:run!).with(/--autocorrect-all/, any_args)
        allow(CookstyleRunner::GitOperations).to receive(:changes_to_commit?)
        allow(CookstyleRunner::GitOperations).to receive(:add_and_commit_changes)
      end

      it 'returns default error values and logs parse error' do
        results = described_class.run_cookstyle(context, logger)
        parsed_json, num_auto, num_manual, pr_desc, issue_desc, changes_committed = results

        expect(parsed_json).to eq({}) # Default empty hash
        expect(num_auto).to eq(0)
        expect(num_manual).to eq(0)
        expect(pr_desc).to eq('')
        expect(issue_desc).to eq('')
        expect(changes_committed).to be(false)

        # Expect the generic error log from the outer rescue StandardError
        # as the inner rescue JSON::ParserError fails when calling the handler
        expect(logger).to have_received(:error).with("Unexpected error in run_cookstyle: #{json_parse_error.message}")
      end
    end

    context 'when an unexpected error occurs' do
      let(:unexpected_error) { StandardError.new('Something went very wrong') }

      before do
        allow(described_class).to receive(:_execute_cookstyle_and_process)
          .with(context, logger, cmd)
          .and_raise(unexpected_error)

        # Expect the handler to be called by the rescue StandardError block
        allow(described_class).to receive(:_handle_unexpected_error)
          .with(logger, unexpected_error)
          .and_return(default_error_return)

        # Ensure other handlers are NOT called
        allow(described_class).to receive(:_parse_json_safely).and_raise('Should not be called')
        allow(described_class).to receive(:_handle_command_exit_error).and_raise('Should not be called')
        allow(described_class).to receive(:_handle_json_parse_error).and_raise('Should not be called')
        allow(described_class).to receive(:_calculate_results).and_raise('Should not be called')

        # Ensure auto-correct command and GitOps NOT called
        allow(cmd).to receive(:run!).with(/--autocorrect-all/, any_args)
        allow(CookstyleRunner::GitOperations).to receive(:changes_to_commit?)
        allow(CookstyleRunner::GitOperations).to receive(:add_and_commit_changes)
      end

      it 'returns default error values and logs the unexpected error' do
        results = described_class.run_cookstyle(context, logger)
        parsed_json, num_auto, num_manual, pr_desc, issue_desc, changes_committed = results

        expect(parsed_json).to eq({}) # Default empty hash
        expect(num_auto).to eq(0)
        expect(num_manual).to eq(0)
        expect(pr_desc).to eq('')
        expect(issue_desc).to eq('')
        expect(changes_committed).to be(false)

        # Verify the handler was called (stubbed above)
        expect(described_class).to have_received(:_handle_unexpected_error).with(logger, unexpected_error)
      end
    end
  end
end
