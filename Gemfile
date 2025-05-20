# frozen_string_literal: true

source 'https://rubygems.org'

# Specify Ruby version from .ruby-version file
ruby File.read('.ruby-version').strip if File.exist?('.ruby-version')

gem 'config'
gem 'cookstyle'
gem 'git'
gem 'octokit'

# Type Checking
gem 'sorbet'
gem 'sorbet-runtime'
# Linting and Style (require: false as they are usually run via Rake/CLI)
gem 'rubocop', require: false
gem 'rubocop-performance', require: false
gem 'rubocop-rake', require: false
gem 'rubocop-rspec', require: false
gem 'rubocop-sorbet', require: false

group :development, :test do
  gem 'fakefs'
  gem 'guard'
  gem 'guard-rspec'
  gem 'guard-rubocop'
  gem 'pry'
  gem 'pry-byebug'
  gem 'rake'
  gem 'rspec'
  gem 'simplecov', require: false
  gem 'sorbet-struct-comparable'
  gem 'tapioca'
  gem 'webmock'
  gem 'yard'
end
