#!/usr/bin/env bats
# Smoke tests para bootstrap/lib/pkg-manager.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # shellcheck source=bootstrap/lib/pkg-manager.sh
  . "$REPO_ROOT/bootstrap/lib/pkg-manager.sh"
}

@test "pkg_install delega los paquetes a apt-get mediante sudo" {
  local bin_dir="$BATS_TEST_TMPDIR/bin"
  local apt_log="$BATS_TEST_TMPDIR/apt.log"

  mkdir -p "$bin_dir"
  printf '%s\n' '#!/bin/sh' 'exec "$@"' > "$bin_dir/sudo"
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$*" > "$APT_LOG"' > "$bin_dir/apt-get"
  chmod +x "$bin_dir/sudo" "$bin_dir/apt-get"

  export APT_LOG="$apt_log"
  export PATH="$bin_dir:$PATH"

  pkg_install curl git

  [ "$(< "$apt_log")" = "install -y curl git" ]
}

@test "pkg_update delega la actualización a apt-get mediante sudo" {
  local bin_dir="$BATS_TEST_TMPDIR/bin"
  local apt_log="$BATS_TEST_TMPDIR/apt.log"

  mkdir -p "$bin_dir"
  printf '%s\n' '#!/bin/sh' 'exec "$@"' > "$bin_dir/sudo"
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$*" > "$APT_LOG"' > "$bin_dir/apt-get"
  chmod +x "$bin_dir/sudo" "$bin_dir/apt-get"

  export APT_LOG="$apt_log"
  export PATH="$bin_dir:$PATH"

  pkg_update

  [ "$(< "$apt_log")" = "update" ]
}
