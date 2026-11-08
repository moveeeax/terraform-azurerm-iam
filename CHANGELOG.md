# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- ABAC conditions on role assignments: optional `condition` and
  `condition_version` attributes on `role_assignments`. `condition_version`
  defaults to `"2.0"` when a condition is set and stays null otherwise, so
  existing assignments plan unchanged.
- `privileged_requires_condition` (default `false`). When true, Owner, User
  Access Administrator and Role Based Access Control Administrator assignments
  pass the privileged-role gate without `allow_privileged_roles` if their
  condition constrains `Microsoft.Authorization/roleAssignments` actions, and
  are rejected without one even when `allow_privileged_roles = true`.

## [1.1.0] - 2026-11-05

### Changed

- Allow azurerm 5.x (`>= 3.87, < 6.0`).
- CI: group Dependabot updates monthly and auto-merge patches; add the azurerm
  tflint ruleset; restore CI action bumps that were lost from main.

## [1.0.0]

Initial release (`v0.1.0` points at the same commit).

[Unreleased]: https://github.com/moveeeax/terraform-azurerm-iam/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/moveeeax/terraform-azurerm-iam/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/moveeeax/terraform-azurerm-iam/releases/tag/v1.0.0
