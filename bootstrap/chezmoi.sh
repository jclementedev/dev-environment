#!/bin/bash
# Instala o actualiza chezmoi mediante su instalador oficial.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly CHEZMOI_INSTALLER_URL="https://get.chezmoi.io"
readonly CHEZMOI_INSTALL_DIR="$HOME/.local/bin"
readonly CHEZMOI_TARGET="$CHEZMOI_INSTALL_DIR/chezmoi"

case ":$PATH:" in
  *":$CHEZMOI_INSTALL_DIR:"*) ;;
  *) export PATH="$CHEZMOI_INSTALL_DIR:$PATH" ;;
esac

require_command()
{
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "chezmoi: se requiere '$command_name'"
    return 1
  fi
}

get_chezmoi_version()
{
  if [ ! -x "$CHEZMOI_TARGET" ]; then
    return 0
  fi

  "$CHEZMOI_TARGET" --version 2>/dev/null || true
}

run_official_installer()
(
  local installer_file

  require_command curl || return 1
  require_command sh || return 1

  if ! mkdir -p "$CHEZMOI_INSTALL_DIR"; then
    log_error "chezmoi: no se pudo crear $CHEZMOI_INSTALL_DIR"
    return 1
  fi

  if ! installer_file="$(mktemp)"; then
    log_error "chezmoi: no se pudo crear el archivo temporal"
    return 1
  fi

  trap 'rm -f -- "$installer_file"' EXIT

  log_info "chezmoi: descargando instalador oficial"

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      "$CHEZMOI_INSTALLER_URL" \
      -o "$installer_file"; then
    log_error "chezmoi: no se pudo descargar el instalador oficial"
    return 1
  fi

  log_info "chezmoi: instalando la última versión estable"

  if ! sh "$installer_file" -b "$CHEZMOI_INSTALL_DIR"; then
    log_error "chezmoi: el instalador oficial falló"
    return 1
  fi
)

validate_installation()
{
  local installed_version

  if [ ! -x "$CHEZMOI_TARGET" ]; then
    log_error "chezmoi: el ejecutable no quedó instalado en $CHEZMOI_INSTALL_DIR"
    return 1
  fi

  installed_version="$(get_chezmoi_version)"

  if [ -z "$installed_version" ]; then
    log_error "chezmoi: no se pudo validar la versión instalada"
    return 1
  fi
}

install_chezmoi()
{
  local installed_version

  if [ -x "$CHEZMOI_TARGET" ]; then
    installed_version="$(get_chezmoi_version)"

    if [ -n "$installed_version" ]; then
      log_info "chezmoi: ya instalado ($installed_version)"
      return 0
    fi

    log_info "chezmoi: instalación existente no válida; se reinstalará"
  fi

  run_official_installer || return 1
  validate_installation || return 1

  log_info "chezmoi: listo ($(get_chezmoi_version))"
}

update_chezmoi()
{
  local installed_version
  local updated_version

  if [ ! -x "$CHEZMOI_TARGET" ]; then
    log_info "chezmoi: no hay instalación previa; ejecutando instalación"
    install_chezmoi
    return
  fi

  installed_version="$(get_chezmoi_version)"

  if [ -z "$installed_version" ]; then
    log_error "chezmoi: la instalación existente no es válida"
    return 1
  fi

  log_info "chezmoi: actualizando ($installed_version)"

  run_official_installer || return 1
  validate_installation || return 1

  updated_version="$(get_chezmoi_version)"

  log_info "chezmoi: actualizado ($installed_version → $updated_version)"
}

main()
{
  case "${1:-install}" in
    install)
      install_chezmoi
      ;;
    update)
      update_chezmoi
      ;;
    *)
      log_error "chezmoi: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
