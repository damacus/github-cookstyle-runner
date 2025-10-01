# frozen_string_literal: true
# typed: false

require 'pastel'
require 'logger'
require_relative '../cookstyle_runner'
require_relative 'version'

module CookstyleRunner
  # Custom exception for CLI argument errors
  class CLIArgumentError < StandardError; end

  # Command Line Interface for Cookstyle Runner
  # Provides user-friendly commands for running Cookstyle operations
  # rubocop:disable Metrics/ClassLength
  class CLI
    # Regex pattern for validating positive integers
    POSITIVE_INTEGER_PATTERN = /^\d+$/

    attr_reader :pastel, :command, :options

    def initialize(argv = ARGV)
      @pastel = Pastel.new
      @argv = argv
      @command = parse_command
      @options = parse_options
    end

    # rubocop:disable Metrics/MethodLength
    def run
      case @command
      when 'run'
        run_command
      when 'list'
        list_command
      when 'config'
        config_command
      when 'status'
        status_command
      when 'version'
        version_command
      when 'help', nil
        help_command
      else
        puts pastel.red("Unknown command: #{@command}")
        puts "Run 'cookstyle-runner help' for usage information"
        1
      end
    rescue CLIArgumentError => e
      puts pastel.red(e.message)
      1
    rescue StandardError => e
      handle_error(e)
      1
    end
    # rubocop:enable Metrics/MethodLength

    private

    def parse_command
      @argv.first unless @argv.empty? || @argv.first.start_with?('-')
    end

    # rubocop:disable Metrics/MethodLength
    def parse_options
      opts = {}
      i = @command ? 1 : 0

      while i < @argv.length
        arg = @argv[i]
        case arg
        when '--verbose', '-v'
          opts[:verbose] = true
        when '--quiet', '-q'
          opts[:quiet] = true
        when '--dry-run', '-n'
          opts[:dry_run] = true
        when '--force', '-f'
          opts[:force] = true
        when '--no-cache'
          opts[:no_cache] = true
        when '--threads', '-t'
          validate_argument_present(i, '--threads', 'a numeric argument')
          thread_val = @argv[i + 1]
          validate_positive_integer(thread_val, '--threads')
          opts[:threads] = thread_val.to_i
          i += 1
        when '--format'
          validate_argument_present(i, '--format', 'an argument')
          opts[:format] = @argv[i + 1]
          i += 1
        when '--validate', '-V'
          opts[:validate] = true
        when '--log-level'
          validate_argument_present(i, '--log-level', 'an argument')
          opts[:log_level] = @argv[i + 1]
          i += 1
        when '--help', '-h'
          opts[:help] = true
        else
          opts[:repos] ||= []
          opts[:repos] << arg unless arg.start_with?('-')
        end
        i += 1
      end

      opts
    end
    # rubocop:enable Metrics/MethodLength

    # rubocop:disable Metrics/MethodLength
    def run_command
      setup_environment

      if options[:help]
        show_run_help
        return 0
      end

      puts pastel.yellow('Dry run mode - no changes will be made') if options[:dry_run]

      apply_cli_options

      repos = options[:repos] || []
      unless repos.empty?
        ENV['GCR_FILTER_REPOS'] = repos.join(',')
        puts pastel.cyan("Running on specific repositories: #{repos.join(', ')}")
      end

      app = Application.new
      exit_code = app.run

      if exit_code.zero?
        puts pastel.green("\n✓ Cookstyle run completed successfully")
      else
        puts pastel.red("\n✗ Cookstyle run completed with errors")
      end

      exit_code
    end
    # rubocop:enable Metrics/MethodLength

    def list_command
      setup_environment

      if options[:help]
        show_list_help
        return 0
      end

      puts pastel.cyan('Fetching repositories...')

      app = Application.new
      repositories = fetch_repositories(app)

      if repositories.empty?
        puts pastel.yellow('No repositories found matching criteria')
        return 0
      end

      display_repositories(repositories, options[:format] || 'table')
      0
    end

    def config_command
      setup_environment

      if options[:help]
        show_config_help
        return 0
      end

      if options[:validate]
        validate_configuration
      else
        display_configuration
      end
    end

    def version_command
      puts pastel.cyan("Cookstyle Runner v#{CookstyleRunner::VERSION}")
      puts pastel.cyan("Ruby v#{RUBY_VERSION}")
      0
    end

    def status_command
      setup_environment

      if options[:help]
        show_status_help
        return 0
      end

      puts pastel.cyan('Cache Status:')
      display_cache_status
      0
    end

    def setup_environment
      if options[:verbose]
        ENV['GCR_LOG_LEVEL'] = 'DEBUG'
      elsif options[:quiet]
        ENV['GCR_LOG_LEVEL'] = 'ERROR'
      elsif options[:log_level]
        ENV['GCR_LOG_LEVEL'] = options[:log_level].upcase
      end
    end

    def apply_cli_options
      ENV['GCR_FORCE_REFRESH'] = 'true' if options[:force]
      ENV['GCR_USE_CACHE'] = 'false' if options[:no_cache]
      ENV['GCR_THREAD_COUNT'] = options[:threads].to_s if options[:threads]
      ENV['GCR_CREATE_MANUAL_FIX_ISSUES'] = options[:create_issues].to_s if options.key?(:create_issues)
    end

    # Validates that an argument is present and not a flag
    def validate_argument_present(index, flag_name, description)
      if index + 1 >= @argv.length || @argv[index + 1].start_with?('-')
        raise CLIArgumentError, "Error: #{flag_name} requires #{description}"
      end
    end

    # Validates that a value is a positive integer
    def validate_positive_integer(value, flag_name)
      return if value.match?(POSITIVE_INTEGER_PATTERN)

      raise CLIArgumentError, "Error: #{flag_name} value must be a positive integer"
    end

    def fetch_repositories(app)
      # Use the public API to fetch repositories
      app.fetch_and_filter_repositories
    end

    def display_repositories(repositories, format)
      case format
      when 'json'
        require 'json'
        puts JSON.pretty_generate(repositories: repositories)
      when 'table'
        puts pastel.green("\nFound #{repositories.length} repositories:")
        repositories.each_with_index do |repo, index|
          repo_name = File.basename(repo, '.git')
          puts "  #{index + 1}. #{repo_name}"
        end
      end
    end

    # rubocop:disable Metrics/MethodLength
    def display_configuration
      app = Application.new
      config = app.configuration

      puts pastel.cyan("\nCookstyle Runner Configuration:")
      puts pastel.cyan('─' * 50)

      display_config_section('GitHub Settings', {
                               'Owner' => config.owner,
                               'API Endpoint' => config.github_api_endpoint,
                               'Topics' => config.topics&.join(', ') || 'none',
                               'Filter Repos' => config.filter_repos&.join(', ') || 'none'
                             })

      display_config_section('Processing Settings', {
                               'Thread Count' => config.thread_count,
                               'Retry Count' => config.retry_count,
                               'Create Manual Fix Issues' => config.create_manual_fix_issues
                             })

      display_config_section('Cache Settings', {
                               'Cache Enabled' => config.use_cache,
                               'Cache Directory' => config.cache_dir,
                               'Cache Max Age (days)' => config.cache_max_age,
                               'Force Refresh' => config.force_refresh
                             })

      display_config_section('Git Settings', {
                               'Branch Name' => config.branch_name,
                               'Default Branch' => config.default_branch,
                               'Git Name' => config.git_name,
                               'Git Email' => config.git_email,
                               'PR Title' => config.pr_title
                             })

      0
    end
    # rubocop:enable Metrics/MethodLength

    def display_config_section(title, settings)
      puts pastel.yellow("\n#{title}:")
      settings.each do |key, value|
        puts "  #{key.ljust(30)}: #{value}"
      end
    end

    def validate_configuration
      puts pastel.cyan('Validating configuration...')

      Application.new

      puts pastel.green('✓ Configuration is valid')
      0
    rescue ArgumentError => e
      puts pastel.red('✗ Configuration validation failed:')
      puts pastel.red("  #{e.message}")
      1
    end

    def display_cache_status
      require_relative 'cache'

      # Settings constant is dynamically loaded via config gem
      settings = Object.const_get('Settings')
      cache = Cache.new(settings.cache_dir, Logger.new($stdout))

      if cache.stats
        stats = cache.stats.runtime_stats
        puts "  Cache Directory: #{settings.cache_dir}"
        puts pastel.green("  Hits: #{stats[:hits]}")
        puts pastel.yellow("  Misses: #{stats[:misses]}")
        puts pastel.cyan("  Stores: #{stats[:stores]}")
        hit_rate = stats[:hit_rate].to_i
        color = hit_rate > 50 ? :green : :yellow
        puts pastel.decorate("  Hit Rate: #{hit_rate}%", color)
      else
        puts pastel.yellow('  No cache statistics available')
      end
    end

    def handle_error(error)
      puts pastel.red("\nError: #{error.message}")

      if options[:verbose]
        puts pastel.red("\nBacktrace:")
        error.backtrace.each { |line| puts pastel.red("  #{line}") }
      else
        puts pastel.yellow('Run with --verbose for more details')
      end
    end

    # rubocop:disable Metrics/MethodLength
    def help_command
      puts pastel.cyan("\nCookstyle Runner v#{CookstyleRunner::VERSION}")
      puts pastel.cyan("\nUsage: cookstyle-runner [COMMAND] [OPTIONS]")
      puts "\nCommands:"
      puts '  run [REPOS...]    Run Cookstyle on repositories'
      puts '  list              List repositories that would be processed'
      puts '  config            Display or validate configuration'
      puts '  status            Show cache and operation status'
      puts '  version           Display version information'
      puts '  help              Show this help message'
      puts "\nGlobal Options:"
      puts '  -v, --verbose     Enable verbose output'
      puts '  -q, --quiet       Suppress non-essential output'
      puts '  --log-level LEVEL Set log level (DEBUG, INFO, WARN, ERROR)'
      puts '  -h, --help        Show help for a command'
      puts "\nRun 'cookstyle-runner COMMAND --help' for more information on a command."
      0
    end
    # rubocop:enable Metrics/MethodLength

    def show_run_help
      puts pastel.cyan("\nUsage: cookstyle-runner run [REPOS...] [OPTIONS]")
      puts "\nRun Cookstyle on specified repositories or all configured repositories."
      puts "\nOptions:"
      puts '  -n, --dry-run     Preview repositories without running Cookstyle'
      puts '  -f, --force       Force cache refresh'
      puts '  -t, --threads N   Number of parallel threads'
      puts '  --no-cache        Disable cache for this run'
      puts "\nExamples:"
      puts '  cookstyle-runner run'
      puts '  cookstyle-runner run repo1 repo2'
      puts '  cookstyle-runner run --dry-run'
      puts '  cookstyle-runner run --force --threads 8'
    end

    def show_list_help
      puts pastel.cyan("\nUsage: cookstyle-runner list [OPTIONS]")
      puts "\nList repositories that match the current configuration."
      puts "\nOptions:"
      puts '  --format FORMAT   Output format (table, json)'
      puts "\nExamples:"
      puts '  cookstyle-runner list'
      puts '  cookstyle-runner list --format json'
    end

    def show_config_help
      puts pastel.cyan("\nUsage: cookstyle-runner config [OPTIONS]")
      puts "\nDisplay or validate configuration settings."
      puts "\nOptions:"
      puts '  -V, --validate    Validate configuration only'
      puts '  --format FORMAT   Output format (table, json)'
      puts "\nExamples:"
      puts '  cookstyle-runner config'
      puts '  cookstyle-runner config --validate'
    end

    def show_status_help
      puts pastel.cyan("\nUsage: cookstyle-runner status")
      puts "\nShow cache status and recent operations."
      puts "\nExamples:"
      puts '  cookstyle-runner status'
    end
  end
  # rubocop:enable Metrics/ClassLength
end
