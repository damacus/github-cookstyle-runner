# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/authentication'
require 'openssl'
require 'jwt'
require 'octokit'
require 'time'
require 'fileutils'

# rubocop:disable Metrics/BlockLength
RSpec.describe CookstyleRunner::Authentication do
  let(:app_id) { '12345' }
  let(:installation_id) { '67890' }
  let(:dummy_key_path) { 'spec/fixtures/dummy_private_key.pem' }
  # Read content once for mocks expecting content
  let(:private_key_pem) { File.read(dummy_key_path) }
  let(:fake_private_key) { instance_double(OpenSSL::PKey::RSA) }
  let(:fake_jwt) { 'fake.jwt.token' }
  let(:fake_installation_token) { 'ghs_fakeinstallationtoken' }
  let(:now) { Time.now.to_i }
  let(:github_token) { 'ghp_fakepattoken' }
  let(:fake_client) { instance_double(Octokit::Client) }

  # Create a dummy private key file for testing if it doesn't exist
  before(:all) do
    fixture_dir = 'spec/fixtures'
    key_path = File.join(fixture_dir, 'dummy_private_key.pem')
    unless File.exist?(key_path)
      FileUtils.mkdir_p(fixture_dir)
      key = OpenSSL::PKey::RSA.new(2048)
      File.write(key_path, key.to_pem)
    end
  end

  before do
    # Clean up any ENV variables that might interfere with tests
    stub_const('ENV', {})
    
    # Mock file reading for consistency in most tests
    allow(File).to receive(:exist?).and_call_original # Allow real check
    allow(File).to receive(:exist?).with(dummy_key_path).and_return(true)
    allow(File).to receive(:read).with(dummy_key_path).and_return(private_key_pem)

    # Mock OpenSSL to expect the key *content*
    allow(OpenSSL::PKey::RSA).to receive(:new).with(private_key_pem).and_return(fake_private_key)

    # Mock JWT encoding
    allow(JWT).to receive(:encode).and_return(fake_jwt)

    # Mock Octokit client and token creation
    fake_octokit_client = instance_double(Octokit::Client)
    allow(Octokit::Client).to receive(:new).with(bearer_token: fake_jwt).and_return(fake_octokit_client)
    allow(fake_octokit_client).to receive(:create_app_installation_access_token)
      .with(installation_id.to_i)
      .and_return({ token: fake_installation_token, expires_at: Time.now + 3600 })
      
    # Setup for PAT client tests
    allow(Octokit::Client).to receive(:new).with(access_token: github_token, auto_paginate: true).and_return(fake_client)
    allow(fake_client).to receive(:api_endpoint=)
  end

  describe '.github_credentials' do
    it 'returns PAT credentials when GITHUB_TOKEN is set' do
      stub_const('ENV', { 'GITHUB_TOKEN' => github_token })
      credentials = described_class.github_credentials
      expect(credentials).to be_a(CookstyleRunner::Authentication::Credentials)
      expect(credentials.auth_type).to eq(:pat)
      expect(credentials.token).to eq(github_token)
    end

    it 'returns App credentials when GITHUB_APP_ variables are set' do
      stub_const('ENV', {
        'GITHUB_APP_ID' => app_id,
        'GITHUB_APP_INSTALLATION_ID' => installation_id,
        'GITHUB_APP_PRIVATE_KEY' => private_key_pem
      })
      credentials = described_class.github_credentials
      expect(credentials).to be_a(CookstyleRunner::Authentication::Credentials)
      expect(credentials.auth_type).to eq(:app)
      expect(credentials.app_id).to eq(app_id)
      expect(credentials.installation_id).to eq(installation_id)
      expect(credentials.private_key).to eq(private_key_pem)
    end

    it 'returns nil credentials when no auth environment variables are set' do
      stub_const('ENV', {})
      credentials = described_class.github_credentials
      expect(credentials).to be_a(CookstyleRunner::Authentication::Credentials)
      expect(credentials.auth_type).to eq(:none)
    end
  end

  describe '.generate_jwt' do
    it 'generates a JWT with the correct payload' do
      allow(Time).to receive(:now).and_return(Time.at(now))

      expected_payload = {
        iat: now, # Use current time for 'issued at'
        exp: now + (10 * 60),
        iss: app_id
      }

      # Call with key content (matches the primary OpenSSL mock)
      jwt = described_class.send(:generate_jwt, app_id, private_key_pem)

      # Updated expectation: only 3 args expected by the code
      expect(JWT).to have_received(:encode).with(expected_payload, fake_private_key, 'RS256')
      expect(jwt).to eq(fake_jwt)
    end

    it 'reads private key from file path if path is given' do
      # Expect File.read to be called with the path
      expect(File).to receive(:read).with(dummy_key_path).and_return(private_key_pem)
      # Expect OpenSSL to be called with the *content* afterwards (handled by main mock)
      expect(OpenSSL::PKey::RSA).to receive(:new).with(private_key_pem).and_return(fake_private_key)

      # Call with the path
      described_class.send(:generate_jwt, app_id, dummy_key_path)

      # JWT encode should still be called correctly (implicitly checked by main mock)
    end

    it 'uses private key directly if content is given' do
      # Ensure File.read is NOT called
      expect(File).not_to receive(:read)
      # Expect OpenSSL to be called with the content
      expect(OpenSSL::PKey::RSA).to receive(:new).with(private_key_pem).and_return(fake_private_key)

      # Call with content
      described_class.send(:generate_jwt, app_id, private_key_pem)
    end
  end

  describe '.get_installation_token' do
    it 'generates a JWT and uses it to request an installation token' do
      # Mock the private generate_jwt method for this test's scope
      allow(described_class).to receive(:generate_jwt).with(app_id, dummy_key_path).and_return(fake_jwt)

      # Call get_installation_token with the path
      token = described_class.get_installation_token(app_id: app_id, installation_id: installation_id,
                                                     private_key: dummy_key_path)

      expect(described_class).to have_received(:generate_jwt).with(app_id, dummy_key_path)
      expect(Octokit::Client).to have_received(:new).with(bearer_token: fake_jwt)
      expect(Octokit::Client.new(bearer_token: fake_jwt))
        .to have_received(:create_app_installation_access_token)
        .with(installation_id.to_i)
      expect(token).to eq(fake_installation_token)
    end

    it 'handles string installation IDs by converting to integer' do
      allow(described_class).to receive(:generate_jwt).with(app_id, dummy_key_path).and_return(fake_jwt)
      
      token = described_class.get_installation_token(app_id: app_id, installation_id: installation_id,
                                                   private_key: dummy_key_path)
      
      # Should have converted string ID to integer
      expect(Octokit::Client.new(bearer_token: fake_jwt))
        .to have_received(:create_app_installation_access_token)
        .with(installation_id.to_i)
      expect(token).to eq(fake_installation_token)
    end
  end

  describe '.client' do
    # Clear the memoized client between examples
    before do
      described_class.instance_variable_set(:@client, nil)
    end

    it 'returns a PAT client when PAT credentials are available' do
      stub_const('ENV', { 'GITHUB_TOKEN' => github_token })
      
      # Set up expectations for this specific test
      pat_client = instance_double(Octokit::Client)
      allow(Octokit::Client).to receive(:new).with(access_token: github_token, auto_paginate: true).and_return(pat_client)
      allow(pat_client).to receive(:api_endpoint=)
      
      client = described_class.client
      expect(client).to eq(pat_client)
      expect(Octokit::Client).to have_received(:new).with(access_token: github_token, auto_paginate: true)
    end
    
    it 'returns an app client when app credentials are available' do
      stub_const('ENV', {
        'GITHUB_APP_ID' => app_id,
        'GITHUB_APP_INSTALLATION_ID' => installation_id,
        'GITHUB_APP_PRIVATE_KEY' => private_key_pem
      })
      
      # Mock the token retrieval
      allow(described_class).to receive(:get_installation_token).and_return(fake_installation_token)
      
      # Mock the final client creation - specific to this test
      app_client = instance_double(Octokit::Client)
      allow(Octokit::Client).to receive(:new).with(access_token: fake_installation_token, auto_paginate: true).and_return(app_client)
      allow(app_client).to receive(:api_endpoint=)
      
      client = described_class.client
      expect(client).to eq(app_client)
      expect(described_class).to have_received(:get_installation_token)
    end
    
    it 'raises an error when no auth credentials are available' do
      stub_const('ENV', {})
      expect { described_class.client }.to raise_error(RuntimeError, /No GitHub authentication/)
    end
  end
  # Additional tests for Credentials class
  describe CookstyleRunner::Authentication::Credentials do
    describe '#initialize' do
      it 'creates credentials with the given attributes' do
        credentials = CookstyleRunner::Authentication::Credentials.new(
          auth_type: :pat,
          token: github_token,
          api_endpoint: 'https://custom.github.com'
        )
        
        expect(credentials.auth_type).to eq(:pat)
        expect(credentials.token).to eq(github_token)
        expect(credentials.api_endpoint).to eq('https://custom.github.com')
      end
      
      it 'sets default values for nil attributes' do
        credentials = CookstyleRunner::Authentication::Credentials.new(auth_type: :none)
        
        expect(credentials.auth_type).to eq(:none)
        expect(credentials.token).to be_nil
        expect(credentials.app_id).to be_nil
        expect(credentials.installation_id).to be_nil
        expect(credentials.private_key).to be_nil
        expect(credentials.api_endpoint).to eq('https://api.github.com')
      end
    end
    
    describe '#valid?' do
      it 'returns true for valid PAT credentials' do
        credentials = CookstyleRunner::Authentication::Credentials.new(
          auth_type: :pat,
          token: github_token
        )
        expect(credentials.valid?).to be true
      end
      
      it 'returns true for valid App credentials' do
        credentials = CookstyleRunner::Authentication::Credentials.new(
          auth_type: :app,
          app_id: app_id,
          installation_id: installation_id,
          private_key: private_key_pem
        )
        expect(credentials.valid?).to be true
      end
      
      it 'returns false for incomplete App credentials' do
        credentials = CookstyleRunner::Authentication::Credentials.new(
          auth_type: :app,
          app_id: app_id
          # Missing installation_id and private_key
        )
        expect(credentials.valid?).to be false
      end
      
      it 'returns false for credentials with auth_type :none' do
        credentials = CookstyleRunner::Authentication::Credentials.new(auth_type: :none)
        expect(credentials.valid?).to be false
      end
    end
  end
  # rubocop:enable Metrics/BlockLength
end
