# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/cli'

RSpec.describe CookstyleRunner::CLI do
  describe '#initialize' do
    it 'parses command from argv' do
      cli = described_class.new(['run'])
      expect(cli.command).to eq('run')
    end

    it 'parses options from argv' do
      cli = described_class.new(['run', '--verbose'])
      expect(cli.options[:verbose]).to be true
    end

    it 'handles no command' do
      cli = described_class.new([])
      expect(cli.command).to be_nil
    end
  end

  describe '#run' do
    let(:cli) { described_class.new(['help']) }

    it 'executes help command when no command given' do
      expect(cli.run).to eq(0)
    end

    it 'handles unknown commands' do
      cli = described_class.new(['unknown'])
      expect(cli.run).to eq(1)
    end
  end

  describe 'version command' do
    it 'displays version information' do
      cli = described_class.new(['version'])
      expect { cli.run }.to output(/Cookstyle Runner v/).to_stdout
    end
  end

  describe 'help command' do
    it 'displays help message' do
      cli = described_class.new(['help'])
      expect { cli.run }.to output(/Usage: cookstyle-runner/).to_stdout
    end

    it 'shows available commands' do
      cli = described_class.new(['help'])
      expect { cli.run }.to output(/Commands:/).to_stdout
    end
  end

  describe 'option parsing' do
    it 'parses --verbose flag' do
      cli = described_class.new(['run', '--verbose'])
      expect(cli.options[:verbose]).to be true
    end

    it 'parses -v flag' do
      cli = described_class.new(['run', '-v'])
      expect(cli.options[:verbose]).to be true
    end

    it 'parses --dry-run flag' do
      cli = described_class.new(['run', '--dry-run'])
      expect(cli.options[:dry_run]).to be true
    end

    it 'parses --force flag' do
      cli = described_class.new(['run', '--force'])
      expect(cli.options[:force]).to be true
    end

    it 'parses --threads with value' do
      cli = described_class.new(['run', '--threads', '4'])
      expect(cli.options[:threads]).to eq(4)
    end

    it 'parses repository arguments' do
      cli = described_class.new(['run', 'repo1', 'repo2'])
      expect(cli.options[:repos]).to eq(['repo1', 'repo2'])
    end

    it 'parses --format option' do
      cli = described_class.new(['list', '--format', 'json'])
      expect(cli.options[:format]).to eq('json')
    end

    it 'parses --validate flag' do
      cli = described_class.new(['config', '--validate'])
      expect(cli.options[:validate]).to be true
    end
  end
end
