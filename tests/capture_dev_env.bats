#!/usr/bin/env bats

# Unit tests for scripts/capture-dev-env.sh.
# The script diffs the environment before/after sourcing a generated
# setup script and prints added/changed vars NUL-delimited.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CAPTURE="$REPO_ROOT/scripts/capture-dev-env.sh"
  TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Helper: run capture with a given setup script, print result as lines.
# Usage: capture_lines <setup-script>
capture_lines() {
  env -u BASH_ENV -u ENV bash --noprofile --norc "$CAPTURE" "$1" 2>/dev/null | tr '\0' '\n'
}

@test "capture: outputs newly added variables" {
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
export CAPTURE_TEST_NEW_VAR="hello123"
EOF
  run capture_lines "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CAPTURE_TEST_NEW_VAR=hello123"* ]]
}

@test "capture: outputs changed variables" {
  export CAPTURE_TEST_CHANGED_VAR="before"
  run bash -c '
    capture="$1"; setup="$2"
    printf "%s\n" "export CAPTURE_TEST_CHANGED_VAR=\"after\"" > "$setup"
    env -u BASH_ENV -u ENV bash --noprofile --norc "$capture" "$setup" 2>/dev/null | tr "\0" "\n"
  ' _ "$CAPTURE" "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CAPTURE_TEST_CHANGED_VAR=after"* ]]
}

@test "capture: omits unchanged variables" {
  export CAPTURE_TEST_SAME_VAR="same"
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
export CAPTURE_TEST_SAME_VAR="same"
EOF
  run capture_lines "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"CAPTURE_TEST_SAME_VAR"* ]]
}

@test "capture: skips denylisted variables even when changed" {
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
export GITHUB_TOKEN_CHANGED="new-value"
export CI="true"
export RUNNER_TRACKING_ID="x"
export ACTIONS_CACHE_URL="http://example.invalid"
export BASH_ENV="/tmp/malicious-env"
export ENV="/tmp/malicious-env"
EOF
  run capture_lines "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"GITHUB_TOKEN_CHANGED"* ]]
  [[ "$output" != *"ACTIONS_CACHE_URL"* ]]
  [[ "$output" != *"BASH_ENV"* ]]
  [[ "$output" != "ENV="* ]]
  [[ "$output" != *$'\nENV='* ]]
  # CI=false is preset by bats; changing it must still be filtered.
  [[ "$output" != *$'\nCI='* ]]
}

@test "capture: skips invalid variable names" {
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
export "NOT-VALID-NAME"="oops"
export CAPTURE_TEST_VALID="yes"
EOF
  run capture_lines "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CAPTURE_TEST_VALID=yes"* ]]
  [[ "$output" != *"NOT-VALID-NAME"* ]]
}

@test "capture: includes PATH changes for downstream filtering" {
  mkdir -p "$TEST_TMPDIR/fakebin"
  cat > "$TEST_TMPDIR/setup.sh" <<EOF
export PATH="$TEST_TMPDIR/fakebin:\$PATH"
EOF
  run capture_lines "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PATH="*"$TEST_TMPDIR/fakebin"* ]]
}

@test "capture: tolerates shellHook with unset vars and non-zero exit" {
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
echo "hook stdout" >&2
echo "about to reference unset var: ${THIS_IS_UNSET_12345:-fallback}" >&2
export CAPTURE_TEST_HOOK_OK="hooked"
# A failing command at the end must not abort the capture.
false
EOF
  run capture_lines "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CAPTURE_TEST_HOOK_OK=hooked"* ]]
}

@test "capture: fails when shellHook exits early with status 0" {
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
export CAPTURE_TEST_BEFORE_EXIT="partial"
exit 0
EOF
  run env -u BASH_ENV -u ENV bash --noprofile --norc "$CAPTURE" "$TEST_TMPDIR/setup.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exited before completing"* ]]
  [[ "$output" != *"CAPTURE_TEST_BEFORE_EXIT"* ]]
}

@test "capture: fails when shellHook exits early with non-zero status" {
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
exit 3
EOF
  run env -u BASH_ENV -u ENV bash --noprofile --norc "$CAPTURE" "$TEST_TMPDIR/setup.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exited before completing"* ]]
}

@test "capture: shellHook EXIT trap does not break capture or cleanup" {
  mkdir -p "$TEST_TMPDIR/tmp"
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
trap 'echo "hook trap" >&2' EXIT
export CAPTURE_TEST_WITH_TRAP="trapped"
EOF
  run env TMPDIR="$TEST_TMPDIR/tmp" bash -c '
    env -u BASH_ENV -u ENV bash --noprofile --norc "$1" "$2" 2>/dev/null | tr "\0" "\n"
  ' _ "$CAPTURE" "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CAPTURE_TEST_WITH_TRAP=trapped"* ]]
  # The capture script's own workdir must still be cleaned up.
  [ -z "$(ls -A "$TEST_TMPDIR/tmp")" ]
}

@test "capture: supports multiline values" {
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
export CAPTURE_TEST_MULTILINE=$'line1\nline2'
EOF
  result="$(env -u BASH_ENV -u ENV bash --noprofile --norc "$CAPTURE" "$TEST_TMPDIR/setup.sh" 2>/dev/null | tr '\0' '\n')"
  [[ "$result" == *"CAPTURE_TEST_MULTILINE=line1"* ]]
  [[ "$result" == *"line2"* ]]
}

@test "capture: survives shellHook unsetting PATH" {
  cat > "$TEST_TMPDIR/setup.sh" <<'EOF'
export CAPTURE_TEST_AFTER_UNSET="still-captured"
unset PATH
EOF
  run capture_lines "$TEST_TMPDIR/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CAPTURE_TEST_AFTER_UNSET=still-captured"* ]]
}
