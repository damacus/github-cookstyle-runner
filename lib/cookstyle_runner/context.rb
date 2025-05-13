# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

module CookstyleRunner
  # Context object
  class Context
    extend T::Sig
    attr_reader :repo_name, :owner, :logger, :repo_dir, :repo_url, :github_token, :app_id, :installation_id, :private_key

    sig do
      params(
        repo_name: String,
        owner: String,
        logger: Logger,
        repo_dir: T.nilable(String),
        repo_url: T.nilable(String),
        github_token: T.nilable(String),
        app_id: T.nilable(String),
        installation_id: T.nilable(Integer),
        private_key: T.nilable(String)
      ).void
    end
    def initialize(repo_name:, owner:, logger:, repo_dir: nil, repo_url: nil, github_token: nil, app_id: nil, installation_id: nil, private_key: nil)
      @repo_name = repo_name
      @owner = owner
      @logger = logger
      @repo_dir = repo_dir
      @repo_url = repo_url
      @github_token = github_token
      @app_id = app_id
      @installation_id = installation_id
      @private_key = private_key
    end
  end
end
