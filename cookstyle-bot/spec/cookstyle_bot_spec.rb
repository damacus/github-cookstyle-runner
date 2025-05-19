# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CookstyleBot do
  it 'has a version number' do
    expect(CookstyleBot::VERSION).not_to be_nil
  end

  describe '.run' do
    # Use a real Logger with a StringIO to satisfy Sorbet type checking
    let(:log_output) { StringIO.new }
    let(:test_logger) { Logger.new(log_output) }

    before do
      # Set up the real logger with spies for verification
      allow(test_logger).to receive(:info).and_call_original
      allow(test_logger).to receive(:debug).and_call_original
      allow(CookstyleBot::Logging).to receive(:logger).and_return(test_logger)

      # Run the method under test (BEFORE we check expectations)
      described_class.run
    end

    it 'logs version' do
      expect(test_logger).to have_received(:info).with(/CookstyleBot version .* starting.../)
    end

    it 'logs settings' do
      expect(test_logger).to have_received(:debug).with(/Settings:/)
    end

    it 'logs finishing message' do
      expect(test_logger).to have_received(:info).with('CookstyleBot finished.')
    end
  end
end
