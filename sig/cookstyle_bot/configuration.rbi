# typed: strict
module CookstyleBot
  class Settings < ::Config::Options
    # This RBI will need to be fleshed out or auto-generated
    # to reflect the actual structure from settings.yml for Sorbet.
    # For now, it's a placeholder.
    # Example for one top-level setting:
    # sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    # def logging; end
  end
end
