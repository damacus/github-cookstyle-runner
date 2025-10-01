# frozen_string_literal: true
# typed: strict

require 'openssl'
require 'jwt'
require 'octokit'
require 'sorbet-runtime'

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

    # Credentials class to encapsulate different authentication methods
    class Credentials
      extend T::Sig

      AUTH_TYPES = T.let(%i[none pat app].freeze, T::Array[Symbol])
      DEFAULT_API_ENDPOINT = 'https://api.github.com'

      @auth_type = T.let(nil, T.nilable(Symbol))
      @token = T.let(nil, T.nilable(String))
      @app_id = T.let(nil, T.nilable(String))
      @installation_id = T.let(nil, T.nilable(String))
      @private_key = T.let(nil, T.nilable(String))
      @api_endpoint = T.let(nil, T.nilable(String))

      attr_reader :auth_type, :token, :app_id, :installation_id, :private_key, :api_endpoint

      # Initialize a new credentials object
      # @param auth_type [Symbol] the authentication type (:pat, :app, :none)
      # @param token [String, nil] optional PAT token (for testing)
      # @param app_id [String, nil] optional app ID (for testing)
      # @param installation_id [String, nil] optional installation ID (for testing)
      # @param private_key [String, nil] optional private key (for testing)
      # @param api_endpoint [String, nil] optional API endpoint (for testing)
      sig do
        params(
          auth_type: Symbol,
          token: T.nilable(String),
          app_id: T.nilable(String),
          installation_id: T.nilable(String),
          private_key: T.nilable(String),
          api_endpoint: T.nilable(String)
        ).void
      end
      def initialize(auth_type:, token: nil, app_id: nil, installation_id: nil, private_key: nil, api_endpoint: nil)
        @auth_type = T.let(auth_type, Symbol)

        # If values are provided, use them (for testing), otherwise read from ENV
        if token || app_id || installation_id || private_key
          @token = T.let(token, T.nilable(String))
          @app_id = T.let(app_id, T.nilable(String))
          @installation_id = T.let(installation_id, T.nilable(String))
          @private_key = T.let(private_key, T.nilable(String))
        else
          # Initialize from environment based on auth type
          case auth_type
          when :pat
            initialize_pat_credentials
          when :app
            initialize_app_credentials
          when :none
            @token = T.let(nil, T.nilable(String))
            @app_id = T.let(nil, T.nilable(String))
            @installation_id = T.let(nil, T.nilable(String))
            @private_key = T.let(nil, T.nilable(String))
          else
            raise "Invalid authentication type: #{auth_type}"
          end
        end

        # Set API endpoint
        @api_endpoint = T.let(api_endpoint || ENV.fetch('GITHUB_API_ENDPOINT', DEFAULT_API_ENDPOINT), String)
      end

      # Initialize PAT credentials from environment variables
      # @return [void]
      sig { void }
      def initialize_pat_credentials
        @token = T.let(ENV.fetch('GITHUB_TOKEN', nil), T.nilable(String))
        @app_id = T.let(nil, T.nilable(String))
        @installation_id = T.let(nil, T.nilable(String))
        @private_key = T.let(nil, T.nilable(String))
      end

      # Initialize GitHub App credentials from environment variables
      # @return [void]
      sig { void }
      def initialize_app_credentials
        @token = T.let(nil, T.nilable(String))
        @app_id = T.let(ENV.fetch('GITHUB_APP_ID', nil), T.nilable(String))
        @installation_id = T.let(ENV.fetch('GITHUB_APP_INSTALLATION_ID', nil), T.nilable(String))
        @private_key = T.let(ENV.fetch('GITHUB_APP_PRIVATE_KEY', nil), T.nilable(String))
      end

      # Create a new credentials object for PAT authentication
      # @return [Credentials] new credentials object
      sig { returns(Credentials) }
      def self.from_pat
        new(auth_type: :pat)
      end

      # Create a new credentials object for GitHub App authentication
      # @return [Credentials] new credentials object
      sig { returns(Credentials) }
      def self.from_app
        new(auth_type: :app)
      end

      # Checks if the credentials are valid for authentication
      # @return [Boolean] true if credentials are valid for the authentication type
      def valid?
        case auth_type
        when :pat
          valid_token?
        when :app
          valid_app_credentials?
        else
          false
        end
      end

      private

      # Check if token is present and not empty
      # @return [Boolean] true if token is valid
      def valid_token?
        !token.nil? && !token.to_s.empty?
      end

      # Check if all app credentials are present and not empty
      # @return [Boolean] true if app credentials are valid
      def valid_app_credentials?
        all_present? && all_not_empty?
      end

      # Check if all required app credentials are present
      # @return [Boolean] true if all credentials are present
      def all_present?
        !app_id.nil? && !installation_id.nil? && !private_key.nil?
      end

      # Check if all required app credentials are not empty
      # @return [Boolean] true if all credentials are not empty
      def all_not_empty?
        !app_id.to_s.empty? && !installation_id.to_s.empty? && !private_key.to_s.empty?
      end
    end

    # Get the configured GitHub credentials from environment variables
    # @return [Credentials] credentials object with loaded config
    # @raise [RuntimeError] if no valid credentials are available
    sig { returns(Credentials) }
    def self.github_credentials
      if pat_available?
        Credentials.from_pat
      elsif app_auth_available?
        Credentials.from_app
      else
        # This will raise an error with a helpful message
        raise 'No GitHub authentication available. Set GITHUB_TOKEN or GITHUB_APP_* environment variables to create pull requests.'
      end
    end

    # Check if PAT authentication is available
    # @return [Boolean] true if PAT is available
    sig { returns(T::Boolean) }
    def self.pat_available?
      ENV.key?('GITHUB_TOKEN') && !ENV.fetch('GITHUB_TOKEN', '').strip.empty?
    end

    # Check if GitHub App authentication is available
    # @return [Boolean] true if GitHub App auth is available
    sig { returns(T::Boolean) }
    def self.app_auth_available?
      ENV.key?('GITHUB_APP_ID') &&
        ENV.key?('GITHUB_APP_INSTALLATION_ID') &&
        ENV.key?('GITHUB_APP_PRIVATE_KEY')
    end

    # Returns a memoized Octokit client (PAT or App auth)
    # Use this for all GitHub API calls
    # @return [Octokit::Client] Octokit client instance
    # @raise [RuntimeError] if no valid authentication is available
    def self.client
      @client ||= begin
        credentials = github_credentials
        raise 'No GitHub authentication available. Set GITHUB_TOKEN or GITHUB_APP_* environment variables.' unless credentials.valid?

        client = if credentials.auth_type == :pat
                   build_pat_client(credentials)
                 elsif credentials.auth_type == :app
                   build_app_client(credentials)
                 else
                   # Should never happen due to valid? check
                   raise "Invalid authentication type: #{credentials.auth_type}"
                 end

        client.api_endpoint = credentials.api_endpoint
        client
      end
    end

    # Build an Octokit client using a Personal Access Token
    # @param credentials [Credentials] credentials containing token info
    # @return [Octokit::Client] the configured client
    def self.build_pat_client(credentials)
      Octokit::Client.new(
        access_token: T.must(credentials.token),
        auto_paginate: true
      )
    end

    # Build an Octokit client using GitHub App authentication
    # @param credentials [Credentials] credentials containing app info
    # @return [Octokit::Client] the configured client
    def self.build_app_client(credentials)
      token = get_installation_token(
        app_id: T.must(credentials.app_id),
        installation_id: T.must(credentials.installation_id),
        private_key: T.must(credentials.private_key)
      )

      Octokit::Client.new(
        access_token: token,
        auto_paginate: true
      )
    end

    # Generate a JWT for the GitHub App
    # @param app_id [String] the GitHub App ID
    # @param private_key [String] path to private key or the key content
    # @return [String] the generated JWT
    def self.generate_jwt(app_id, private_key)
      payload = jwt_payload(app_id)
      key_content = read_private_key(private_key)
      rsa_key = OpenSSL::PKey::RSA.new(key_content)
      JWT.encode(payload, rsa_key, 'RS256')
    end

    # Get an installation access token
    # @param app_id [String] the GitHub App ID
    # @param installation_id [String, Integer] the GitHub App installation ID
    # @param private_key [String] path to private key or the key content
    # @return [String] the installation token
    def self.get_installation_token(app_id:, installation_id:, private_key:)
      # Convert installation_id to integer if it's not already
      converted_id = installation_id.is_a?(Integer) ? installation_id : installation_id.to_i

      # Generate JWT and use it to get an installation token
      jwt = generate_jwt(app_id, private_key)
      client = Octokit::Client.new(bearer_token: jwt)
      token_response = client.create_app_installation_access_token(converted_id)
      token_response[:token]
    end

    # Builds the payload for the JWT
    # @param app_id [String] the GitHub App ID
    # @return [Hash] the JWT payload
    def self.jwt_payload(app_id)
      now = Time.now.to_i
      {
        iat: now,              # Issued at time
        exp: now + (10 * 60),  # Expiration time (10 minutes from now)
        iss: app_id            # Issuer (GitHub App ID)
      }
    end

    # Reads the private key content from a file path or uses the string directly
    # @param private_key [String] path to private key or the key content
    # @return [String] the private key content
    def self.read_private_key(private_key)
      File.exist?(private_key) ? File.read(private_key) : private_key
    end

    # Generate an authenticated URL for Git operations
    # @param owner [String] repository owner
    # @param repo_name [String] repository name
    # @param logger [Logger] logger instance
    # @return [String] authenticated URL for Git operations
    def self.authenticated_url(owner, repo_name, logger = nil)
      credentials = github_credentials
      base_url = "https://github.com/#{owner}/#{repo_name}.git"

      return build_pat_url(credentials, owner, repo_name, logger) if pat_auth?(credentials)
      return build_app_url(credentials, owner, repo_name) if app_auth?(credentials)

      # No valid authentication
      logger&.error("No valid authentication found for #{repo_name}")
      base_url
    end

    # Check if PAT authentication is valid
    # @param credentials [Credentials] credentials to check
    # @return [Boolean] true if PAT auth is valid
    def self.pat_auth?(credentials)
      credentials.auth_type == :pat && !credentials.token.nil?
    end

    # Check if GitHub App authentication is valid
    # @param credentials [Credentials] credentials to check
    # @return [Boolean] true if app auth is valid
    def self.app_auth?(credentials)
      credentials.auth_type == :app && credentials.valid?
    end

    # Build URL with PAT authentication
    # @param credentials [Credentials] PAT credentials
    # @param owner [String] repository owner
    # @param repo_name [String] repository name
    # @param logger [Logger] logger instance
    # @return [String] authenticated URL
    def self.build_pat_url(credentials, owner, repo_name, logger)
      logger&.debug("Using PAT authentication for #{repo_name}")
      "https://#{credentials.token}:x-oauth-basic@github.com/#{owner}/#{repo_name}.git"
    end

    # Build URL with GitHub App authentication
    # @param credentials [Credentials] app credentials
    # @param owner [String] repository owner
    # @param repo_name [String] repository name
    # @return [String] authenticated URL
    def self.build_app_url(credentials, owner, repo_name)
      token = get_installation_token(
        app_id: T.must(credentials.app_id),
        installation_id: T.must(credentials.installation_id),
        private_key: T.must(credentials.private_key)
      )
      "https://x-access-token:#{token}@github.com/#{owner}/#{repo_name}.git"
    end
  end
end
