#!/usr/bin/env bats
# Pruebas del API público de bootstrap/lib/ssh.sh.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

@test "gh_fetch_github_host_keys rechaza un escaneo vacío" {
  # shellcheck source=bootstrap/lib/ssh.sh
  . "$REPO_ROOT/bootstrap/lib/ssh.sh"
  ssh-keyscan() {
    return 0
  }

  ! gh_fetch_github_host_keys
}

@test "gh_fetch_github_host_keys rechaza una clave de tipo no admitido" {
  # shellcheck source=bootstrap/lib/ssh.sh
  . "$REPO_ROOT/bootstrap/lib/ssh.sh"
  ssh-keyscan() {
    printf '%s\n' 'github.com ssh-dss AAAAkey'
  }

  ! gh_fetch_github_host_keys
}

@test "trust_github_host rechaza un directorio SSH enlazado" {
  # shellcheck source=bootstrap/lib/ssh.sh
  . "$REPO_ROOT/bootstrap/lib/ssh.sh"
  local home_dir="$BATS_TEST_TMPDIR/home"

  mkdir -p "$home_dir"
  ln -s "$BATS_TEST_TMPDIR/other" "$home_dir/.ssh"
  HOME="$home_dir"

  ! trust_github_host
}

@test "trust_github_host actualiza known_hosts, preserva hosts ajenos y fija permisos" {
  # shellcheck source=bootstrap/lib/ssh.sh
  . "$REPO_ROOT/bootstrap/lib/ssh.sh"
  local home_dir="$BATS_TEST_TMPDIR/home"
  local known_hosts="$home_dir/.ssh/known_hosts"

  mkdir -p "$home_dir/.ssh"
  printf '%s\n' 'gitlab.com ssh-ed25519 foreign-key' > "$known_hosts"
  chmod 0644 "$known_hosts"
  HOME="$home_dir"
  gh_fetch_github_host_keys() {
    printf '%s\n' 'github.com ssh-ed25519 verified-key'
  }
  ssh-keygen() {
    return 0
  }

  trust_github_host

  grep -qx 'gitlab.com ssh-ed25519 foreign-key' "$known_hosts"
  grep -qx 'github.com ssh-ed25519 verified-key' "$known_hosts"
  [ "$(stat -c '%a' "$known_hosts")" = 600 ]
}

@test "trust_github_host elimina los respaldos temporales de ssh-keygen" {
  # shellcheck source=bootstrap/lib/ssh.sh
  . "$REPO_ROOT/bootstrap/lib/ssh.sh"
  local home_dir="$BATS_TEST_TMPDIR/home"

  mkdir -p "$home_dir/.ssh"
  printf '%s\n' 'github.com ssh-ed25519 existing-key' > "$home_dir/.ssh/known_hosts"
  HOME="$home_dir"
  gh_fetch_github_host_keys() {
    printf '%s\n' 'github.com ssh-ed25519 verified-key'
  }
  ssh-keygen() {
    local known_hosts_file

    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-f" ]; then
        known_hosts_file="$2"
        break
      fi
      shift
    done
    cp "$known_hosts_file" "${known_hosts_file}.old"
  }

  trust_github_host
  run bash -c 'compgen -G "$1" > /dev/null' _ "$home_dir/.ssh/known_hosts.existing.*.old"
  [ "$status" -ne 0 ]
}

@test "trust_github_host elimina respaldos temporales cuando falla el reemplazo" {
  # shellcheck source=bootstrap/lib/ssh.sh
  . "$REPO_ROOT/bootstrap/lib/ssh.sh"
  local home_dir="$BATS_TEST_TMPDIR/home"

  mkdir -p "$home_dir/.ssh"
  printf '%s\n' 'github.com ssh-ed25519 existing-key' > "$home_dir/.ssh/known_hosts"
  HOME="$home_dir"
  gh_fetch_github_host_keys() {
    printf '%s\n' 'github.com ssh-ed25519 verified-key'
  }
  ssh-keygen() {
    local known_hosts_file

    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-f" ]; then
        known_hosts_file="$2"
        break
      fi
      shift
    done
    cp "$known_hosts_file" "${known_hosts_file}.old"
  }
  mv() {
    return 1
  }

  run trust_github_host
  [ "$status" -ne 0 ]
  run bash -c 'compgen -G "$1" > /dev/null' _ "$home_dir/.ssh/known_hosts.existing.*.old"
  [ "$status" -ne 0 ]
}
