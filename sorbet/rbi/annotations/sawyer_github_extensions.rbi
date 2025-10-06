# typed: true

# Extensions for Sawyer::Resource to include GitHub-specific attributes
# This allows Sorbet to understand dynamic attributes from GitHub API responses

class Sawyer::Resource
  # GitHub Pull Request attributes
  sig { returns(Integer) }
  def number; end

  sig { params(value: Integer).returns(Integer) }
  def number=(value); end

  # GitHub Issue attributes (PRs are also issues)
  sig { returns(String) }
  def state; end

  sig { returns(String) }
  def title; end

  sig { returns(String) }
  def body; end

  sig { returns(T.nilable(String)) }
  def html_url; end

  # Head reference for PRs
  sig { returns(T.untyped) }
  def head; end

  # Base reference for PRs
  sig { returns(T.untyped) }
  def base; end
end
