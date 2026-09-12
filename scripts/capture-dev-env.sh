#!/usr/bin/env bash

set -euo pipefail

setup_dev_env="$1"

workdir="$(mktemp -d)"
trap 'rm -rf -- "$workdir"' EXIT

ENV_BIN="$(command -v env)"
base_env="$workdir/base_env"
merged_env="$workdir/merged_env"

# Dump the environments before and after sourcing setup_dev_env into files for later comparison.
# The devShell hooks do not expect strict mode; disable it while sourcing so a non-zero status or
# unset variable in the hook does not abort the capture.
"$ENV_BIN" -0 > "$base_env"
set +e +u
set +o pipefail
source "$setup_dev_env" >&2
set -euo pipefail
"$ENV_BIN" -0 > "$merged_env"

# Store the pre-execution environment for lookups.
base_keys=()
base_vals=()
while IFS='=' read -r -d '' key val; do
  base_keys+=("$key")
  base_vals+=("$val")
done < "$base_env"

# Output only variables that were added or changed in the post-execution environment.
while IFS='=' read -r -d '' name value; do
  if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    continue
  fi
  case "$name" in
    _ |\
    ACTIONS_* |\
    BASHOPTS |\
    BASH_ENV |\
    CI |\
    ENV |\
    EUID |\
    GITHUB_* |\
    IFS |\
    OLDPWD |\
    PPID |\
    PWD |\
    RUNNER_* |\
    SHELLOPTS |\
    SHLVL |\
    UID)
      continue ;;
  esac
  found=0
  base_value=""
  for ((i = 0; i < ${#base_keys[@]}; i++)); do
    if [[ "${base_keys[i]}" == "$name" ]]; then
      found=1
      base_value="${base_vals[i]}"
      break
    fi
  done
  if ((found == 0)) || [[ "$base_value" != "$value" ]]; then
    printf '%s=%s\0' "$name" "$value"
  fi
done < "$merged_env"
