#!/usr/bin/env bats
# Smoke tests para bootstrap/semgrep.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "semgrep.sh existe" {
  [ -f "$REPO_ROOT/bootstrap/semgrep.sh" ]
}

@test "semgrep.sh es ejecutable" {
  [ -x "$REPO_ROOT/bootstrap/semgrep.sh" ]
}

@test "semgrep.sh pasa bash -n sin errores de sintaxis" {
  bash -n "$REPO_ROOT/bootstrap/semgrep.sh"
}
