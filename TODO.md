# Pull request tracking

Keep track of the PR number of each repository we open

here is the log output from an existing run
2025-10-09 12:30:51.411611 I [1:1304] CookstyleRunner::GitHubPRManager -- Pull request created successfully -- {repo: "sous-chefs/isc_kea", pr_number: 39, action: "create_pr"}

This tracking data should be put into a KV store such as redis/postgresql for later stats and make it easier to find old PRs that we have opened.

# Cleanup

When closing PRs using the "cleanup_prs" method it should lookup information in this table, close the PR and delete the branch, then remove the corresponding entry in the DB.

#
