#!/usr/bin/env bats

# Unit tests for scripts/load-devshell.sh helper functions.
# These tests source the script (main is guarded) and exercise the
# pure filtering logic without requiring Nix.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/scripts/load-devshell.sh"

  TEST_TMPDIR="$(mktemp -d)"
  export GITHUB_ENV="$TEST_TMPDIR/github_env"
  export GITHUB_PATH="$TEST_TMPDIR/github_path"
  touch "$GITHUB_ENV" "$GITHUB_PATH"

  EXPORT_ENV_PATTERNS=()
  EXPORT_PATH_PATTERNS=()
  # Save original PATH for tests that mutate it.
  ORIGINAL_PATH="$PATH"
}

teardown() {
  PATH="$ORIGINAL_PATH"
  rm -rf "$TEST_TMPDIR"
}

# --- split_lines ---

@test "split_lines: trims whitespace and skips empty lines and comments" {
  input=$'  APP_*  \n\n# comment\n   # indented comment\nDB_*\n   \nPATH_*'
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    while IFS= read -r -d "" line; do printf "[%s]\n" "$line"; done < <(split_lines "$2")
  ' _ "$REPO_ROOT" "$input"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "[APP_*]" ]
  [ "${lines[1]}" = "[DB_*]" ]
  [ "${lines[2]}" = "[PATH_*]" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "split_lines: empty input produces no output" {
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    while IFS= read -r -d "" line; do echo "unexpected: $line"; done < <(split_lines "$2")
  ' _ "$REPO_ROOT" ""
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# --- expand_path_pattern ---

@test "expand_path_pattern: expands \$GITHUB_WORKSPACE and \$PWD" {
  export GITHUB_WORKSPACE="/tmp/workspace"
  mkdir -p "$TEST_TMPDIR/workdir"
  # NOTE: PWD is managed by bash itself, so it cannot be faked via export.
  # Test $PWD expansion by actually changing directory in the subshell.
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    expand_path_pattern "\$GITHUB_WORKSPACE/*"
    echo
    expand_path_pattern "\${GITHUB_WORKSPACE}/*"
    echo
    cd "$2"
    expand_path_pattern "\$PWD/*"
    echo
    expand_path_pattern "\${PWD}/*"
  ' _ "$REPO_ROOT" "$TEST_TMPDIR/workdir"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/tmp/workspace/*" ]
  [ "${lines[1]}" = "/tmp/workspace/*" ]
  [ "${lines[2]}" = "$TEST_TMPDIR/workdir/*" ]
  [ "${lines[3]}" = "$TEST_TMPDIR/workdir/*" ]
}

@test "expand_path_pattern: leaves other variables untouched" {
  export GITHUB_WORKSPACE="/tmp/workspace"
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    expand_path_pattern "\$HOME/*"
    echo
    expand_path_pattern "/nix/store/*"
  ' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "\$HOME/*" ]
  [ "${lines[1]}" = "/nix/store/*" ]
}

@test "expand_path_pattern: does not expand when variable is unset" {
  unset GITHUB_WORKSPACE || true
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    expand_path_pattern "\$GITHUB_WORKSPACE/*"
  ' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "\$GITHUB_WORKSPACE/*" ]
}

@test "expand_path_pattern: escapes glob chars in expanded value" {
  export GITHUB_WORKSPACE="/tmp/my [bracket]*dir"
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    expand_path_pattern "\$GITHUB_WORKSPACE/*"
  ' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = '/tmp/my \[bracket\]\*dir/*' ]
}

# --- matches_any ---

@test "matches_any: matches glob patterns" {
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    matches_any "APP_NAME" "APP_*" "DB_*"
  ' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "matches_any: returns non-zero when nothing matches" {
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    matches_any "MYAPP_URL" "APP_*" "DB_*"
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
}

# --- try_write_env ---

@test "try_write_env: writes matching vars in heredoc format" {
  EXPORT_ENV_PATTERNS=("APP_*" "DB_*")
  try_write_env "APP_NAME" "my-app"
  grep -q '^APP_NAME<<EOF_' "$GITHUB_ENV"
  grep -q '^my-app$' "$GITHUB_ENV"
}

@test "try_write_env: skips non-matching vars" {
  EXPORT_ENV_PATTERNS=("APP_*")
  try_write_env "OTHER_VAR" "value"
  [ ! -s "$GITHUB_ENV" ]
}

@test "try_write_env: writes nothing when no patterns configured" {
  EXPORT_ENV_PATTERNS=()
  try_write_env "APP_NAME" "my-app"
  [ ! -s "$GITHUB_ENV" ]
}

@test "try_write_env: preserves multiline values" {
  EXPORT_ENV_PATTERNS=("APP_*")
  try_write_env "APP_MULTILINE" $'line1\nline2'
  grep -q '^line1$' "$GITHUB_ENV"
  grep -q '^line2$' "$GITHUB_ENV"
}

# --- try_write_path ---

@test "try_write_path: writes matching existing dirs to GITHUB_PATH" {
  mkdir -p "$TEST_TMPDIR/fakebin"
  EXPORT_PATH_PATTERNS=("$TEST_TMPDIR/*")
  # Ensure the dir is not already on PATH.
  PATH="/usr/bin:/bin"
  try_write_path "$TEST_TMPDIR/fakebin"
  grep -q "$TEST_TMPDIR/fakebin" "$GITHUB_PATH"
}

@test "try_write_path: skips non-matching dirs" {
  mkdir -p "$TEST_TMPDIR/fakebin"
  EXPORT_PATH_PATTERNS=("/nix/store/*")
  PATH="/usr/bin:/bin"
  try_write_path "$TEST_TMPDIR/fakebin"
  [ ! -s "$GITHUB_PATH" ]
}

@test "try_write_path: skips non-existent dirs" {
  EXPORT_PATH_PATTERNS=("*")
  PATH="/usr/bin:/bin"
  try_write_path "$TEST_TMPDIR/does-not-exist"
  [ ! -s "$GITHUB_PATH" ]
}

@test "try_write_path: skips dirs already on PATH" {
  mkdir -p "$TEST_TMPDIR/fakebin"
  EXPORT_PATH_PATTERNS=("$TEST_TMPDIR/*")
  PATH="$TEST_TMPDIR/fakebin:/usr/bin:/bin"
  try_write_path "$TEST_TMPDIR/fakebin"
  [ ! -s "$GITHUB_PATH" ]
}

@test "try_write_path: writes nothing when no patterns configured" {
  mkdir -p "$TEST_TMPDIR/fakebin"
  EXPORT_PATH_PATTERNS=()
  PATH="/usr/bin:/bin"
  try_write_path "$TEST_TMPDIR/fakebin"
  [ ! -s "$GITHUB_PATH" ]
}

# --- main error handling (no Nix required) ---

@test "main: fails when GITHUB_ENV is not set" {
  unset GITHUB_ENV
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    main "."
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_ENV is not set"* ]]
}

@test "main: fails when GITHUB_PATH is not set" {
  unset GITHUB_PATH
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    main "."
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_PATH is not set"* ]]
}

@test "main: fails when nix command is missing" {
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    PATH="/usr/bin:/bin" main "."
  ' _ "$REPO_ROOT"
  # /usr/bin:/bin has no nix on GitHub runners without install-nix-action.
  # If nix happens to be there, the test still validates error text on failure.
  if [ "$status" -ne 0 ]; then
    [[ "$output" == *"'nix' command not found"* ]]
  else
    skip "nix found on PATH, cannot test missing-nix path"
  fi
}

@test "main: fails when nix print-dev-env fails" {
  fakebin="$TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  printf '#!/usr/bin/env bash\necho "mock nix failure" >&2\nexit 1\n' > "$fakebin/nix"
  chmod +x "$fakebin/nix"
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    export PATH="$2:$PATH"
    main "."
  ' _ "$REPO_ROOT" "$fakebin"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to run 'nix print-dev-env'"* ]]
}

@test "main: end-to-end with mocked nix (env + PATH filtering)" {
  fakebin="$TEST_TMPDIR/fakebin"
  fakepathdir="$TEST_TMPDIR/newpath"
  mkdir -p "$fakebin" "$fakepathdir"
  # Mock `nix print-dev-env` to emit a setup script that exports vars and PATH.
  cat > "$fakebin/nix" <<MOCK
#!/usr/bin/env bash
echo "export MOCK_APP_VAR='mock-value'"
echo "export MOCK_OTHER_VAR='should-be-filtered'"
echo "export PATH=\"$fakepathdir:\$PATH\""
MOCK
  chmod +x "$fakebin/nix"

  run bash -c '
    source "$1/scripts/load-devshell.sh"
    export PATH="$2:$PATH"
    export FLAKE="."
    export EXPORT_ENV="MOCK_APP_*"
    export EXPORT_PATH="$3/*"
    main
  ' _ "$REPO_ROOT" "$fakebin" "$TEST_TMPDIR"
  [ "$status" -eq 0 ]
  grep -q '^MOCK_APP_VAR<<EOF_' "$GITHUB_ENV"
  grep -q '^mock-value$' "$GITHUB_ENV"
  if grep -q 'MOCK_OTHER_VAR' "$GITHUB_ENV"; then
    echo "MOCK_OTHER_VAR should have been filtered" >&2
    exit 1
  fi
  grep -q "$fakepathdir" "$GITHUB_PATH"
}

@test "main: empty EXPORT_PATH disables PATH export" {
  fakebin="$TEST_TMPDIR/fakebin"
  fakepathdir="$TEST_TMPDIR/newpath"
  mkdir -p "$fakebin" "$fakepathdir"
  cat > "$fakebin/nix" <<MOCK
#!/usr/bin/env bash
echo "export MOCK_APP_VAR='mock-value'"
echo "export PATH=\"$fakepathdir:\$PATH\""
MOCK
  chmod +x "$fakebin/nix"

  run bash -c '
    source "$1/scripts/load-devshell.sh"
    export PATH="$2:$PATH"
    export FLAKE="."
    export EXPORT_ENV="MOCK_APP_*"
    export EXPORT_PATH=""
    main
  ' _ "$REPO_ROOT" "$fakebin"
  [ "$status" -eq 0 ]
  grep -q '^MOCK_APP_VAR<<EOF_' "$GITHUB_ENV"
  [ ! -s "$GITHUB_PATH" ]
}

@test "main: fails when openssl command is missing" {
  fakebin="$TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/nix" <<'MOCK'
#!/usr/bin/env bash
echo "export MOCK_APP_VAR='mock-value'"
MOCK
  chmod +x "$fakebin/nix"
  # Minimal PATH with only the nix mock: openssl must not be resolvable.
  # The openssl check runs before any other external tool, so no other
  # entries are needed. Skip if openssl lives in the mock dir (never).
  run bash -c '
    source "$1/scripts/load-devshell.sh"
    export PATH="$2"
    export FLAKE="."
    export EXPORT_ENV="MOCK_APP_*"
    export EXPORT_PATH=""
    if command -v openssl >/dev/null 2>&1; then
      echo "openssl unexpectedly found on minimal PATH" >&2
      exit 99
    fi
    main
  ' _ "$REPO_ROOT" "$fakebin"
  [ "$status" -ne 0 ]
  [ "$status" -ne 99 ]
  [[ "$output" == *"'openssl' command not found"* ]]
}
