# typed: false
# frozen_string_literal: true

require 'bundler/setup'

require 'rake'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# Standard RSpec task
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.rspec_opts = '--color --format progress'
end

# RuboCop task
RuboCop::RakeTask.new(:rubocop) do |task|
  task.fail_on_error = true
  task.options = ['--display-cop-names']
end

# Sorbet static type checking task
desc 'Run Sorbet static type checking'
task :sorbet do
  puts 'Running Sorbet type checker...'
  sh 'bundle exec srb tc'
end

# Default task: run tests, linting, and type checking
desc 'Run all default checks: RuboCop, RSpec, and Sorbet'
task default: %i[rubocop spec sorbet]

# Alias 'test' to run the default tasks
desc 'Alias for default checks (RuboCop, RSpec, Sorbet)'
task test: :default

# Yard documentation task (if yard is available)
begin
  require 'yard/rake/yardoc_task'
  YARD::Rake::YardocTask.new do |t|
    t.files   = ['lib/**/*.rb']
    t.options = ['--output-dir', 'doc', '--readme', 'README.md']
  end
rescue LoadError
  desc 'Generate YARD documentation (YARD gem not found)'
  task :yard do
    warn 'YARD gem not found. Skipping documentation generation.'
  end
end
