# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

# CookstyleRunner provides functionality for running Cookstyle, parsing its output,
# and creating GitHub pull requests for issues that can be automatically fixed
module CookstyleRunner
  # Module for formatting Cookstyle output
  module Format
    extend T::Sig

    sig do
      params(
        cookstyle_output: T::Hash[String, T.untyped] # Expects the full parsed JSON
      ).returns(
        T::Hash[String, T::Array[String]] # Returns Hash{file_path => [formatted_offense_string]}
      )
    end
    def self.offences(cookstyle_output)
      offences_by_file = {} # Initialize the result Hash

      # Early return if no files or not an array
      files = extract_files(cookstyle_output)
      return offences_by_file if files.empty?

      # Process each file
      files.each do |file_data|
        path, formatted_offenses = process_file(file_data)
        offences_by_file[path] = formatted_offenses unless formatted_offenses.empty?
      end

      offences_by_file
    end

    sig { params(cookstyle_output: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.extract_files(cookstyle_output)
      raw_files = cookstyle_output.fetch('files', [])
      return [] unless raw_files.is_a?(Array)

      T.let(raw_files, T::Array[T::Hash[String, T.untyped]])
    end

    sig do
      params(file_data: T::Hash[String, T.untyped])
        .returns([String, T::Array[String]])
    end
    def self.process_file(file_data)
      path = T.let(file_data.fetch('path', 'unknown_path'), String)
      offenses = T.let(file_data.fetch('offenses', []), T::Array[T::Hash[String, T.untyped]])

      formatted_offenses = offenses.map { |offense| format_offense(offense) }

      [path, formatted_offenses]
    end

    sig { params(offense: T::Hash[String, T.untyped]).returns(String) }
    def self.format_offense(offense)
      location_info = extract_location_info(offense)
      offense_details = extract_offense_details(offense)

      " - #{location_info} #{offense_details}"
    end

    sig { params(offense: T::Hash[String, T.untyped]).returns(String) }
    def self.extract_location_info(offense)
      location = T.let(offense.fetch('location', {}), T::Hash[String, T.untyped])
      line = T.let(location.fetch('line', '?'), T.any(String, Integer))
      column = T.let(location.fetch('column', '?'), T.any(String, Integer))

      "#{line}:#{column}"
    end

    sig { params(offense: T::Hash[String, T.untyped]).returns(String) }
    def self.extract_offense_details(offense)
      severity = T.let(offense.fetch('severity', 'unknown'), String)
      cop_name = T.let(offense.fetch('cop_name', 'UnknownCop'), String)
      message = T.let(offense.fetch('message', 'No message provided'), String)

      "#{severity}: `#{cop_name}` - #{message}"
    end

    private_class_method :extract_files, :process_file, :format_offense,
                         :extract_location_info, :extract_offense_details
  end
end
