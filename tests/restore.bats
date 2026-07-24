#!/usr/bin/env bats
# Pruebas de restauración desde snapshots creados por backup.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_HOME="$(mktemp -d)"
  TEST_STATE_DIR="$(mktemp -d)"
  TEST_OUTSIDE="$(mktemp -d)"
}

teardown() {
  chmod -R u+rwx "$TEST_HOME" 2>/dev/null || true
  rm -rf "$TEST_HOME" "$TEST_STATE_DIR" "$TEST_OUTSIDE"
}

@test "restore.sh rejects an incomplete snapshot" {
  local snapshot="$TEST_STATE_DIR/backups/incomplete"

  mkdir -p "$snapshot"
  touch "$snapshot/.zshrc"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/restore.sh" incomplete

  [ "$status" -ne 0 ]
  [[ "$output" == *"no fue completado por backup.sh"* ]]
  [ "$(find "$TEST_STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
}

@test "restore.sh restaura un archivo regular y conserva un backup defensivo" {
  local snapshot="$TEST_STATE_DIR/backups/valid"
  local defensive_snapshot

  mkdir -p "$snapshot/.complete"
  printf 'snapshot\n' >"$snapshot/.zshrc"
  printf 'original\n' >"$TEST_HOME/.zshrc"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/restore.sh" valid

  [ "$status" -eq 0 ]
  [ "$(<"$TEST_HOME/.zshrc")" = "snapshot" ]
  defensive_snapshot="$(find "$TEST_STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d ! -name valid -print -quit)"
  [ -n "$defensive_snapshot" ]
  [ -d "$defensive_snapshot/.complete" ]
  [ "$(<"$defensive_snapshot/.zshrc")" = "original" ]
}

@test "restore.sh rejects a symlinked completion marker before creating a defensive snapshot" {
  local snapshot="$TEST_STATE_DIR/backups/symlinked-marker"

  mkdir -p "$snapshot" "$TEST_OUTSIDE/complete-marker"
  ln -s "$TEST_OUTSIDE/complete-marker" "$snapshot/.complete"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/restore.sh" symlinked-marker

  [ "$status" -ne 0 ]
  [[ "$output" == *"no fue completado por backup.sh"* ]]
  [ "$(find "$TEST_STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
}

@test "restore.sh rejects an ancestor symlink that escapes HOME before writing outside" {
  local snapshot="$TEST_STATE_DIR/backups/escaping-ancestor"

  mkdir -p "$snapshot/.config"
  mkdir "$snapshot/.complete"
  printf 'unsafe\n' >"$snapshot/.config/restore-target"
  ln -s "$TEST_OUTSIDE" "$TEST_HOME/.config"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/restore.sh" escaping-ancestor

  [ "$status" -ne 0 ]
  [[ "$output" == *"escaparía de HOME"* ]]
  [ ! -e "$TEST_OUTSIDE/restore-target" ]
}

@test "restore.sh rejects a destination symlink that escapes HOME before writing outside" {
  local snapshot="$TEST_STATE_DIR/backups/escaping-destination"

  mkdir -p "$snapshot"
  mkdir "$snapshot/.complete"
  printf 'unsafe\n' >"$snapshot/.zshrc"
  ln -s "$TEST_OUTSIDE/restore-target" "$TEST_HOME/.zshrc"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/restore.sh" escaping-destination

  [ "$status" -ne 0 ]
  [[ "$output" == *"escaparía de HOME"* ]]
  [ ! -e "$TEST_OUTSIDE/restore-target" ]
}

@test "restore.sh rejects a source symlink that escapes the snapshot" {
  local snapshot="$TEST_STATE_DIR/backups/escaping-source-link"

  mkdir -p "$snapshot/.config/nested" "$TEST_OUTSIDE"
  mkdir "$snapshot/.complete"
  printf 'outside\n' >"$TEST_OUTSIDE/restore-target"
  ln -s "$TEST_OUTSIDE/restore-target" "$snapshot/.config/nested/restore-target"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/restore.sh" escaping-source-link

  [ "$status" -ne 0 ]
  [[ "$output" == *"referencia fuera del snapshot"* ]]
  [ ! -e "$TEST_HOME/.config" ]
}

@test "restore.sh preserves a source symlink that resolves inside the snapshot" {
  local snapshot="$TEST_STATE_DIR/backups/internal-source-link"

  mkdir -p "$snapshot/.config" "$snapshot/.complete"
  printf 'inside\n' >"$snapshot/.config/restore-target"
  ln -s .config/restore-target "$snapshot/.zshrc"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash "$REPO_ROOT/scripts/restore.sh" internal-source-link

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.zshrc" ]
  [ "$(readlink "$TEST_HOME/.zshrc")" = ".config/restore-target" ]
  [ "$(<"$TEST_HOME/.zshrc")" = "inside" ]
}
