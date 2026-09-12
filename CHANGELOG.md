# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-09-12

### Fixed

- Add `BASH_ENV` and `ENV` to the denylist so a devShell can no longer
  propagate them to later steps via `$GITHUB_ENV` (#1).

### Added

- Add `update-major-tag` workflow that moves the floating `v1` / `v1.2`
  tags when a release tag like `v1.2.3` is pushed (#2).

### Changed

- Clarify the `flake` input description with an attribute-selection
  example (`.#ci`) (#4).
- Scope the test workflow triggers to the `main` branch to avoid
  duplicate runs on pull requests (#5).

### Tests

- Add a regression test verifying devShell `PATH` priority is preserved
  when two directories provide the same tool (#3).

## [1.0.0] - 2026-09-12

- Initial release.

[Unreleased]: https://github.com/tacbooon/nix-devshell-action/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/tacbooon/nix-devshell-action/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/tacbooon/nix-devshell-action/releases/tag/v1.0.0
