#!/usr/bin/env bats
# Smoke test para bootstrap.sh: verifica que el entry point existe, es ejecutable,
# y que las librerías requeridas pueden cargarse.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  OS_RELEASE_FILE="$(mktemp)"
  TEST_BIN="$(mktemp -d)"
}

teardown() {
  rm -rf "$OS_RELEASE_FILE" "$TEST_BIN"
}

@test "bootstrap.sh existe y es ejecutable" {
  [ -x "$REPO_ROOT/bootstrap.sh" ]
}

@test "bootstrap.sh pasa bash -n sin errores de sintaxis" {
  bash -n "$REPO_ROOT/bootstrap.sh"
}

@test "prepare_repository emite solo la ruta cuando git pull escribe en stdout" {
  local repository="$BATS_TEST_TMPDIR/repository"
  local stderr_file="$BATS_TEST_TMPDIR/prepare-repository.stderr"

  mkdir -p "$repository/.git"
  cat >"$TEST_BIN/git" <<'EOF'
#!/bin/sh
case "$*" in
  "rev-parse --show-toplevel") printf '%s\n' "$TEST_REPOSITORY" ;;
  "-C $TEST_REPOSITORY remote get-url origin") printf '%s\n' 'https://github.com/jclementedev/dev-environment.git' ;;
  "-C $TEST_REPOSITORY branch --show-current") printf '%s\n' 'main' ;;
  "-C $TEST_REPOSITORY status --porcelain") ;;
  "-C $TEST_REPOSITORY pull --ff-only") printf '%s\n' 'Already up to date.' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$TEST_BIN/git"

  run env \
    PATH="$TEST_BIN:$PATH" \
    TEST_REPOSITORY="$repository" \
    STDERR_FILE="$stderr_file" \
    bash -c 'source "$1"; prepare_repository 2>"$STDERR_FILE"' \
    bash "$REPO_ROOT/bootstrap.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "$repository" ]
  grep -Fqx 'Already up to date.' "$stderr_file"
}

@test "bootstrap.sh rechaza una distribución no Ubuntu antes de usar Git" {
  printf 'ID=debian\nVERSION_ID=12\n' > "$OS_RELEASE_FILE"

  run env OS_RELEASE_FILE="$OS_RELEASE_FILE" bash "$REPO_ROOT/bootstrap.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"se requiere Ubuntu"* ]]
}

@test "bootstrap.sh ejecutado desde stdin no falla con set -u" {
  printf 'ID=debian\nVERSION_ID=12\n' > "$OS_RELEASE_FILE"

  run bash -c 'env OS_RELEASE_FILE="$1" bash < "$2"' \
    bash "$OS_RELEASE_FILE" "$REPO_ROOT/bootstrap.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"se requiere Ubuntu"* ]]
  [[ "$output" != *"BASH_SOURCE[0]: unbound variable"* ]]
}

@test "bootstrap.sh rechaza una versión Ubuntu no soportada antes de usar Git" {
  local bin_dir="$BATS_TEST_TMPDIR/bin"
  local git_log="$BATS_TEST_TMPDIR/git.log"

  mkdir -p "$bin_dir"
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$*" >> "$GIT_LOG"' > "$bin_dir/git"
  chmod +x "$bin_dir/git"
  printf 'ID=ubuntu\nVERSION_ID=99.99\n' > "$OS_RELEASE_FILE"

  run env \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    GIT_LOG="$git_log" \
    PATH="$bin_dir:$PATH" \
    bash "$REPO_ROOT/bootstrap.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Ubuntu 99.99 no está entre las versiones soportadas"* ]]
  [ ! -e "$git_log" ]
}
