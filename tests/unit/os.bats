#!/usr/bin/env bats
# Smoke tests para bootstrap/lib/os.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # shellcheck source=bootstrap/lib/os.sh
  . "$REPO_ROOT/bootstrap/lib/os.sh"
}

@test "validate_supported_platform rechaza ID no ubuntu" {
  OS_RELEASE_FILE="$(mktemp)"
  printf 'ID=debian\nVERSION_ID=12\n' > "$OS_RELEASE_FILE"
  ! validate_supported_platform
  rm -f "$OS_RELEASE_FILE"
}

@test "validate_supported_platform rechaza VERSION_ID ubuntu no listada" {
  OS_RELEASE_FILE="$(mktemp)"
  printf 'ID=ubuntu\nVERSION_ID=99.99\n' > "$OS_RELEASE_FILE"
  ! validate_supported_platform
  rm -f "$OS_RELEASE_FILE"
}

@test "validate_supported_platform acepta ubuntu 24.04" {
  OS_RELEASE_FILE="$(mktemp)"
  printf 'ID=ubuntu\nVERSION_ID=24.04\n' > "$OS_RELEASE_FILE"
  validate_supported_platform
  rm -f "$OS_RELEASE_FILE"
}

@test "_supported_ubuntu_versions lista 24.04 y 26.04" {
  result="$(_supported_ubuntu_versions | tr '\n' ' ')"
  [[ "$result" == *"24.04"* ]]
  [[ "$result" == *"26.04"* ]]
}