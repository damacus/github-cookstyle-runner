# frozen_string_literal: true

source 'https://rubygems.org'

gem 'base64'
gem 'config'
gem 'cookstyle'
gem 'dry-schema'
gem 'faraday', '~> 2.0'
gem 'faraday-retry', '~> 2.0' # Specify v2 for Faraday v2 compatibility
gem 'git' # Required for local Git operations
gem 'json', '~> 2.6' # JSON parsing
gem 'jwt', '~> 3.0' # For GitHub App JWT generation
gem 'octokit', '~> 10.0' # GitHub API client
gem 'ostruct'
gem 'parallel', '~> 1.26' # Parallel processing
gem 'pastel', '~> 0.8' # Terminal colors
gem 'pp'
gem 'sorbet-runtime'
gem 'tty-command' # For running shell commands
gem 'tty-option', '~> 0.3' # CLI option parsing
gem 'tty-progressbar', '~> 0.18' # Progress indicators
gem 'tty-prompt', '~> 0.23' # Interactive prompts
gem 'tty-spinner', '~> 0.9' # Spinners for operations

group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rubocop'
  gem 'rubocop-rspec'
  gem 'sorbet'
  gem 'tapioca', require: false
  gem 'timecop'
  gem 'vcr', '~> 6.3' # Record and replay HTTP interactions
  gem 'webmock', '~> 3.25' # HTTP request stubbing
end
