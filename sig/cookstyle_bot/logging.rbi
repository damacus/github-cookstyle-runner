# typed: strong
# frozen_string_literal: true

module CookstyleBot
  module Logging
    extend T::Sig

    sig { returns(::Logger) }
    def self.logger; end

    sig { params(settings: T.nilable(CookstyleBot::Settings)).returns(::Logger) }
    def self.setup_logger(settings = nil); end
  end
end
