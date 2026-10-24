# AGENTS.md

This repository provides a composite GitHub Action backed by Bash scripts that loads a Nix devShell environment into later workflow steps.

## Environments

- Nix flakes for the contributor devShell (`flake.nix`).
- Linux and macOS runners only; Windows is unsupported.

## Commands

- Run tests: `bats tests/`
- Run ShellCheck: `shellcheck scripts/*.sh` and `shellcheck --severity=warning tests/*.bats`
- Format: `nix fmt`
- Format check: `nix fmt -- --ci`
- Lint workflows: `jactionlint`

## Releases

- Use annotated `vX.Y.Z` tags. Pushing one triggers `update-major-tag.yml`, which moves `vX` and `vX.Y`.
- Before tagging, move `Unreleased` changelog entries in `CHANGELOG.md` to the new version and update the comparison links.

## Conventions

- Keep `README.md` and `README-ja.md` in sync.
- Write code comments, error messages, and commit messages in English.
- Do not push or create releases unless asked.
