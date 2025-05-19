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
    end

    it 'logs starting and finishing messages' do
      # Verify the real logger is used correctly
      expect(test_logger).to receive(:info).with(/CookstyleBot version .* starting.../).ordered
      expect(test_logger).to receive(:debug).with(/Settings:/).ordered
      expect(test_logger).to receive(:info).with('CookstyleBot finished.').ordered
      described_class.run
    end
  end
end
