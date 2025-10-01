# frozen_string_literal: true

namespace :sorbet do
  desc 'Run Sorbet typechecking'
  task :typecheck do
    puts 'Running Sorbet type checks...'
    sh 'bundle exec srb tc'
  end

  desc 'Run Tapioca to sync gem RBIs'
  task :sync do
    puts 'Syncing gem RBIs with Tapioca...'
    sh 'bundle exec tapioca sync'
  end

  desc 'Generate RBIs for DSLs'
  task :dsl do
    puts 'Generating RBIs for DSLs...'
    sh 'bundle exec tapioca dsl'
  end

  desc 'Check todo.rbi file for unresolved constants'
  task :todo do
    puts 'Checking todo.rbi file for unresolved constants...'
    sh 'bundle exec tapioca todo'
  end

  desc 'Run all Sorbet tasks in sequence'
  task all: %i[sync dsl todo typecheck]
end

# Add Sorbet to standard test suite
task test: 'sorbet:typecheck'
