# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/formatter'

RSpec.describe CookstyleRunner::Formatter do
  describe '.format_pr_description' do
    context 'when there are mixed correctable and non-correctable offenses' do
      let(:offense_details) do
        {
          'files' => [
            {
              'path' => 'libraries/helpers.rb',
              'offenses' => [
                {
                  'cop_name' => 'Style/RedundantReturn',
                  'correctable' => true,
                  'corrected' => true
                }
              ]
            },
            {
              'path' => 'resources/script.rb',
              'offenses' => [
                {
                  'cop_name' => 'Layout/HashAlignment',
                  'correctable' => true,
                  'corrected' => true
                }
              ]
            },
            {
              'path' => 'resources/user_install.rb',
              'offenses' => [
                {
                  'cop_name' => 'Layout/ArrayAlignment',
                  'correctable' => true,
                  'corrected' => true
                },
                {
                  'cop_name' => 'Layout/HashAlignment',
                  'correctable' => true,
                  'corrected' => true
                }
              ]
            },
            {
              'path' => 'Berksfile',
              'offenses' => []
            },
            {
              'path' => 'test/unit/default_spec.rb',
              'offenses' => [
                {
                  'cop_name' => 'Chef/Deprecations/ResourceWithoutUnifiedTrue',
                  'correctable' => false,
                  'corrected' => false
                }
              ]
            }
          ],
          'summary' => {
            'offense_count' => 4
          }
        }
      end

      it 'only includes files with correctable offenses' do
        result = described_class.format_pr_description(offense_details)

        # Should include files with correctable offenses
        expect(result).to include('libraries/helpers.rb')
        expect(result).to include('resources/script.rb')
        expect(result).to include('resources/user_install.rb')

        # Should NOT include files with no offenses
        expect(result).not_to include('Berksfile')

        # Should NOT include files with only non-correctable offenses
        expect(result).not_to include('test/unit/default_spec.rb')
      end

      it 'shows the correct cop names for files with correctable offenses' do
        result = described_class.format_pr_description(offense_details)

        expect(result).to include('Style/RedundantReturn')
        expect(result).to include('Layout/HashAlignment')
        expect(result).to include('Layout/ArrayAlignment')
      end

      it 'includes the header and summary' do
        result = described_class.format_pr_description(offense_details)

        expect(result).to include('Cookstyle Automated Changes')
        expect(result).to include('Changes Made')
        expect(result).to include('Summary')
      end

      it 'shows correct file count in summary (only files with correctable offenses)' do
        result = described_class.format_pr_description(offense_details)

        # Should show 3 files (helpers.rb, script.rb, user_install.rb)
        # NOT 5 files (which would include Berksfile and default_spec.rb)
        expect(result).to include('Files with issues: 3')
        expect(result).not_to include('Files with issues: 5')
      end
    end

    context 'when all files have no offenses' do
      let(:offense_details) do
        {
          'files' => [
            {
              'path' => 'Berksfile',
              'offenses' => []
            },
            {
              'path' => 'metadata.rb',
              'offenses' => []
            }
          ],
          'summary' => {
            'offense_count' => 0
          }
        }
      end

      it 'does not list any files in the changes section' do
        result = described_class.format_pr_description(offense_details)

        expect(result).not_to include('Berksfile')
        expect(result).not_to include('metadata.rb')
        expect(result).to include('Changes Made')
      end
    end

    context 'when there are only non-correctable offenses' do
      let(:offense_details) do
        {
          'files' => [
            {
              'path' => 'test/unit/spec.rb',
              'offenses' => [
                {
                  'cop_name' => 'Chef/Deprecations/ResourceWithoutUnifiedTrue',
                  'correctable' => false,
                  'corrected' => false
                }
              ]
            }
          ],
          'summary' => {
            'offense_count' => 1
          }
        }
      end

      it 'does not list files with only non-correctable offenses' do
        result = described_class.format_pr_description(offense_details)

        expect(result).not_to include('test/unit/spec.rb')
        expect(result).not_to include('Chef/Deprecations/ResourceWithoutUnifiedTrue')
      end
    end
  end
end
