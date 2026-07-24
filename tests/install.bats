#!/usr/bin/env bats
# Pruebas de install.sh: configuración, orquestación y comportamiento no fatal.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_BIN="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_BIN"
}

@test "install.sh existe y es ejecutable" {
  [ -x "$REPO_ROOT/install.sh" ]
}

@test "install.sh pasa bash -n sin errores de sintaxis" {
  bash -n "$REPO_ROOT/install.sh"
}

@test "install.sh no inicializa el estado de cuentas GitHub" {
  ! grep -q 'github-accounts.sh\|init_state' "$REPO_ROOT/install.sh"
}

@test "install.sh incluye dev-tools como bootstrap opcional" {
  grep -q 'run_optional_bootstrap dev-tools' "$REPO_ROOT/install.sh"
}

@test "install.sh configura Zsh como shell de inicio después de aplicar Chezmoi" {
  local installation_log="$BATS_TEST_TMPDIR/installation.log"
  local sudo_log="$BATS_TEST_TMPDIR/sudo.log"
  local chsh_log="$BATS_TEST_TMPDIR/chsh.log"
  local chezmoi_applied="$BATS_TEST_TMPDIR/chezmoi-applied"
  local expected_lines=(
    'validate_environment'
    'prepare_sudo'
    'update_package_index'
    'install_components'
    'ensure_chezmoi_config'
    'apply_chezmoi'
    'show_summary'
  )
  local index

  printf '%s\n' '#!/bin/sh' 'exit 0' >"$TEST_BIN/zsh"
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$*" >> "$CHSH_LOG"' >"$TEST_BIN/chsh"
  printf '%s\n' '#!/bin/sh' '[ -f "$CHEZMOI_APPLIED" ] || exit 1' 'printf "%s\\n" "$*" >> "$SUDO_LOG"' 'exec "$@"' >"$TEST_BIN/sudo"
  chmod +x "$TEST_BIN/zsh" "$TEST_BIN/chsh" "$TEST_BIN/sudo"

  run env \
    PATH="$TEST_BIN:$PATH" \
    USER=installer \
    INSTALLATION_LOG="$installation_log" \
    SUDO_LOG="$sudo_log" \
    CHSH_LOG="$chsh_log" \
    CHEZMOI_APPLIED="$chezmoi_applied" \
    bash -c '
      source "$1"
      validate_environment() { printf "validate_environment\\n" >> "$INSTALLATION_LOG"; }
      prepare_sudo() { printf "prepare_sudo\\n" >> "$INSTALLATION_LOG"; }
      update_package_index() { printf "update_package_index\\n" >> "$INSTALLATION_LOG"; }
      install_components() { printf "install_components\\n" >> "$INSTALLATION_LOG"; }
      ensure_chezmoi_config() { printf "ensure_chezmoi_config\\n" >> "$INSTALLATION_LOG"; }
      apply_chezmoi() { printf "apply_chezmoi\\n" >> "$INSTALLATION_LOG"; touch "$CHEZMOI_APPLIED"; }
      show_summary() { printf "show_summary\\n" >> "$INSTALLATION_LOG"; }
      main
    ' bash "$REPO_ROOT/install.sh"

  [ "$status" -eq 0 ]
  mapfile -t installation_lines <"$installation_log"
  [ "${#installation_lines[@]}" -eq "${#expected_lines[@]}" ]

  for index in "${!expected_lines[@]}"; do
    [ "${installation_lines[$index]}" = "${expected_lines[$index]}" ]
  done
  [ "$(<"$sudo_log")" = "chsh -s $TEST_BIN/zsh installer" ]
  [ "$(<"$chsh_log")" = "-s $TEST_BIN/zsh installer" ]
}

@test "install.sh continúa si no puede configurar Zsh como shell de inicio" {
  local installation_log="$BATS_TEST_TMPDIR/installation.log"
  local sudo_log="$BATS_TEST_TMPDIR/sudo.log"
  local chsh_log="$BATS_TEST_TMPDIR/chsh.log"
  local chezmoi_applied="$BATS_TEST_TMPDIR/chezmoi-applied"

  printf '%s\n' '#!/bin/sh' 'exit 0' >"$TEST_BIN/zsh"
  printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s\\n" "$*" >> "$CHSH_LOG"' \
    'exit 1' >"$TEST_BIN/chsh"
  printf '%s\n' \
    '#!/bin/sh' \
    '[ -f "$CHEZMOI_APPLIED" ] || exit 1' \
    'printf "%s\\n" "$*" >> "$SUDO_LOG"' \
    'exec "$@"' >"$TEST_BIN/sudo"
  chmod +x "$TEST_BIN/zsh" "$TEST_BIN/chsh" "$TEST_BIN/sudo"

  run env \
    PATH="$TEST_BIN:$PATH" \
    USER=installer \
    INSTALLATION_LOG="$installation_log" \
    SUDO_LOG="$sudo_log" \
    CHSH_LOG="$chsh_log" \
    CHEZMOI_APPLIED="$chezmoi_applied" \
    bash -c '
      source "$1"
      validate_environment() { :; }
      prepare_sudo() { :; }
      update_package_index() { :; }
      install_components() { :; }
      ensure_chezmoi_config() { :; }
      apply_chezmoi() { printf "apply_chezmoi\\n" >> "$INSTALLATION_LOG"; touch "$CHEZMOI_APPLIED"; }
      show_summary() { printf "show_summary\\n" >> "$INSTALLATION_LOG"; }
      main
    ' bash "$REPO_ROOT/install.sh"

  [ "$status" -eq 0 ]
  [ "$(<"$installation_log")" = $'apply_chezmoi\nshow_summary' ]
  [ "$(<"$sudo_log")" = "chsh -s $TEST_BIN/zsh installer" ]
  [ "$(<"$chsh_log")" = "-s $TEST_BIN/zsh installer" ]
  [[ "$output" == *'No se pudo configurar Zsh como shell de inicio. Ejecute: chsh -s "$(command -v zsh)"'* ]]
}

