# typed: false
# frozen_string_literal: true

# This file is an RBI (Ruby Interface) file for Sorbet static type checking.
# It provides type signatures for the CookstyleRunner::Git module.
# DO NOT put implementation code here. For more information, see:
# https://sorbet.org/docs/rbi

module CookstyleRunner
  # Module for Git operations.
  module Git
    # Type declarations for RepoContext class variables
    class RepoContext
      @repo_name = T.let(nil, String)
      @owner = T.let(nil, String)
      @logger = T.let(nil, T.untyped)
      @repo_url = T.let(nil, String)
      @repo_dir = T.let(nil, String)
      @github_token = T.let(nil, T.nilable(String))
      @app_id = T.let(nil, T.nilable(String))
      @installation_id = T.let(nil, T.nilable(Integer))
      @private_key = T.let(nil, T.nilable(String))
    end
    # Check if a git repository exists in the directory
    sig { params(context: RepoContext).returns(T::Boolean) }
    def self.repo_exists?(context); end

    # Create a new branch for cookstyle fixes using GitHub API
    # Deletes the existing branch if there is one
    sig { params(context: RepoContext, config: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.create_branch(context, config); end

    # Get the latest commit SHA for the repository
    sig { params(repo_dir: String).returns(T.nilable(String)) }
    def self.latest_commit_sha(repo_dir); end

    # Clone or update a repository to get the latest state
    sig { params(context: RepoContext, config: T::Hash[Symbol, T.untyped]).returns(T.nilable(::Git::Base)) }
    def self.clone_or_update_repo(context, config); end

    # Get authenticated URL for git operations based on auth method in context
    # Exits if authentication fails
    sig { params(context: RepoContext).returns(String) }
    def self.authenticated_url(context); end

    # Update the repository to the specified branch
    # Returns the repo object, or nil if an error occurs
    sig { params(context: RepoContext, branch: String).returns(T.nilable(::Git::Base)) }
    def self.update_repo(context, branch); end

    # Clone the repository and checkout the branch
    # Returns the repo object, or nil if an error occurs
    sig { params(context: RepoContext, authed_url: String, branch: String).returns(T.nilable(::Git::Base)) }
    def self.clone_repo(context, authed_url, branch); end

    # Checkout or create a branch from remote
    sig { params(context: RepoContext, branch: String).returns(T::Boolean) }
    def self.checkout_branch(context, branch); end

    # Get the current commit SHA
    sig { params(context: RepoContext).returns(T.nilable(String)) }
    def self.current_commit_sha(context); end

    # Check if there are changes to commit
    sig { params(context: RepoContext).returns(T::Boolean) }
    def self.changes_to_commit?(context); end

    # Accept T.untyped for testability with RSpec doubles (Sorbet does not accept instance doubles as ::Git::Base)
    sig { params(repo: T.untyped).returns(T::Boolean) }
    def self.changes?(repo); end

    # Add and commit local changes
    sig { params(context: RepoContext, commit_message: String).returns(T::Boolean) }
    def self.add_and_commit_changes(context, commit_message); end

    # Push the current branch to the remote repository
    sig { params(context: RepoContext, branch_name: String).returns(T::Boolean) }
    def self.push_branch(context, branch_name); end

    # Configure remote repository URL
    sig { params(repo: ::Git::Base, context: RepoContext).returns(T::Boolean) }
    def self.setup_remote(repo, context); end

    # Remove the 'origin' remote if it exists, with logging
    sig { params(repo: ::Git::Base, remote_name: String, context: RepoContext).void }
    def self.remove_origin_remote_if_exists(repo, remote_name, context); end

    # Push changes to the remote repository
    sig { params(repo: ::Git::Base, context: RepoContext, branch_name: String).returns(T::Boolean) }
    def self.push_to_remote(repo, context, branch_name); end

    # Configure git user.name and user.email globally
    sig { params(user_name: String, user_email: String).returns(T::Boolean) }
    def self.setup_git_config(user_name:, user_email:); end

    # Helper method to delete, create, and checkout a branch
    sig { params(repo: ::Git::Base, branch_name: String).void }
    def self._manage_branch_lifecycle(repo, branch_name); end

    # Commit and push changes to the remote branch with robust error handling
    sig { params(context: RepoContext, commit_message: String).returns(T::Boolean) }
    def self.commit_and_push_changes(context, commit_message); end

    # Commit local changes to the repository
    # @param context [RepoContext] Repository context
    # @param commit_message [String] Commit message
    # @return [Boolean] True if successful, false otherwise
    sig { params(context: RepoContext, commit_message: String).returns(T::Boolean) }
    def self.commit_changes(context, commit_message); end
  end
end
