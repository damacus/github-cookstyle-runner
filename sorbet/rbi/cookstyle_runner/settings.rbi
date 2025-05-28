# typed: true
# frozen_string_literal: true

# This file is an RBI (Ruby Interface) file for Sorbet static type checking.
# It provides type signatures for the Settings class used by the config gem.

# Settings class from the config gem
class Settings
  extend T::Sig

  # Branch name for Git operations
  sig { returns(String) }
  def self.branch_name; end

  # Other common Settings methods that might be used
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def self.to_hash; end

  sig { params(key: T.any(String, Symbol)).returns(T.untyped) }
  def self.[](key); end
end
