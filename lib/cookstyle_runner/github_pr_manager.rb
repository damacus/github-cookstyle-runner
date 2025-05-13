# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module CookstyleRunner
  # Stub for GitHub PR Manager to satisfy dependency requirements
  # This will be properly implemented in a future update
  class GitHubPRManager
    extend T::Sig

    sig { params(logger: T.untyped).void }
    def initialize(logger)
      @logger = logger
    end

    sig { params(repository: String, branch: String, title: String, body: String).returns(T::Boolean) }
    def create_pull_request(repository, _branch, title, _body)
      @logger.info("Stub PR Manager: Would create PR for #{repository} with title: #{title}")
      true
    end

    sig { params(repository: String, title: String, body: String).returns(T::Boolean) }
    def create_issue(repository, title, _body)
      @logger.info("Stub PR Manager: Would create issue for #{repository} with title: #{title}")
      true
    end
  end
end
