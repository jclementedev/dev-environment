#!/bin/bash
#
# install.sh — instala el entorno y aplica los dotfiles.
#
# Responsabilidades:
#   1. valida la plataforma;
#   2. instala los componentes del entorno;
#   3. crea la configuración inicial de Chezmoi;
#   4. crea un backup previo a Chezmoi;
#   5. aplica los dotfiles.
#
# No configura autenticación externa. La cuenta primaria y las cuentas
# secundarias de GitHub se administran posteriormente con scripts/account.sh.
#

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CHEZMOI_SOURCE_DIR="$SCRIPT_DIR/dotfiles"
readonly CHEZMOI_CONFIG_DIR="$HOME/.config/chezmoi"
readonly CHEZMOI_CONFIG_FILE="$CHEZMOI_CONFIG_DIR/chezmoi.toml"

readonly INSTALL_STATE_DIR="${DEV_ENV_STATE_DIR:-$HOME/.local/state/dev-env-bootstrap}"

readonly PRE_CHEZMOI_BACKUP="$INSTALL_STATE_DIR/backups/pre-chezmoi"

# shellcheck source=bootstrap/lib/log.sh
. "$SCRIPT_DIR/bootstrap/lib/log.sh"

# shellcheck source=bootstrap/lib/os.sh
. "$SCRIPT_DIR/bootstrap/lib/os.sh"

# shellcheck source=bootstrap/lib/pkg-manager.sh
. "$SCRIPT_DIR/bootstrap/lib/pkg-manager.sh"

FAILED_COMPONENTS=()

case ":$PATH:" in
  *":$HOME/.local/bin:"*)
    ;;

  *)
    export PATH="$HOME/.local/bin:$PATH"
    ;;
esac

require_command()
{
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 \
    || die "install.sh: $command_name es requerido"
}

validate_environment()
{
  log_info "install.sh: validando entorno"

  require_command bash
  require_command git
  require_command sudo

  validate_supported_platform \
    || die "install.sh: plataforma no soportada; abortando antes de cualquier mutación"
}

prepare_sudo()
{
  log_info "install.sh: validando acceso sudo"

  if [ -r /dev/tty ]; then
    sudo -v </dev/tty \
      || die "install.sh: no se pudo obtener acceso sudo"

    return 0
  fi

  sudo -n true >/dev/null 2>&1 \
    || die "install.sh: sudo requiere una terminal interactiva"
}

update_package_index()
{
  log_info "install.sh: actualizando índice de paquetes"

  pkg_update \
    || die "install.sh: no se pudo actualizar el índice de paquetes"
}

bootstrap_script_path()
{
  local component="$1"

  printf '%s/bootstrap/%s.sh\n' "$SCRIPT_DIR" "$component"
}

run_required_bootstrap()
{
  local component="$1"
  local script

  script="$(bootstrap_script_path "$component")"

  if [ ! -f "$script" ]; then
    die "$component: no se encontró $script"
  fi

  log_info "install.sh: instalando $component"

  bash "$script" \
    || die "$component: instalación fallida"
}

run_optional_bootstrap()
{
  local component="$1"
  local script

  script="$(bootstrap_script_path "$component")"

  if [ ! -f "$script" ]; then
    log_warn "$component: no se encontró $script; omitiendo"
    FAILED_COMPONENTS+=("$component")
    return 0
  fi

  log_info "install.sh: instalando $component"

  if ! bash "$script"; then
    log_warn "$component: instalación fallida; continuando"
    FAILED_COMPONENTS+=("$component")
  fi
}

install_components()
{
  run_required_bootstrap essentials
  run_required_bootstrap shell
  run_required_bootstrap chezmoi

  run_optional_bootstrap ripgrep
  run_optional_bootstrap bat
  run_optional_bootstrap eza
  run_optional_bootstrap zoxide
  run_optional_bootstrap fzf
  run_optional_bootstrap node
  run_optional_bootstrap python
  run_optional_bootstrap dotnet
  run_optional_bootstrap docker
  run_optional_bootstrap aws
  run_optional_bootstrap terraform
  run_optional_bootstrap dev-tools
}

is_valid_email()
{
  local email="$1"

  [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

read_required_value()
{
  local prompt="$1"
  local value=""

  [ -r /dev/tty ] || return 1

  while [ -z "$value" ]; do
    read -r -p "$prompt" value </dev/tty
  done

  printf '%s\n' "$value"
}

read_git_email()
{
  local email=""

  while true; do
    email="$(
      read_required_value "Correo para los commits de Git: "
    )" || return 1

    if is_valid_email "$email"; then
      printf '%s\n' "$email"
      return 0
    fi

    log_warn "install.sh: formato de correo inválido"
  done
}

toml_escape()
{
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"

  printf '%s' "$value"
}

expand_home_path()
{
  local path="$1"

  case "$path" in
    "~")
      printf '%s\n' "$HOME"
      ;;

    "~/"*)
      printf '%s/%s\n' "$HOME" "${path#~/}"
      ;;

    *)
      printf '%s\n' "$path"
      ;;
  esac
}

