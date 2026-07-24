#!/usr/bin/env bats
# Smoke tests para bootstrap/checkov.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "checkov.sh existe" {
  [ -f "$REPO_ROOT/bootstrap/checkov.sh" ]
}

@test "checkov.sh es ejecutable" {
  [ -x "$REPO_ROOT/bootstrap/checkov.sh" ]
}

@test "checkov.sh pasa bash -n sin errores de sintaxis" {
  bash -n "$REPO_ROOT/bootstrap/checkov.sh"
}
