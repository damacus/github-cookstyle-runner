# frozen_string_literal: true
# typed: true

require 'openssl'
require 'jwt'
require 'octokit'
require 'sorbet-runtime'

module CookstyleRunner
  # Helper module for GitHub App authentication
  module Authentication
    extend T::Sig
    # Returns a memoized Octokit client (PAT or App auth)
    # Use this for all GitHub API calls
    # @return [Octokit::Client] Octokit client instance
    def self.client
      @client ||= use_pat? ? build_pat_client : build_app_client
    end

    # Determine if a Personal Access Token should be used
    sig { returns(T::Boolean) }
    def self.use_pat?
      ENV.fetch('GITHUB_TOKEN', nil) && !T.must(ENV.fetch('GITHUB_TOKEN', nil)).empty?
    end

    # Returns the API endpoint to use for GitHub API calls
    sig { returns(String) }
    def self.api_endpoint
      ENV['GITHUB_API_ENDPOINT'] || 'https://api.github.com'
    end

    # Build an Octokit client using a Personal Access Token
    sig { returns(Octokit::Client) }
    def self.build_pat_client
      client = Octokit::Client.new(
        access_token: ENV.fetch('GITHUB_TOKEN', nil),
        auto_paginate: true
      )
      client.api_endpoint = api_endpoint
      client
    end

    # Build an Octokit client using GitHub App authentication
    sig { returns(Octokit::Client) }
    def self.build_app_client
      app_id = ENV.fetch('GITHUB_APP_ID', nil)
      installation_id = ENV.fetch('GITHUB_APP_INSTALLATION_ID', nil)
      private_key = ENV.fetch('GITHUB_APP_PRIVATE_KEY', nil)
      token = get_installation_token(app_id: T.must(app_id), installation_id: installation_id, private_key: T.must(private_key))
      client = Octokit::Client.new(
        access_token: token,
        auto_paginate: true
      )
      client.api_endpoint = api_endpoint
      client
    end

    # Generate a JWT for the GitHub App
    sig { params(app_id: String, private_key: String).returns(String) }
    def self.generate_jwt(app_id, private_key)
      payload = jwt_payload(app_id)
      key_content = read_private_key(private_key)
      rsa_key = OpenSSL::PKey::RSA.new(key_content)
      JWT.encode(payload, rsa_key, 'RS256')
    end

    # Get an installation access token
    sig { params(app_id: String, installation_id: Integer, private_key: String).returns(String) }
    def self.get_installation_token(app_id:, installation_id:, private_key:)
      jwt = generate_jwt(app_id, private_key)
      client = Octokit::Client.new(bearer_token: jwt)
      token_response = client.create_app_installation_access_token(installation_id)
      token_response[:token]
    end

    # Builds the payload for the JWT
    sig { params(app_id: String).returns(Hash) }
    def self.jwt_payload(app_id)
      now = Time.now.to_i
      {
        iat: now,              # Issued at time
        exp: now + (10 * 60),  # Expiration time (10 minutes from now)
        iss: app_id            # Issuer (GitHub App ID)
      }
    end

    # Reads the private key content from a file path or uses the string directly
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
