# typed: strong
# frozen_string_literal: true

module CookstyleBot
  extend T::Sig

  class Error < StandardError; end

  sig { returns(::Logger) }
  private_class_method def self.logger; end

  sig { void }
  def self.run; end
end
