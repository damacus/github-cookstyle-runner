# typed: true
# frozen_string_literal: true

# This file is an RBI (Ruby Interface) file for Sorbet static type checking.
# It provides type signatures for the CookstyleRunner::Git::RepoContext class.
# DO NOT put implementation code here. For more information, see:
# https://sorbet.org/docs/rbi

# Context object for git operations.
#
# @!attribute [r] owner
#   @return [String] the GitHub owner (user or org)
# @!attribute [r] logger
#   @return [Object] logger instance (accepts T.untyped for test doubles)
# @!attribute [r] repo_url
#   @return [String] the repository URL
# @!attribute [r] repo_dir
#   @return [String] the local directory for the repo
# @!attribute [r] github_token
#   @return [String, nil] GitHub token for authentication
# @!attribute [r] app_id
#   @return [String, nil] GitHub App ID (if using App auth)
# @!attribute [r] installation_id
#   @return [Integer, nil] GitHub App installation ID
# @!attribute [r] private_key
#   @return [String, nil] GitHub App private key
class CookstyleRunner::Git::RepoContext
  # Repository name accessor
  sig { returns(String) }
  def repo_name; end

  # Repository owner accessor
  sig { returns(String) }
  def owner; end

  # Logger accessor (accepts T.untyped for test doubles)
  sig { returns(T.untyped) }
  def logger; end

  # Repository URL accessor
  sig { returns(String) }
  def repo_url; end

  # Repository directory accessor 
  sig { returns(String) }
  def repo_dir; end

  # GitHub token accessor
  sig { returns(T.nilable(String)) }
  def github_token; end

  # GitHub App ID accessor
  sig { returns(T.nilable(String)) }
  def app_id; end

  # GitHub App installation ID accessor
  sig { returns(T.nilable(Integer)) }
  def installation_id; end

  # GitHub App private key accessor
  sig { returns(T.nilable(String)) }
  def private_key; end

  # Initialize a repository context with either token or GitHub App authentication
  # @param repo_name [String] Repository name
  # @param owner [String] Repository owner
  # @param logger [Object] Logger instance
  # @param base_dir [String] Base directory (default: Dir.pwd)
  # @param repo_dir [String, nil] Repository directory (optional)
  # @param repo_url [String, nil] Repository URL (optional)
  # @param github_token [String, nil] GitHub token (optional)
  # @param app_id [String, nil] GitHub App ID (optional)
  # @param installation_id [Integer, nil] GitHub App installation ID (optional)
  # @param private_key [String, nil] GitHub App private key (optional)
  sig do
    params(
      repo_name: String,
      owner: String,
      logger: T.untyped,
      base_dir: String,
      repo_dir: T.nilable(String),
      repo_url: T.nilable(String),
      github_token: T.nilable(String),
      app_id: T.nilable(String),
      installation_id: T.nilable(Integer),
      private_key: T.nilable(String)
    ).void
  end
  def initialize(
    repo_name:,
    owner:,
    logger:,
    base_dir: Dir.pwd,
    repo_dir: nil,
    repo_url: nil,
    github_token: nil,
    app_id: nil,
    installation_id: nil,
    private_key: nil
  ); end
end
