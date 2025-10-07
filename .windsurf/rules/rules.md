---
trigger: always_on
description: development and coding standards for an AI agent.
---

## 1. AI Interaction & Response Format

- **State Applied Rules**: Start responses with `Applying: [Rule, Another Rule]` to declare the guiding principles for the change.
- **Acknowledge Context**: Before implementing, explicitly reference the specific files, methods, or memories that inform the approach.

---

## 2. Core Philosophy & Goals

- **Primary Goal**: Produce code that is **production-ready**, **secure**, and has a **small memory footprint**.
- **Production-Ready Code**: Code must be complete and self-contained. Do not use placeholders or `TODOs` in production files. Ensure all dependencies are included.
- **Efficiency**: Strive for maximum efficiency and optimal outcomes.

---

## 3. Development Cycle & Workflow

- **Test-First (TDD)**: Always write or update a failing test *before* writing production code. Show the test output to prove the **Red → Green** transition.
- **One Change at a Time**: Modify only one method per iteration. Keep changes small, atomic, and verifiable.
- **Verify Each Step**: Run RSpec and RuboCop after every single change. Explicitly show the passing output before proceeding to the next step.
- **Focused Commits**: Make one logical change per commit using the Conventional Commits format.
- **Code Reviews**: Conduct regular code reviews and refactoring.
- **CI/CD Gate**: All automated tests and checks must pass before merging.

---

## 4. Code Quality & Architecture (Ruby)

- **Readability**: Prioritize code that is readable, efficient, and well-documented.
- **Extract, Don't Expand**: When complexity increases, extract internal helper methods rather than expanding public methods. Keep public APIs stable.
- **Single Responsibility**: Keep classes and methods lean and focused on a single responsibility.
- **Guard Clauses**: Use guard clauses for early returns to reduce nesting.
- **Code Hygiene**:
  - Delete unused code immediately; do not comment it out.
  - Remove all `TODO` comments before finalizing code.
  - Avoid global variables and mutable state.
- **Error Handling**: Implement robust error handling and logging.
- **Dependency Management**: Use dependency injection to manage dependencies.
- **Service Objects**: Implement service objects for complex business logic.

---

## 5. Static Typing (Ruby Sorbet)

- **Strict Compliance**: All code must comply with Sorbet `strict` mode as part of the production-ready standard.
- **Coverage**: Apply type hints to all variables and method parameters.
- **Prohibited Type**:
  - Do not use `T.untyped`.
  - Do not use `T.unsafe`

---

## 6. Testing (RSpec)

- **RSpec Mocks**: Use `have_received` for message expectation tests.
- **Test Data**: Write realistic and logical test data.
- **Fixtures**:
  - Ensure no duplicate fixtures.
  - Avoid where possible; prefer factory methods or setup blocks.
- **Test Coverage**: Aim for 100% test coverage on all new and modified code

---

## 7. Documentation

- **Consistency**: Maintain consistency across all project documentation.
- **Linting**: All Markdown files must pass `markdown-lint-cli2` base rules.
- **Comprehensive**: Ensure documentation is thorough and up-to-date.
