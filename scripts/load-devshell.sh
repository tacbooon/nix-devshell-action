#!/usr/bin/env bash

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -- "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE")" && pwd)"
unset SOURCE DIR
DEFAULT_EXPORT_PATH=$'/nix/store/*\n$GITHUB_WORKSPACE/*'

EXPORT_ENV_PATTERNS=()
EXPORT_PATH_PATTERNS=()

# Reads newline-separated patterns from $1, prints trimmed entries NUL-delimited to stdout.
split_lines() {
  local input="$1"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    case "$line" in \#*) continue ;; esac
    printf '%s\0' "$line"
  done <<< "$input"
}

# Escape glob special chars so an expanded path matches literally.
escape_glob() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\*/\\*}"
  s="${s//\?/\\?}"
  s="${s//\[/\\[}"
  s="${s//\]/\\]}"
  printf '%s' "$s"
}

# Expand $GITHUB_WORKSPACE and $PWD in a $PATH pattern.
# Other $-forms are left untouched to avoid unintended expansion.
# Expansion is skipped when the variable is unset/empty, leaving the pattern
# as-is (which then matches nothing) instead of expanding to "/*".
expand_path_pattern() {
  local pat="$1"
  local ws="${GITHUB_WORKSPACE:-}"
  local pwd_val="${PWD:-}"
  local esc
  if [[ -n "$ws" ]]; then
    esc="$(escape_glob "$ws")"
    pat="${pat//\$\{GITHUB_WORKSPACE\}/$esc}"
    pat="${pat//\$GITHUB_WORKSPACE/$esc}"
  fi
  if [[ -n "$pwd_val" ]]; then
    esc="$(escape_glob "$pwd_val")"
    pat="${pat//\$\{PWD\}/$esc}"
    pat="${pat//\$PWD/$esc}"
  fi
  printf '%s' "$pat"
}

# Succeed if $1 matches any of the remaining args as glob patterns.
# Note: callers must not expand an empty array into "$@" here.
matches_any() {
  local target="$1"
  shift || return 1
  local pattern
  for pattern in "$@"; do
    # shellcheck disable=SC2254 # Intentional glob matching
    case "$target" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

try_write_path() {
  local entry="$1"

  [[ -n "$entry" && -d "$entry" ]] || return 0

  [[ ${#EXPORT_PATH_PATTERNS[@]} -eq 0 ]] && return 0
  matches_any "$entry" "${EXPORT_PATH_PATTERNS[@]}" || return 0

  local resolved
  resolved="$(cd -- "$entry" 2>/dev/null && pwd -P)" || return 0
  [[ -n "$resolved" ]] || return 0
  if [[ ":$PATH:" == *":$entry:"* || ":$PATH:" == *":$resolved:"* ]]; then
    return 0
  fi

  echo "PATH: $resolved"
  echo "$resolved" >> "$GITHUB_PATH"
  PATH="$resolved:$PATH"
}

try_write_env() {
  local name="$1"
  local value="$2"
  local delimiter
  delimiter="EOF_$(openssl rand -hex 16)"
  [[ ${#EXPORT_ENV_PATTERNS[@]} -eq 0 ]] && return 0
  matches_any "$name" "${EXPORT_ENV_PATTERNS[@]}" || return 0
  echo "ENV: $name"
  printf '%s<<%s\n%s\n%s\n' "$name" "$delimiter" "$value" "$delimiter" >> "$GITHUB_ENV"
}

main() {
  # Inputs are passed via env (see action.yml) to avoid script injection.
  # Positional args remain as a fallback for direct local execution.
  # NOTE: use '-' (not ':-') so an explicitly empty input stays empty.
  # This lets users disable PATH export with `export-path: ''` as documented.
  local flake="${FLAKE:-${1:-.}}"
  local export_env="${EXPORT_ENV-${2-}}"
  local export_path="${EXPORT_PATH-${3-$DEFAULT_EXPORT_PATH}}"
  local line

  if ! command -v nix >/dev/null 2>&1; then
    echo "error: 'nix' command not found. Install Nix with Flakes enabled before using this action (e.g. cachix/install-nix-action)." >&2
    return 1
  fi
  if ! command -v openssl >/dev/null 2>&1; then
    echo "error: 'openssl' command not found." >&2
    return 1
  fi
  if [[ -z "${GITHUB_ENV:-}" ]]; then
    echo "error: GITHUB_ENV is not set. This action must run inside GitHub Actions." >&2
    return 1
  fi
  if [[ -z "${GITHUB_PATH:-}" ]]; then
    echo "error: GITHUB_PATH is not set. This action must run inside GitHub Actions." >&2
    return 1
  fi

  while IFS= read -r -d '' line; do
    EXPORT_ENV_PATTERNS+=("$line")
  done < <(split_lines "${export_env}")
  while IFS= read -r -d '' line; do
    line="$(expand_path_pattern "$line")"
    [[ -z "$line" ]] && continue
    EXPORT_PATH_PATTERNS+=("$line")
  done < <(split_lines "${export_path}")

  # Keep it global so the EXIT trap can reference it.
  workdir="$(mktemp -d)"
  trap 'rm -rf -- "$workdir"' EXIT

  # Generate shell code that sets up the devShell environment.
  local setup_dev_env="$workdir/setup-dev-env.sh"
  if ! nix print-dev-env --no-write-lock-file -- "$flake" > "$setup_dev_env"; then
    echo "error: failed to run 'nix print-dev-env' for flake '$flake'." >&2
    return 1
  fi

  # Capture the environment defined by the devShell by executing setup-dev-env.sh with bash.
  # Run it in a clean environment by preventing external scripts from being sourced.
  local dev_env="$workdir/dev-env"
  local capture_dev_env="$SCRIPT_DIR/capture-dev-env.sh"
  env -u BASH_ENV -u ENV bash --noprofile --norc "$capture_dev_env" "$setup_dev_env" > "$dev_env"

  while IFS="=" read -r -d '' name value; do
    if [[ "$name" == "PATH" ]]; then
      local paths=()
      IFS=: read -r -a paths <<< "$value"
      for ((i = ${#paths[@]} - 1; i >= 0; i--)); do
        try_write_path "${paths[i]}"
      done
    else
      try_write_env "$name" "$value"
    fi
  done < "$dev_env"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
