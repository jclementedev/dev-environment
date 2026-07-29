#!/bin/bash
# Instala o actualiza Starship, prompt multiplataforma para shells.
# Usa el instalador oficial; la configuración del shell se administra mediante Chezmoi.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly STARSHIP_INSTALL_DIR="$HOME/.local/bin"
readonly STARSHIP_TARGET="$STARSHIP_INSTALL_DIR/starship"
readonly STARSHIP_INSTALLER_URL="https://starship.rs/install.sh"

case ":$PATH:" in
  *":$STARSHIP_INSTALL_DIR:"*) ;;
  *) export PATH="$STARSHIP_INSTALL_DIR:$PATH" ;;
esac

require_command()
{
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "starship: se requiere '$command_name'"
    return 1
  fi
}

get_starship_version()
{
  if [ ! -x "$STARSHIP_TARGET" ]; then
    return 0
  fi

  "$STARSHIP_TARGET" --version 2>/dev/null \
    | head -n 1 \
    || true
}

validate_installation()
{
  local installed_version

  if [ ! -x "$STARSHIP_TARGET" ]; then
    log_error "starship: el binario no quedó disponible en $STARSHIP_TARGET"
    return 1
  fi

  installed_version="$(get_starship_version)"

  if [ -z "$installed_version" ]; then
    log_error "starship: no se pudo validar la versión instalada"
    return 1
  fi
}

run_official_installer()
{
  require_command curl || return 1
  require_command tar || return 1

  if ! mkdir -p "$STARSHIP_INSTALL_DIR"; then
    log_error "starship: no se pudo crear $STARSHIP_INSTALL_DIR"
    return 1
  fi

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 300 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      "$STARSHIP_INSTALLER_URL" \
    | sh -s -- \
        --yes \
        --bin-dir "$STARSHIP_INSTALL_DIR"; then
    log_error "starship: el instalador oficial falló"
    return 1
  fi
}

install_starship()
{
  local installed_version

  if [ -x "$STARSHIP_TARGET" ]; then
    installed_version="$(get_starship_version)"

    if [ -n "$installed_version" ]; then
      log_info "starship: ya instalado ($installed_version)"
      return 0
    fi

    log_info "starship: instalación existente no válida; se reinstalará"
  fi

  log_info "starship: instalando la última versión estable"

  run_official_installer || return 1
  validate_installation || return 1

  log_info "starship: listo ($(get_starship_version))"
}

update_starship()
{
  local previous_version
  local current_version

  if [ ! -x "$STARSHIP_TARGET" ]; then
    log_info "starship: no hay instalación previa; ejecutando instalación"
    install_starship
    return
  fi

  previous_version="$(get_starship_version)"

  if [ -z "$previous_version" ]; then
    log_info "starship: instalación existente no válida; se reinstalará"
  else
    log_info "starship: actualizando ($previous_version)"
  fi

  run_official_installer || return 1
  validate_installation || return 1

  current_version="$(get_starship_version)"

  if [ -n "$previous_version" ]; then
    log_info "starship: actualizado ($previous_version → $current_version)"
  else
    log_info "starship: listo ($current_version)"
  fi
}

main()
{
  case "${1:-install}" in
    install)
      install_starship
      ;;
    update)
      update_starship
      ;;
    *)
      log_error "starship: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