chezmoi_data_key_exists()
{
  local key="$1"

  awk -v key="$key" '
    /^[[:space:]]*\[[[:space:]]*data[[:space:]]*\][[:space:]]*(#.*)?$/ {
      in_data = 1
      next
    }
    /^[[:space:]]*\[/ {
      in_data = 0
    }
    in_data && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      found = 1
      exit
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$CHEZMOI_CONFIG_FILE"
}

merge_missing_chezmoi_data()
{
  local git_user_name="$1"
  local git_user_email="$2"
  local primary_ssh_key="$3"
  local add_git_user_name="$4"
  local add_git_user_email="$5"
  local add_primary_ssh_key="$6"
  local additions_file
  local temporary_file

  additions_file="$(
    mktemp "$CHEZMOI_CONFIG_DIR/chezmoi.toml.data.XXXXXX"
  )" || die "install.sh: no se pudo crear los datos temporales de Chezmoi"

  temporary_file="$(
    mktemp "$CHEZMOI_CONFIG_DIR/chezmoi.toml.XXXXXX"
  )" || die "install.sh: no se pudo crear el archivo temporal de Chezmoi"

  {
    if [ "$add_git_user_name" = true ]; then
      printf 'git_user_name = "%s"\n' "$(toml_escape "$git_user_name")"
    fi

    if [ "$add_git_user_email" = true ]; then
      printf 'git_user_email = "%s"\n' "$(toml_escape "$git_user_email")"
    fi

    if [ "$add_primary_ssh_key" = true ]; then
      printf 'primary_ssh_key = "%s"\n' "$(toml_escape "$primary_ssh_key")"
    fi
  } >"$additions_file"

  awk -v additions_file="$additions_file" '
    function write_additions(  line) {
      while ((getline line < additions_file) > 0) {
        print line
      }
      close(additions_file)
    }
    /^[[:space:]]*\[[[:space:]]*data[[:space:]]*\][[:space:]]*(#.*)?$/ {
      in_data = 1
      saw_data = 1
      print
      next
    }
    in_data && /^[[:space:]]*\[/ {
      write_additions()
      in_data = 0
      wrote_additions = 1
    }
    { print }
    END {
      if (saw_data && !wrote_additions) {
        write_additions()
      }
      if (!saw_data) {
        print ""
        print "[data]"
        write_additions()
      }
    }
  ' "$CHEZMOI_CONFIG_FILE" >"$temporary_file" \
    || die "install.sh: no se pudo actualizar los datos de Chezmoi"

  chmod --reference="$CHEZMOI_CONFIG_FILE" "$temporary_file"
  mv "$temporary_file" "$CHEZMOI_CONFIG_FILE"
  rm -f "$additions_file"
}

ensure_chezmoi_config()
{
  local git_user_name="${BOOTSTRAP_GIT_USER_NAME:-}"
  local git_user_email="${BOOTSTRAP_GIT_USER_EMAIL:-}"
  local primary_ssh_key="${BOOTSTRAP_SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
  local config_exists=false
  local needs_git_user_name=true
  local needs_git_user_email=true
  local needs_primary_ssh_key=true
  local temporary_file

  if [ -L "$CHEZMOI_CONFIG_FILE" ]; then
    die \
      "install.sh: $CHEZMOI_CONFIG_FILE es un symlink; se rechaza reemplazarlo"
  fi

  if [ -f "$CHEZMOI_CONFIG_FILE" ]; then
    config_exists=true
    log_info \
      "install.sh: configuración de Chezmoi existente en $CHEZMOI_CONFIG_FILE"

    if chezmoi_data_key_exists git_user_name; then
      needs_git_user_name=false
    fi

    if chezmoi_data_key_exists git_user_email; then
      needs_git_user_email=false
    fi

    if chezmoi_data_key_exists primary_ssh_key; then
      needs_primary_ssh_key=false
    fi
  fi

  if [ "$needs_git_user_name" = true ] && [ -z "$git_user_name" ]; then
    git_user_name="$(
      read_required_value "Nombre para los commits de Git: "
    )" || die \
      "install.sh: define BOOTSTRAP_GIT_USER_NAME en modo no interactivo"
  fi

  if [ "$needs_git_user_email" = true ] && [ -z "$git_user_email" ]; then
    git_user_email="$(
      read_git_email
    )" || die \
      "install.sh: define BOOTSTRAP_GIT_USER_EMAIL en modo no interactivo"
  elif [ "$needs_git_user_email" = true ] && ! is_valid_email "$git_user_email"; then
    die "install.sh: BOOTSTRAP_GIT_USER_EMAIL tiene formato inválido"
  fi

  if [ "$needs_primary_ssh_key" = true ]; then
    primary_ssh_key="$(expand_home_path "$primary_ssh_key")"
  fi

  if [ "$config_exists" = true ]; then
    if [ "$needs_git_user_name" = true ] || \
      [ "$needs_git_user_email" = true ] || \
      [ "$needs_primary_ssh_key" = true ]; then
      merge_missing_chezmoi_data \
        "$git_user_name" \
        "$git_user_email" \
        "$primary_ssh_key" \
        "$needs_git_user_name" \
        "$needs_git_user_email" \
        "$needs_primary_ssh_key"

      log_info "install.sh: datos requeridos de Chezmoi completados"
    fi

    return 0
  fi

  mkdir -p "$CHEZMOI_CONFIG_DIR"
  chmod 700 "$CHEZMOI_CONFIG_DIR"

  temporary_file="$(
    mktemp "$CHEZMOI_CONFIG_DIR/chezmoi.toml.XXXXXX"
  )" || die "install.sh: no se pudo crear el archivo temporal de Chezmoi"

  {
    printf '[data]\n'
    printf \
      'git_user_name = "%s"\n' \
      "$(toml_escape "$git_user_name")"

    printf \
      'git_user_email = "%s"\n' \
      "$(toml_escape "$git_user_email")"

    printf \
      'primary_ssh_key = "%s"\n' \
      "$(toml_escape "$primary_ssh_key")"
  } >"$temporary_file"

  chmod 600 "$temporary_file"
  mv "$temporary_file" "$CHEZMOI_CONFIG_FILE"

  log_info \
    "install.sh: configuración creada en $CHEZMOI_CONFIG_FILE"
}

