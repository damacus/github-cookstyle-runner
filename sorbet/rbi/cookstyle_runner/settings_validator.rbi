# typed: strict

module CookstyleRunner
  class SettingsValidator
    extend T::Sig

    sig { params(data: T.untyped).returns(T.untyped) }
    def validate(data); end

    sig { params(config: T.untyped).returns(T::Array[String]) }
    def self.validate(config); end

    sig { params(config: T.untyped).returns(T::Array[String]) }
    def self.validate_auth_requirements(config); end

    sig { params(config: T.untyped).returns(T::Boolean) }
    def self.token_auth_configured?(config); end

    sig { params(config: T.untyped).returns(T::Boolean) }
    def self.app_auth_configured?(config); end

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.value?(value); end
  end
end
