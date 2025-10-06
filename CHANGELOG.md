# Changelog

## Unreleased

### Added

- Pretty table output format using `table_tennis` gem
- `--format pretty` option for CLI list command
- Enhanced table rendering with borders and zebra striping
- Configuration validation for output_format setting

### Changed

- Updated `tty-progressbar` dependency to support `table_tennis`

## 2.0.0 - *2021-08-11*

- Breaking Change: Defaults to looking for main branches, introduces new cli arg for setting default branch name

## 1.4.3 - *2020-11-18*

- Removed branch cleanup workflow as now using github repo settings

## 1.4.2 - *2020-11-18*

- Fixed bug with dockerhub push due to set-env deprecation

## 1.4.1 - *2020-10-25*

- Resolved issues with pagination:
  - Set auth headers correctly
  - Removed duplicate results from being added

## 1.3.1

Stop `"` blowing up the builds

## 1.3.0

Remove Chef Workstation as cookstyle is not up to date there
Installs cookstyle manually

## 1.2.0

Removed user configurable pull request body
Pull request body now has the cookstyle version in it

## 1.1.1

Make change log marker case insensitive

## 1.0.0

Full initial release of the application with all functionality working
