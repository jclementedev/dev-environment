#!/usr/bin/env bats
# Smoke tests para bootstrap/lib/log.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # shellcheck source=bootstrap/lib/log.sh
  . "$REPO_ROOT/bootstrap/lib/log.sh"
}

@test "log_info imprime [INFO] a stderr" {
  result=$(log_info "mensaje" 2>&1 >/dev/null)
  [ "$result" = "[INFO] mensaje" ]
}

@test "log_warn imprime [WARN] a stderr" {
  result=$(log_warn "atencion" 2>&1 >/dev/null)
  [ "$result" = "[WARN] atencion" ]
}

@test "log_error imprime [ERROR] a stderr" {
  result=$(log_error "fallo" 2>&1 >/dev/null)
  [ "$result" = "[ERROR] fallo" ]
}

@test "log_fatal imprime [FATAL] a stderr" {
  result=$(log_fatal "critico" 2>&1 >/dev/null)
  [ "$result" = "[FATAL] critico" ]
}

@test "die imprime [FATAL] y sale con código 1" {
  run die "fatal"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FATAL] fatal"* ]]
}