directory_has_content()
{
  local directory="$1"

  [ -d "$directory" ] &&
    [ -n "$(find "$directory" -mindepth 1 -print -quit 2>/dev/null)" ]
}

snapshot_is_complete()
{
  local snapshot="$1"
  local marker="$snapshot/.complete"

  [ -d "$marker" ] && [ ! -L "$marker" ]
}

create_pre_chezmoi_backup()
{
  local backup_script="$SCRIPT_DIR/scripts/backup.sh"
  local snapshot

  if snapshot_is_complete "$PRE_CHEZMOI_BACKUP"; then
    log_info \
      "install.sh: backup pre-chezmoi existente y completado en $PRE_CHEZMOI_BACKUP; omitiendo"

    return 0
  fi

  if directory_has_content "$PRE_CHEZMOI_BACKUP"; then
    die \
      "install.sh: el backup pre-chezmoi existente está incompleto: $PRE_CHEZMOI_BACKUP; conserva sus archivos y elimínalo o complétalo antes de reintentar"
  fi

  if [ ! -f "$backup_script" ]; then
    die "install.sh: no se encontró $backup_script"
  fi

  log_info "install.sh: creando backup previo a Chezmoi"

  # backup.sh reserva stdout exclusivamente para devolver la ruta.
  # Los mensajes de log permanecen en stderr y no deben capturarse.
  snapshot="$(
    bash "$backup_script" --name=pre-chezmoi
  )" || die "install.sh: no se pudo crear el backup pre-chezmoi"

  if [ -z "$snapshot" ]; then
    die "install.sh: backup.sh devolvió una ruta vacía"
  fi

  if [ "$snapshot" != "$PRE_CHEZMOI_BACKUP" ]; then
    die \
      "install.sh: backup.sh devolvió una ruta inesperada: $snapshot"
  fi

  if ! snapshot_is_complete "$snapshot"; then
    die "install.sh: el backup pre-chezmoi no fue completado: $snapshot"
  fi

  if [ ! -r "$snapshot" ]; then
    die "install.sh: el backup pre-chezmoi no es legible: $snapshot"
  fi

  log_info "install.sh: backup defensivo creado en $snapshot"
}

apply_chezmoi()
{
  require_command chezmoi

  if [ ! -d "$CHEZMOI_SOURCE_DIR" ]; then
    die \
      "install.sh: no se encontró la fuente de Chezmoi: $CHEZMOI_SOURCE_DIR"
  fi

  create_pre_chezmoi_backup

  log_info "install.sh: aplicando Chezmoi"

  chezmoi apply --source "$CHEZMOI_SOURCE_DIR" \
    || die "install.sh: aplicación de Chezmoi falló"
}

show_summary()
{
  log_info "install.sh: instalación finalizada"

  if [ "${#FAILED_COMPONENTS[@]}" -gt 0 ]; then
    log_warn \
      "install.sh: componentes opcionales con errores: ${FAILED_COMPONENTS[*]}"
  fi

  log_info "install.sh: siguiente paso para configurar GitHub:"
  log_info "  $SCRIPT_DIR/scripts/account.sh setup-primary"
}

main()
{
  validate_environment
  prepare_sudo
  update_package_index
  install_components
  ensure_chezmoi_config
  apply_chezmoi

  if ! sudo chsh -s "$(command -v zsh)" "$USER"; then
    log_warn 'No se pudo configurar Zsh como shell de inicio. Ejecute: chsh -s "$(command -v zsh)"'
  fi

  show_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
