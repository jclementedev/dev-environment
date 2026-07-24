#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BIN_DIR="$BATS_TEST_TMPDIR/bin"
  COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"

  mkdir -p "$BIN_DIR"

  printf '%s\n' '#!/bin/sh' 'if [ "$1" = "compose" ] || [ "$1" = "buildx" ] || [ "$1" = "--version" ]; then exit 0; fi' > "$BIN_DIR/docker"
  printf '%s\n' '#!/bin/sh' 'if [ "$1" = "group" ] && [ "$2" = "docker" ]; then exit 0; fi; exit 1' > "$BIN_DIR/getent"
  printf '%s\n' '#!/bin/sh' 'if [ "$1" = "-un" ]; then printf "%s\\n" testuser; else printf "%s\\n" testuser; fi' > "$BIN_DIR/id"
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "${PID1:-systemd}"' > "$BIN_DIR/ps"
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$*" >> "$COMMAND_LOG"; exec "$@"' > "$BIN_DIR/sudo"
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "usermod $*" >> "$COMMAND_LOG"' > "$BIN_DIR/usermod"
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "systemctl $*" >> "$COMMAND_LOG"' > "$BIN_DIR/systemctl"
  chmod +x "$BIN_DIR"/*
}

@test "docker.sh reconcilia grupo y servicio cuando Docker ya está instalado" {
  run env PATH="$BIN_DIR:$PATH" COMMAND_LOG="$COMMAND_LOG" bash "$REPO_ROOT/bootstrap/docker.sh"

  [ "$status" -eq 0 ]
  grep -Fqx 'usermod -aG docker testuser' "$COMMAND_LOG"
  grep -Fqx 'systemctl enable --now docker' "$COMMAND_LOG"
}

@test "docker.sh no falla sin systemd cuando Docker ya está instalado" {
  run env \
    PATH="$BIN_DIR:$PATH" \
    COMMAND_LOG="$COMMAND_LOG" \
    PID1=init \
    bash "$REPO_ROOT/bootstrap/docker.sh"

  [ "$status" -eq 0 ]
  grep -Fqx 'usermod -aG docker testuser' "$COMMAND_LOG"
  ! grep -Fq 'systemctl enable --now docker' "$COMMAND_LOG"
}