@test "install.sh no intenta chsh si falla la configuración de Chezmoi" {
  local sudo_log="$BATS_TEST_TMPDIR/sudo.log"

  printf '%s\n' '#!/bin/sh' 'printf "attempted\\n" >> "$SUDO_LOG"' >"$TEST_BIN/sudo"
  chmod +x "$TEST_BIN/sudo"

  run env SUDO_LOG="$sudo_log" PATH="$TEST_BIN:$PATH" bash -c '
    source "$1"
    validate_environment() { :; }
    prepare_sudo() { :; }
    update_package_index() { :; }
    install_components() { :; }
    ensure_chezmoi_config() { return 1; }
    main
  ' bash "$REPO_ROOT/install.sh"

  [ "$status" -ne 0 ]
  [ ! -e "$sudo_log" ]
}

@test "install.sh no intenta chsh si falla la aplicación de Chezmoi" {
  local sudo_log="$BATS_TEST_TMPDIR/sudo.log"

  printf '%s\n' '#!/bin/sh' 'printf "attempted\\n" >> "$SUDO_LOG"' >"$TEST_BIN/sudo"
  chmod +x "$TEST_BIN/sudo"

  run env SUDO_LOG="$sudo_log" PATH="$TEST_BIN:$PATH" bash -c '
    source "$1"
    validate_environment() { :; }
    prepare_sudo() { :; }
    update_package_index() { :; }
    install_components() { :; }
    ensure_chezmoi_config() { :; }
    apply_chezmoi() { return 1; }
    main
  ' bash "$REPO_ROOT/install.sh"

  [ "$status" -ne 0 ]
  [ ! -e "$sudo_log" ]
}

@test "install.sh completa solo los datos de Chezmoi que faltan" {
  local home_directory="$BATS_TEST_TMPDIR/home"
  local config_directory="$home_directory/.config/chezmoi"
  local config_file="$config_directory/chezmoi.toml"

  mkdir -p "$config_directory"
  printf '%s\n' \
    '[chezmoi]' \
    '    sourceDir = "/custom/source"' \
    '' \
    '[data]' \
    '    git_user_name = "Existing Name"' \
    '    custom_value = "preserve"' \
    '' \
    '[other]' \
    '    enabled = true' >"$config_file"

  run env \
    HOME="$home_directory" \
    BOOTSTRAP_GIT_USER_EMAIL="existing@example.test" \
    bash -c 'source "$1"; ensure_chezmoi_config' bash "$REPO_ROOT/install.sh"

  [ "$status" -eq 0 ]
  grep -Fqx '    sourceDir = "/custom/source"' "$config_file"
  grep -Fqx '    git_user_name = "Existing Name"' "$config_file"
  grep -Fqx '    custom_value = "preserve"' "$config_file"
  grep -Fqx 'git_user_email = "existing@example.test"' "$config_file"
  grep -Fqx "primary_ssh_key = \"$home_directory/.ssh/id_ed25519\"" "$config_file"
  grep -Fqx '[other]' "$config_file"
  grep -Fqx '    enabled = true' "$config_file"
}

@test "install.sh rechaza un symlink de chezmoi.toml sin reemplazarlo" {
  local home_directory="$BATS_TEST_TMPDIR/home"
  local config_directory="$home_directory/.config/chezmoi"
  local config_file="$config_directory/chezmoi.toml"
  local target_file="$BATS_TEST_TMPDIR/external-chezmoi.toml"

  mkdir -p "$config_directory"
  printf '%s\n' '[data]' 'git_user_name = "Existing Name"' >"$target_file"
  ln -s "$target_file" "$config_file"

  run env \
    HOME="$home_directory" \
    BOOTSTRAP_GIT_USER_EMAIL="existing@example.test" \
    bash -c 'source "$1"; ensure_chezmoi_config' bash "$REPO_ROOT/install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"es un symlink; se rechaza reemplazarlo"* ]]
  [ -L "$config_file" ]
  [ "$(readlink "$config_file")" = "$target_file" ]
  [ "$(<"$target_file")" = $'[data]\ngit_user_name = "Existing Name"' ]
}

@test "install.sh rejects an incomplete pre-chezmoi backup before applying Chezmoi" {
  local home_directory="$BATS_TEST_TMPDIR/home"
  local state_directory="$BATS_TEST_TMPDIR/state"
  local snapshot="$state_directory/backups/pre-chezmoi"

  mkdir -p "$snapshot"
  printf 'partial\n' >"$snapshot/.zshrc"

  run env HOME="$home_directory" DEV_ENV_STATE_DIR="$state_directory" \
    bash -c 'source "$1"; create_pre_chezmoi_backup' \
    bash "$REPO_ROOT/install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"backup pre-chezmoi existente está incompleto"* ]]
  [ "$(<"$snapshot/.zshrc")" = "partial" ]
  [ ! -e "$snapshot/.complete" ]
}
