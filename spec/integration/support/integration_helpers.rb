# frozen_string_literal: true

module IntegrationHelpers
  # Real sous-chefs repositories for integration testing
  TEST_REPOS = {
    clean: 'sous-chefs/sc_vscode',      # Clean repo (no offenses)
    simple: 'sous-chefs/apt',           # Simple with known offenses
    complex: 'sous-chefs/apache2',      # Complex/large cookbook
    large: 'sous-chefs/apache2'         # Same as complex for now
  }.freeze

  # Run the cookstyle-runner CLI with given options
  # @param args [Hash] Options to pass to the runner
  # @return [CommandResult] Result object with exit_code, stdout, stderr
  def run_cookstyle_runner(args = {})
    cmd_args = build_command_args(args)

    stdout, stderr, status = Open3.capture3(
      { 'ENVIRONMENT' => 'test' },
      'bundle', 'exec', 'bin/cookstyle-runner', *cmd_args
    )

    CommandResult.new(
      exit_code: status.exitstatus,
      stdout: stdout,
      stderr: stderr,
      args: args
    )
  end

  # Parse cache statistics from runner output
  # @param output [String]
  # @return [Hash{Symbol=>Integer}]
  def extract_cache_stats(output)
    stats = {}

    output.each_line do |line|
      clean_line = strip_ansi(line)
      next unless clean_line.include?(':')

      key, value = clean_line.split(':', 2).map(&:strip)
      next unless key && value

      normalized_key = key.downcase.gsub(' ', '_').to_sym

      if normalized_key == :cache_directory
        stats[normalized_key] = value
      elsif numeric_value?(value)
        stats[normalized_key] = parse_numeric(value)
      end
    end

    stats
  end

  def extract_cache_directory(output)
    output.each_line do |line|
      clean_line = strip_ansi(line)
      next unless clean_line.start_with?('  Cache Directory:')

      return clean_line.split(':', 2)[1]&.strip
    end

    nil
  end

  def numeric_value?(value)
    value.match?(/\A\d+(\.\d+)?%?\z/)
  end

  def parse_numeric(value)
    numeric = value.delete('%')
    numeric.include?('.') ? numeric.to_f : numeric.to_i
  end

  def strip_ansi(text)
    text.gsub(/\e\[[\d;]*m/, '')
  end

  # Build command line arguments from hash
  def build_command_args(args)
    cmd = [args[:command] || 'run']

    cmd << '--dry-run' if args[:dry_run]
    cmd << '--force' if args[:force]
    cmd << '--no-cache' if args[:no_cache]
    cmd << '--threads' << args[:threads].to_s if args[:threads]
    cmd << '--verbose' if args[:verbose]

    # Add repository arguments
    Array(args[:repos]).each { |repo| cmd << repo }

    cmd
  end

  # Run the CLI and assert success, returning the result for additional checks
  # @param command [String]
  # @param args [Hash]
  def expect_successful_run(command:, **args)
    result = run_cookstyle_runner({ command: command }.merge(args))

    aggregate_failures do
      expect(result).to be_success
      expect(result.stderr).to be_empty
    end

    result
  end

  # Set up temporary git configuration for tests
  def with_temp_git_config
    # Get original git config using Open3 for proper error handling
    original_name, = Open3.capture3('git', 'config', '--global', 'user.name')
    original_name = original_name.strip
    original_email, = Open3.capture3('git', 'config', '--global', 'user.email')
    original_email = original_email.strip

    system('git', 'config', '--global', 'user.name', 'Test User')
    system('git', 'config', '--global', 'user.email', 'test@example.com')

    yield
  ensure
    # Restore original config if it was set (not empty)
    system('git', 'config', '--global', 'user.name', original_name) unless original_name.empty?
    system('git', 'config', '--global', 'user.email', original_email) unless original_email.empty?
  end

  # Clean up any test artifacts (branches, PRs, etc.)
  def cleanup_test_artifacts
    # TODO: Implement cleanup logic
    # - Delete test branches
    # - Close test PRs
    # - Delete test issues
  end

  # Result object for CLI command execution
  class CommandResult
    attr_reader :exit_code, :stdout, :stderr, :args

    def initialize(exit_code:, stdout:, stderr:, args:)
      @exit_code = exit_code
      @stdout = stdout
      @stderr = stderr
      @args = args
    end

    def success?
      exit_code.zero?
    end

    def output
      stdout + stderr
    end

    # Check if a PR was created (based on output)
    def created_pr?
      stdout.include?('Created pull request') || stdout.include?('PR created')
    end

    # Check if an issue was created
    def created_issue?
      stdout.include?('Created issue') || stdout.include?('Issue created')
    end

    # Extract PR number from output
    def pr_number
      stdout[/PR #(\d+)/, 1]&.to_i
    end

    # Extract issue number from output
    def issue_number
      stdout[/Issue #(\d+)/, 1]&.to_i
    end
  end
end
