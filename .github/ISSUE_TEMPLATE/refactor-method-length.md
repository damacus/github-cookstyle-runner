---
name: Refactor MethodLength Violations
about: Technical debt - methods exceeding 15 lines need extraction
title: 'Refactor: Fix 9 Metrics/MethodLength violations'
labels: technical-debt, refactoring, code-quality
assignees: ''
---

## Summary

We have 9 methods across 6 files that exceed the RuboCop `Metrics/MethodLength` limit of 15 lines. These need to be refactored by extracting helper methods to improve readability and maintainability.

## Current Violations

### 1. `config/initializers/config.rb:51` - `map_environment_variables` (1 violation)

- **Issue**: `Naming/PredicateMethod` - Method name doesn't follow predicate naming convention
- **Lines**: Method needs review for naming

### 2. `lib/cookstyle_runner/authentication.rb:56` - `initialize`

- **Current**: 22 lines
- **Target**: ≤15 lines
- **Suggested fix**: Extract credential validation logic into private helper methods

### 3. `lib/cookstyle_runner/config_manager.rb:26` - `log_config_summary`

- **Current**: 41 lines
- **Target**: ≤15 lines
- **Suggested fix**: Extract logging sections into separate methods:
  - `log_github_config`
  - `log_processing_config`
  - `log_cache_config`

### 4. `lib/cookstyle_runner/configuration.rb:112` - `initialize`

- **Current**: 38 lines
- **Target**: ≤15 lines
- **Suggested fix**: Extract configuration steps:
  - `load_settings`
  - `validate_settings`
  - `apply_environment_overrides`

### 5. `lib/cookstyle_runner/github_pr_manager.rb:51` - `create_pull_request`

- **Current**: 20 lines
- **Target**: ≤15 lines
- **Suggested fix**: Extract PR body formatting and error handling

### 6. `lib/cookstyle_runner/github_pr_manager.rb:81` - `create_issue`

- **Current**: 19 lines
- **Target**: ≤15 lines
- **Suggested fix**: Extract issue body formatting and error handling

### 7. `lib/cookstyle_runner/repository_processor.rb:63` - `process_repository`

- **Current**: 42 lines
- **Target**: ≤15 lines
- **Suggested fix**: Extract major workflow steps:
  - `setup_repository`
  - `run_cookstyle_analysis`
  - `handle_results`
  - `cleanup_repository`

### 8. `lib/cookstyle_runner/repository_processor.rb:200` - `handle_auto_correctable_issues`

- **Current**: 55 lines (LARGEST)
- **Target**: ≤15 lines
- **Suggested fix**: Extract workflow steps:
  - `prepare_branch_for_fixes`
  - `apply_cookstyle_fixes`
  - `commit_and_push_changes`
  - `create_pull_request_for_fixes`

### 9. `lib/cookstyle_runner/settings_validator.rb:37` - `schema`

- **Current**: 21 lines
- **Target**: ≤15 lines
- **Suggested fix**: Extract schema sections:
  - `github_auth_schema`
  - `processing_options_schema`
  - `cache_config_schema`

## Refactoring Guidelines

1. **Extract Private Methods**: Create well-named private helper methods
2. **Single Responsibility**: Each method should do one thing
3. **Maintain Tests**: Ensure all existing tests pass after refactoring
4. **Add Tests**: Consider adding tests for new extracted methods
5. **Preserve Behavior**: No functional changes, only structural improvements
6. **Document Intent**: Use clear method names that explain what they do

## Benefits

- **Readability**: Shorter methods are easier to understand
- **Testability**: Smaller methods are easier to test in isolation
- **Maintainability**: Changes are localized to specific helper methods
- **Reusability**: Extracted methods can potentially be reused
- **Compliance**: Meets RuboCop style guidelines

## Acceptance Criteria

- [ ] All 9 methods refactored to ≤15 lines
- [ ] All existing tests pass
- [ ] RuboCop reports 0 `Metrics/MethodLength` violations
- [ ] Code review confirms improved readability
- [ ] No functional changes (behavior preserved)

## Related

- Current test coverage: 177 examples
- RuboCop compliance: 9 violations remaining
- Part of ongoing code quality improvements

## Priority

**Medium** - These are working methods with good test coverage. The refactoring improves code quality but doesn't fix bugs or add features.
