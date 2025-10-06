# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/repository_manager'
require 'logger'

RSpec.describe CookstyleRunner::RepositoryManager do
  let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil) }

  describe '.extract_repo_name' do
    it 'extracts repository name from HTTPS URL' do
      url = 'https://github.com/sous-chefs/ruby_rbenv.git'
      expect(described_class.extract_repo_name(url)).to eq('ruby_rbenv')
    end

    it 'extracts repository name from SSH URL' do
      url = 'git@github.com:sous-chefs/ruby_rbenv.git'
      expect(described_class.extract_repo_name(url)).to eq('ruby_rbenv')
    end

    it 'extracts repository name without .git extension' do
      url = 'https://github.com/sous-chefs/ruby_rbenv'
      expect(described_class.extract_repo_name(url)).to eq('ruby_rbenv')
    end
  end

  describe '.cleanup_repo_dir' do
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'removes the repository directory' do
      expect(File.exist?(temp_dir)).to be true
      result = described_class.cleanup_repo_dir(temp_dir)
      expect(result).to be true
      expect(File.exist?(temp_dir)).to be false
    end

    it 'returns false when cleanup fails' do
      non_existent_path = '/some/path/that/does/not/exist'
      allow(FileUtils).to receive(:rm_rf).and_call_original
      allow(FileUtils).to receive(:rm_rf).with(non_existent_path).and_raise(StandardError, 'Permission denied')

      result = described_class.cleanup_repo_dir(non_existent_path)
      expect(result).to be false
    end
  end

  describe '.filter_repositories' do
    let(:repositories) do
      [
        'https://github.com/sous-chefs/ruby_rbenv.git',
        'https://github.com/sous-chefs/mysql.git',
        'https://github.com/sous-chefs/postgresql.git',
        'https://github.com/sous-chefs/apache2.git'
      ]
    end

    context 'when filter_repos is nil' do
      it 'returns all repositories' do
        result = described_class.filter_repositories(repositories, nil, logger)
        expect(result).to eq(repositories)
      end
    end

    context 'when filter_repos is empty' do
      it 'returns all repositories' do
        result = described_class.filter_repositories(repositories, [], logger)
        expect(result).to eq(repositories)
      end
    end

    context 'when filter_repos contains one repository' do
      it 'returns only the matching repository' do
        filter = ['ruby_rbenv']
        result = described_class.filter_repositories(repositories, filter, logger)
        expect(result).to eq(['https://github.com/sous-chefs/ruby_rbenv.git'])
      end

      it 'performs case-insensitive matching' do
        filter = ['RUBY_RBENV']
        result = described_class.filter_repositories(repositories, filter, logger)
        expect(result).to eq(['https://github.com/sous-chefs/ruby_rbenv.git'])
      end
    end

    context 'when filter_repos contains multiple repositories' do
      it 'returns all matching repositories' do
        filter = %w[ruby_rbenv mysql]
        result = described_class.filter_repositories(repositories, filter, logger)
        expect(result).to contain_exactly(
          'https://github.com/sous-chefs/ruby_rbenv.git',
          'https://github.com/sous-chefs/mysql.git'
        )
      end
    end

    context 'when filter_repos contains non-existent repository' do
      it 'returns empty array' do
        filter = ['non_existent_repo']
        result = described_class.filter_repositories(repositories, filter, logger)
        expect(result).to be_empty
      end
    end

    context 'when filter_repos contains partial match' do
      it 'does not match partial names (exact match only)' do
        filter = ['ruby']
        result = described_class.filter_repositories(repositories, filter, logger)
        expect(result).to be_empty
      end
    end

    it 'logs filtering information' do
      filter = ['ruby_rbenv']
      described_class.filter_repositories(repositories, filter, logger)
      expect(logger).to have_received(:info).with(/Filtering repositories/)
      expect(logger).to have_received(:info).with(/Found 1 repositories/)
    end
  end
end
