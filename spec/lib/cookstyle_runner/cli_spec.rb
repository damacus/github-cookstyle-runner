# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/cli'
require 'semantic_logger'

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
      cli = described_class.new(%w[run repo1 repo2])
      expect(cli.options[:repos]).to eq(%w[repo1 repo2])
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

  describe 'run command with format options' do
    let(:cli) { described_class.new(argv) }

    context 'with json format' do
      let(:argv) { ['run', '--format', 'json'] }

      it 'sets GCR_LOG_FORMAT environment variable to json' do
        # Mock Application to prevent actual execution
        app_double = instance_double(CookstyleRunner::Application, run: 0)
        allow(CookstyleRunner::Application).to receive(:new).and_return(app_double)

        cli.send(:apply_cli_options)
        expect(ENV.fetch('GCR_LOG_FORMAT', nil)).to eq('json')
      end
    end

    context 'with text format' do
      let(:argv) { ['run', '--format', 'text'] }

      it 'sets GCR_LOG_FORMAT environment variable to color' do
        # Mock Application to prevent actual execution
        app_double = instance_double(CookstyleRunner::Application, run: 0)
        allow(CookstyleRunner::Application).to receive(:new).and_return(app_double)

        cli.send(:apply_cli_options)
        expect(ENV.fetch('GCR_LOG_FORMAT', nil)).to eq('color')
      end
    end

    context 'with table format' do
      let(:argv) { ['run', '--format', 'table'] }

      it 'sets GCR_LOG_FORMAT environment variable to color' do
        # Mock Application to prevent actual execution
        app_double = instance_double(CookstyleRunner::Application, run: 0)
        allow(CookstyleRunner::Application).to receive(:new).and_return(app_double)

        cli.send(:apply_cli_options)
        expect(ENV.fetch('GCR_LOG_FORMAT', nil)).to eq('color')
      end
    end
  end

  describe 'list command with format options' do
    let(:repositories) { %w[repo1.git repo2.git repo3.git] }
    let(:cli) { described_class.new(argv) }
    let(:mock_app) { instance_double(CookstyleRunner::Application) }
    let(:mock_logger) { instance_double(SemanticLogger::Logger) }

    before do
      allow(CookstyleRunner::Application).to receive(:new).and_return(mock_app)
      allow(mock_app).to receive_messages(
        fetch_and_filter_repositories: repositories,
        logger: mock_logger
      )
      allow(mock_logger).to receive_messages(info: nil, error: nil)
    end

    context 'with default format' do
      let(:argv) { ['list'] }

      it 'outputs repository list through logger' do
        cli.run
        expect(mock_logger).to have_received(:info).with('Repository list', repositories: repositories)
      end
    end

    context 'with json format' do
      let(:argv) { ['list', '--format', 'json'] }

      it 'outputs repository list through logger' do
        cli.run
        expect(mock_logger).to have_received(:info).with('Repository list', repositories: repositories)
      end
    end

    context 'with table format' do
      let(:argv) { ['list', '--format', 'table'] }

      it 'outputs repository list through logger' do
        cli.run
        expect(mock_logger).to have_received(:info).with('Found 3 repositories:')
      end
    end

    context 'with invalid format' do
      let(:argv) { ['list', '--format', 'invalid'] }

      it 'validates format option values through logger' do
        cli.run
        expect(mock_logger).to have_received(:error).with('Invalid format: invalid')
      end
    end
  end
end
