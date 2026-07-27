#!/bin/bash
# Instala o actualiza Herdr, multiplexor para supervisar agentes IA en paneles.
# Usa el instalador oficial del proveedor y conserva su destino por defecto.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly HERDR_INSTALLER_URL="https://herdr.dev/install.sh"

require_command()
{
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "herdr: se requiere '$command_name'"
    return 1
  fi
}

get_herdr_version()
{
  if ! command -v herdr >/dev/null 2>&1; then
    return 0
  fi

  herdr --version 2>/dev/null || true
}

run_official_installer()
{
  require_command curl || return 1
  require_command sh || return 1

  log_info "herdr: instalando la última versión estable"

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 300 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      "$HERDR_INSTALLER_URL" \
    | sh; then
    log_error "herdr: el instalador oficial falló"
    return 1
  fi
}

validate_installation()
{
  local installed_version

  if ! command -v herdr >/dev/null 2>&1; then
    log_error "herdr: el binario no quedó accesible tras la instalación"
    return 1
  fi

  installed_version="$(get_herdr_version)"

  if [ -z "$installed_version" ]; then
    log_error "herdr: no se pudo validar la versión instalada"
    return 1
  fi
}

install_herdr()
{
  local installed_version

  if command -v herdr >/dev/null 2>&1; then
    installed_version="$(get_herdr_version)"

    if [ -n "$installed_version" ]; then
      log_info "herdr: ya instalado ($installed_version)"
      return 0
    fi

    log_info "herdr: instalación existente no válida; se reinstalará"
  fi

  run_official_installer || return 1
  validate_installation || return 1

  log_info "herdr: listo ($(get_herdr_version))"
}

update_herdr()
{
  local installed_version
  local updated_version

  if ! command -v herdr >/dev/null 2>&1; then
    log_info "herdr: no hay instalación previa; ejecutando instalación"
    install_herdr
    return
  fi

  installed_version="$(get_herdr_version)"

  if [ -z "$installed_version" ]; then
    log_error "herdr: la instalación existente no es válida"
    return 1
  fi

  log_info "herdr: actualizando ($installed_version)"

  if ! herdr update; then
    log_error "herdr: la actualización falló"
    return 1
  fi

  validate_installation || return 1

  updated_version="$(get_herdr_version)"

  log_info "herdr: actualizado ($installed_version → $updated_version)"
}

main()
{
  case "${1:-install}" in
    install)
      install_herdr
      ;;
    update)
      update_herdr
      ;;
    *)
      log_error "herdr: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
