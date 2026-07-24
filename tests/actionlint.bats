#!/usr/bin/env bats
# Smoke tests para bootstrap/actionlint.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "actionlint.sh existe" {
  [ -f "$REPO_ROOT/bootstrap/actionlint.sh" ]
}

@test "actionlint.sh es ejecutable" {
  [ -x "$REPO_ROOT/bootstrap/actionlint.sh" ]
}

@test "actionlint.sh pasa bash -n sin errores de sintaxis" {
  bash -n "$REPO_ROOT/bootstrap/actionlint.sh"
}