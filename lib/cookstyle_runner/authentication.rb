# frozen_string_literal: true

require 'openssl'
require 'jwt'
require 'octokit'

module CookstyleRunner
  # Helper module for GitHub App authentication
  module Authentication
    # Generate a JWT for the GitHub App
    # @param app_id [String, Integer]
    # @param private_key [String] PEM-encoded private key or path to key file
    # @return [String] JWT
    def self.generate_jwt(app_id, private_key)
      payload = jwt_payload(app_id)
      key_content = read_private_key(private_key)
      rsa_key = OpenSSL::PKey::RSA.new(key_content)
      JWT.encode(payload, rsa_key, 'RS256')
    end

    # Get an installation access token
    # @param app_id [String, Integer]
    # @param installation_id [String, Integer]
    # @param private_key [String] PEM-encoded private key or path to key file
    # @return [String] installation access token
    def self.get_installation_token(app_id:, installation_id:, private_key:)
      jwt = generate_jwt(app_id, private_key)
      client = Octokit::Client.new(bearer_token: jwt)
      token_response = client.create_app_installation_access_token(installation_id)
      token_response[:token]
    end

    # Builds the payload for the JWT
    # @param app_id [String, Integer] GitHub App ID
    # @return [Hash] JWT payload
    def self.jwt_payload(app_id)
      now = Time.now.to_i
      {
        iat: now,              # Issued at time
        exp: now + (10 * 60),  # Expiration time (10 minutes from now)
        iss: app_id            # Issuer (GitHub App ID)
      }
    end

    # Reads the private key content from a file path or uses the string directly
    # @param private_key [String] Path to the key file or the key content itself
    # @return [String] Private key content
    def self.read_private_key(private_key)
      if File.exist?(private_key.to_s)
        File.read(private_key)
      else
        private_key # Assume it's the key content itself
      end
    end
  end
end
