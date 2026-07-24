#!/usr/bin/env bats
# Pruebas de snapshots defensivos creados por scripts/backup.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_HOME="$(mktemp -d)"
  TEST_STATE_DIR="$(mktemp -d)"
}

teardown() {
  chmod -R u+rwx "$TEST_HOME" 2>/dev/null || true
  rm -rf "$TEST_HOME" "$TEST_STATE_DIR"
}

@test "backup.sh completa un snapshot vacío y reserva stdout para su ruta" {
  local stdout_file="$TEST_HOME/stdout"
  local stderr_file="$TEST_HOME/stderr"
  local snapshot="$TEST_STATE_DIR/backups/pre-chezmoi"

  HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/backup.sh" --name=pre-chezmoi \
    >"$stdout_file" 2>"$stderr_file"

  [ "$(<"$stdout_file")" = "$snapshot" ]
  [ -d "$snapshot/.complete" ]
}

@test "backup.sh rejects an incomplete fixed-name snapshot without printing a path" {
  local snapshot="$TEST_STATE_DIR/backups/pre-chezmoi"

  mkdir -p "$snapshot"
  printf 'partial\n' >"$snapshot/.zshrc"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/backup.sh" --name=pre-chezmoi

  [ "$status" -ne 0 ]
  [[ "$output" == *"snapshot fijo existente está incompleto"* ]]
  [ "$(<"$snapshot/.zshrc")" = "partial" ]
  [ ! -e "$snapshot/.complete" ]
}

@test "backup.sh fails when a source cannot be copied" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "permission failure cannot be reproduced as root"
  fi

  mkdir -p "$TEST_HOME/.config/fish"
  chmod 000 "$TEST_HOME/.config/fish"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/backup.sh" --name=pre-chezmoi

  chmod 700 "$TEST_HOME/.config/fish"

  [ "$status" -ne 0 ]
  [ ! -e "$TEST_STATE_DIR/backups/pre-chezmoi/.complete" ]
}
