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
    # Mock file reading for consistency in most tests
    allow(File).to receive(:exist?).and_call_original # Allow real check
    allow(File).to receive(:exist?).with(dummy_key_path).and_return(true)
    allow(File).to receive(:read).with(dummy_key_path).and_return(private_key_pem)

    # Mock OpenSSL to expect the key *content*
    allow(OpenSSL::PKey::RSA).to receive(:new).with(private_key_pem).and_return(fake_private_key)

    # Mock JWT encoding - Expecting 3 args now
    allow(JWT).to receive(:encode).and_return(fake_jwt)

    # Mock Octokit client and token creation
    fake_octokit_client = instance_double(Octokit::Client)
    allow(Octokit::Client).to receive(:new).with(bearer_token: fake_jwt).and_return(fake_octokit_client)
    allow(fake_octokit_client).to receive(:create_app_installation_access_token)
      .with(installation_id)
      .and_return({ token: fake_installation_token, expires_at: Time.now + 3600 })
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
      # Expect it to be called with the path, assuming path is passed in
      allow(described_class).to receive(:generate_jwt).with(app_id, dummy_key_path).and_return(fake_jwt)

      # Call get_installation_token with the path
      token = described_class.get_installation_token(app_id: app_id, installation_id: installation_id,
                                                     private_key: dummy_key_path)

      expect(described_class).to have_received(:generate_jwt).with(app_id, dummy_key_path)
      expect(Octokit::Client).to have_received(:new).with(bearer_token: fake_jwt)
      expect(Octokit::Client.new(bearer_token: fake_jwt))
        .to have_received(:create_app_installation_access_token)
        .with(installation_id)
      expect(token).to eq(fake_installation_token)
    end
  end
  # rubocop:enable Metrics/BlockLength
end
