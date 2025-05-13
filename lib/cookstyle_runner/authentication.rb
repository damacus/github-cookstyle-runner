# frozen_string_literal: true
# typed: strict

require 'openssl'
require 'jwt'
require 'octokit'
require 'sorbet-runtime'

module CookstyleRunner
  # Helper module for GitHub App authentication
  module Authentication
    extend T::Sig

    # Class instance variables for singleton
    @client = T.let(nil, T.nilable(T.any(Octokit::Client, T.untyped)))

    # Credentials class to encapsulate different authentication methods
    class Credentials
      extend T::Sig

      # Authentication types supported by the system
      AUTH_TYPES = T.let(%i[none pat app].freeze, T::Array[Symbol])

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

      # Initializes a new Credentials object
      # @param auth_type [Symbol] The type of authentication (:pat, :app, :none)
      # @param token [String, nil] Personal access token for :pat auth
      # @param app_id [String, nil] GitHub App ID for :app auth
      # @param installation_id [String, nil] GitHub App installation ID for :app auth
      # @param private_key [String, nil] GitHub App private key content or path for :app auth
      # @param api_endpoint [String] The GitHub API endpoint URL
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
        @token = T.let(token, T.nilable(String))
        @app_id = T.let(app_id, T.nilable(String))
        @installation_id = T.let(installation_id, T.nilable(String))
        @private_key = T.let(private_key, T.nilable(String))
        @api_endpoint = T.let(api_endpoint || 'https://api.github.com', String)
      end

      # Checks if the credentials are valid for authentication
      # @return [Boolean] true if credentials are valid for the authentication type
      sig { returns(T::Boolean) }
      def valid?
        case auth_type
        when :pat
          !token.nil? && !token.to_s.empty?
        when :app
          !app_id.nil? && !installation_id.nil? && !private_key.nil? &&
            !app_id.to_s.empty? && !installation_id.to_s.empty? && !private_key.to_s.empty?
        else
          false
        end
      end
    end

    # Get the configured GitHub credentials from environment variables
    # @return [Credentials] credentials object with loaded config
    sig { returns(Credentials) }
    def self.github_credentials
      if ENV.key?('GITHUB_TOKEN') && !ENV.fetch('GITHUB_TOKEN', '').strip.empty?
        # PAT authentication
        Credentials.new(
          auth_type: :pat,
          token: ENV.fetch('GITHUB_TOKEN', nil),
          api_endpoint: ENV.fetch('GITHUB_API_ENDPOINT', nil)
        )
      elsif ENV.key?('GITHUB_APP_ID') && ENV.key?('GITHUB_APP_INSTALLATION_ID') && ENV.key?('GITHUB_APP_PRIVATE_KEY')
        # GitHub App authentication
        Credentials.new(
          auth_type: :app,
          app_id: ENV.fetch('GITHUB_APP_ID', nil),
          installation_id: ENV.fetch('GITHUB_APP_INSTALLATION_ID', nil),
          private_key: ENV.fetch('GITHUB_APP_PRIVATE_KEY', nil),
          api_endpoint: ENV.fetch('GITHUB_API_ENDPOINT', nil)
        )
      else
        # No valid authentication
        Credentials.new(auth_type: :none, api_endpoint: ENV.fetch('GITHUB_API_ENDPOINT', nil))
      end
    end

    # Returns a memoized Octokit client (PAT or App auth)
    # Use this for all GitHub API calls
    # @return [Octokit::Client] Octokit client instance
    # @raise [RuntimeError] if no valid authentication is available
    sig { returns(T.any(Octokit::Client, T.untyped)) }
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
    sig { params(credentials: Credentials).returns(T.any(Octokit::Client, T.untyped)) }
    def self.build_pat_client(credentials)
      Octokit::Client.new(
        access_token: T.must(credentials.token),
        auto_paginate: true
      )
    end

    # Build an Octokit client using GitHub App authentication
    # @param credentials [Credentials] credentials containing app info
    # @return [Octokit::Client] the configured client
    sig { params(credentials: Credentials).returns(T.any(Octokit::Client, T.untyped)) }
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
    sig { params(app_id: String, private_key: String).returns(String) }
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
    sig { params(app_id: String, installation_id: T.any(String, Integer), private_key: String).returns(String) }
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
    sig { params(app_id: String).returns(T::Hash[Symbol, T.any(Integer, String)]) }
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
    sig { params(private_key: String).returns(String) }
    def self.read_private_key(private_key)
      if File.exist?(private_key.to_s)
        File.read(private_key)
      else
        private_key
      end
    end
  end
end
