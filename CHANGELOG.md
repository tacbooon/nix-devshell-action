# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Features

- Add a `working-directory` input so the action can run in a subdirectory of a monorepo. Relative `flake` paths and `$PWD` in `export-path` are resolved from that directory.

### Improvements

- Add `LD_PRELOAD`, `LD_AUDIT`, `DYLD_INSERT_LIBRARIES`, `NODE_OPTIONS`, `PROMPT_COMMAND`, and `PS4` to the denylist so a broad `export-env` pattern cannot inject code into later steps.
- Improve performance for devShells that define many environment variables by generating the `GITHUB_ENV` delimiter only after a variable matches an `export-env` pattern. Previously, `openssl` ran once for every variable, including those that were filtered out.

### Bug Fixes

- Fail with an error when the devShell setup script, including its `shellHook`, exits before the environment capture completes, instead of silently exporting nothing.
- Match `export-path` patterns against the resolved physical path, so a symlink or `..` segment under an allowed prefix cannot add a directory outside it.

### Documentation

- Document supported runners, required tools, PATH deduplication, the limitation around unset variables, and commands for running tests and linters locally.

### Maintenance

- Add `nixfmt-tree` as the repository formatter and run `nix fmt -- --ci` in the test workflow.
- Replace `actionlint` and `zizmor` with `jactionlint`, which covers both workflow linting and security auditing.
- Add the `nixpkgs-extras` flake input (which provides `jactionlint`) and update `flake.lock`.
- Use GitHub Actions self-repository syntax (`$/`) for local action references in workflows.
- Use `bash` as the default shell for workflow `run` steps.
- Prevent the floating `v1` / `v1.x` tags from moving backwards when an older release, such as a backport, is pushed.
- Check in CI that unexported and denylisted variables are not propagated to later steps, and run ShellCheck on Bats test files.
- Add ARM64 Linux coverage to the test matrix, pin the Linux runner to Ubuntu 26.04, and include the runner architecture in the Nix cache key.

## [1.1.0] - 2026-09-12

### Improvements

- Add `BASH_ENV` and `ENV` to the denylist so a devShell can no longer propagate them to later steps via `$GITHUB_ENV` (#1).

### Documentation

- Clarify the `flake` input description with an attribute-selection example (`.#ci`) (#4).

### Maintenance

- Add `update-major-tag` workflow that moves the floating `v1` / `v1.2` tags when a release tag like `v1.2.3` is pushed (#2).
- Scope the test workflow triggers to the `main` branch to avoid duplicate runs on pull requests (#5).
- Add a regression test verifying devShell `PATH` priority is preserved when two directories provide the same tool (#3).

## [1.0.0] - 2026-09-12

- Initial release.

[Unreleased]: https://github.com/tacbooon/nix-devshell-action/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/tacbooon/nix-devshell-action/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/tacbooon/nix-devshell-action/releases/tag/v1.0.0
