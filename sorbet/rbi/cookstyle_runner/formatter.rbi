# frozen_string_literal: true
# typed: strict

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - Formatter
  # =============================================================================
  #
  # This module formats the results of Cookstyle checks into a structured format
  # for display in pull requests or issues.
  #
  module Formatter
    extend T::Sig

    sig { params(cookstyle_output: T::Hash[String, T.untyped]).returns(T::Hash[String, T::Array[String]]) }
    def self.offences(cookstyle_output); end

    sig { params(offense_details: T::Hash[String, T.untyped]).returns(String) }
    def self.format_pr_description(offense_details); end

    sig { params(offences: T::Hash[String, T.untyped]).returns(String) }
    def self.format_issue_description(offences); end

    sig { returns(String) }
    def self.issue_header; end

    sig { params(files: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(String) }
    def self.format_file_offenses(files); end

    sig { params(offences: T::Hash[String, T.untyped], manual_fixes: T::Boolean).returns(String) }
    def self.format_summary(offences, manual_fixes); end

    # Private methods - included in RBI for completeness

    sig { params(cookstyle_output: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.extract_files(cookstyle_output); end

    sig { params(file_data: T::Hash[String, T.untyped]).returns([String, T::Array[String]]) }
    def self.process_file(file_data); end

    sig { params(offense: T::Hash[String, T.untyped]).returns(String) }
    def self.format_offense(offense); end

    sig { params(offense: T::Hash[String, T.untyped]).returns(String) }
    def self.extract_location_info(offense); end

    sig { params(offense: T::Hash[String, T.untyped]).returns(String) }
    def self.extract_offense_details(offense); end
  end
end
