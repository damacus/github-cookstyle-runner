module CookstyleRunner
  module Reporter
    # This class is responsible for reporting the results of the Cookstyle run.
    class Reporter
      def initialize(cookstyle_runner)
        @cookstyle_runner = cookstyle_runner
      end

      # Aggregates results from parallel processing
      # @param results [Array<Hash>] Array of result hashes from RepositoryProcessor
      # @return [Array<Integer>] counts for [processed, issues, skipped, errors]
      def aggregate_results(results)
        processed_count = 0
        issues_found_count = 0
        skipped_count = 0
        error_count = 0

        results.each do |result|
          case result[:status]
          when :no_issues
            processed_count += 1 # Count successful processing without issues
          when :issues_found
            processed_count += 1
            issues_found_count += 1
          when :skipped
            skipped_count += 1
          when :error
            error_count += 1
            logger.error("Error occurred processing repository: #{result[:repo_name]}. Message: #{result[:error_message]}")
          else
            logger.warn("Unknown status '#{result[:status]}' received for repository: #{result[:repo_name]}")
            error_count += 1 # Treat unknown status as an error
          end

          # Collect artifact details if available
          @created_artifacts << result[:pr_details] if result[:pr_details]

          # Collect artifact creation error if available
          @artifact_creation_errors << result[:pr_error] if result[:pr_error]
        end
        [processed_count, issues_found_count, skipped_count, error_count]
      end

      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
      # Ignoring rubocop warnings for method length and parameter lists
      # Reports the summary of the application run
      # @param total_repos [Integer] Total repositories considered
      # @param processed_count [Integer] Number of repositories processed
      # @param issues_count [Integer] Number of repositories with issues
      # @param skipped_count [Integer] Number of repositories skipped
      # @param error_count [Integer] Number of repositories with errors
      # @param issues_created [Integer] Number of issues created
      # @param prs_created [Integer] Number of pull requests created
      # @param issue_errors [Integer] Number of issue creation errors
      # @param pr_errors [Integer] Number of pull request creation errors
      # @return [String] Summary report
      def summary(total_repos:, processed_count:, issues_count:, skipped_count:, error_count:,
                  issues_created:, prs_created:, issue_errors:, pr_errors:)
        summary = <<~SUMMARY
          --- Summary ---
          Total repositories considered: #{total_repos}
          Successfully processed: #{processed_count}
          Found issues in: #{issues_count} repositories.
          Skipped: #{skipped_count} repositories.
          Errors: #{error_count} repositories.

          --- Artifact Creation ---
          Issues Created: #{issues_created}
          Pull Requests Created: #{prs_created}
          Issue Creation Errors: #{issue_errors}
          PR Creation Errors: #{pr_errors}
        SUMMARY
        logger.info(summary.strip)
        summary
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

      # rubocop:disable Metrics/MethodLength
      def created_artifacts(created_artifacts:)
        artifact_report = ["--- Created Artifacts (#{created_artifacts.size}) ---"]

        created_artifacts.each do |artifact|
          artifact_report << <<~ARTIFACT_ENTRY
            Repository: #{artifact[:repo]}
            Artifact ##{artifact[:number]}: #{artifact[:title]}
            Type: #{artifact[:type]}
            URL: #{artifact[:url]}
          ARTIFACT_ENTRY
        end

        if created_artifacts.any?
          logger.info(artifact_report.join("\n").strip)
        else
          logger.info('No artifacts were created during this run.')
        end
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength
      def artifact_creation_error(artifact_creation_errors = [])
        artifact_error_report = ["--- Artifact Creation Errors (#{artifact_creation_errors.size}) ---"]
        artifact_creation_errors.each do |error|
          artifact_error_report << <<~ARTIFACT_ERROR_ENTRY
            Repository: #{error[:repo]}
            Error: #{error[:message]}
            Type: #{error[:type]}
          ARTIFACT_ERROR_ENTRY
        end
        if artifact_creation_errors.any?
          logger.info(artifact_error_report.join("\n").strip)
        else
          logger.info('No artifact creation errors were reported.')
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
