# frozen_string_literal: true

require 'rspec/core/rake_task'

# Load all task definitions
Dir.glob('lib/tasks/*.rake').each { |r| load r }

RSpec::Core::RakeTask.new(:spec)

desc 'Run RuboCop'
task :rubocop do
  sh 'bundle exec rubocop'
end

desc 'Run RuboCop with auto-corrections'
task :rubocop_autocorrect do
  sh 'bundle exec rubocop -a'
end

desc 'Run all code quality checks'
task quality: [:rubocop, 'sorbet:typecheck']

# Define default task
task default: %i[spec quality]
