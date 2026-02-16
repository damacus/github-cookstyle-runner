# typed: false
# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Forbidden Sorbet types' do
  it 'does not use forbidden Sorbet escape hatches in production Ruby files' do
    project_root = File.expand_path('../..', __dir__)
    ruby_files = Dir.glob(File.join(project_root, '{lib,config}/**/*.rb'))
    forbidden_types = %w[untyped unsafe].freeze

    offenses = ruby_files.each_with_object([]) do |path, memo|
      File.readlines(path, chomp: true).each_with_index do |line, index|
        next unless forbidden_types.any? { |type_name| line.match?(Regexp.new("T\\.#{type_name}\\b")) }

        memo << "#{path}:#{index + 1}: #{line.strip}"
      end
    end

    expect(offenses).to be_empty, "Found forbidden Sorbet types:\n#{offenses.join("\n")}"
  end
end

# rubocop:enable RSpec/DescribeClass
