# typed: false
# frozen_string_literal: true

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - Authentication
  # =============================================================================
  #
  # This module handles GitHub authentication using either Personal Access Tokens
  # or GitHub App authentication.
  #
  module Authentication
    extend T::Sig

    # Class instance variables for singleton
    @client = T.let(nil, T.nilable(T.any(Octokit::Client, T.untyped)))

    sig { returns(Credentials) }
    def self.github_credentials; end

    sig { returns(T::Boolean) }
    def self.pat_available?; end

    sig { returns(T::Boolean) }
    def self.app_auth_available?; end

    sig { params(credentials: Credentials).returns(T::Boolean) }
    def self.pat_auth?(credentials); end

    sig { params(credentials: Credentials).returns(T::Boolean) }
    def self.app_auth?(credentials); end

    sig { params(credentials: Credentials, owner: String, repo_name: String, logger: T.untyped).returns(String) }
    def self.build_pat_url(credentials, owner, repo_name, logger); end

    sig { params(credentials: Credentials, owner: String, repo_name: String).returns(String) }
    def self.build_app_url(credentials, owner, repo_name); end

    sig { returns(T.any(Octokit::Client, T.untyped)) }
    def self.client; end

    sig { params(credentials: Credentials).returns(T.any(Octokit::Client, T.untyped)) }
    def self.build_pat_client(credentials); end

    sig { params(credentials: Credentials).returns(T.any(Octokit::Client, T.untyped)) }
    def self.build_app_client(credentials); end

    sig { params(app_id: String, private_key: String).returns(String) }
    def self.generate_jwt(app_id, private_key); end

    sig { params(app_id: String, installation_id: T.any(String, Integer), private_key: String).returns(String) }
    def self.get_installation_token(app_id:, installation_id:, private_key:); end

    sig { params(app_id: String).returns(T::Hash[Symbol, T.any(Integer, String)]) }
    def self.jwt_payload(app_id); end

    sig { params(private_key: String).returns(String) }
    def self.read_private_key(private_key); end

    sig { params(owner: String, repo_name: String, logger: T.untyped).returns(String) }
    def self.authenticated_url(owner, repo_name, logger = nil); end

    # Credentials class to encapsulate different authentication methods
    class Credentials
      extend T::Sig

      # Authentication types supported by the system
      AUTH_TYPES = T.let(%i[none pat app].freeze, T::Array[Symbol])

      # Default API endpoint
      DEFAULT_API_ENDPOINT = T.let('https://api.github.com', String)

      sig { returns(Symbol) }
      attr_reader :auth_type

      sig { returns(T.nilable(String)) }
      attr_reader :token

      sig { returns(T.nilable(String)) }
      attr_reader :app_id

      sig { returns(T.nilable(String)) }
      attr_reader :installation_id

      sig { returns(T.nilable(String)) }
      attr_reader :private_key

      sig { returns(String) }
      attr_reader :api_endpoint

      sig { params(auth_type: Symbol).void }
      def initialize(auth_type); end

      sig { void }
      def initialize_pat_credentials; end

      sig { void }
      def initialize_app_credentials; end

      sig { returns(Credentials) }
      def self.from_pat; end

      sig { returns(Credentials) }
      def self.from_app; end

      sig { returns(T::Boolean) }
      def valid?; end

      # Private methods
      sig { returns(T::Boolean) }
      def valid_token?; end

      sig { returns(T::Boolean) }
      def valid_app_credentials?; end

      sig { returns(T::Boolean) }
      def all_present?; end

      sig { returns(T::Boolean) }
      def all_not_empty?; end
    end
  end
end
