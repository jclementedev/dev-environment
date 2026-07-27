#!/bin/bash
# Instala o actualiza Pi, agente IA para desarrollo.
# Usa el instalador oficial del proveedor y conserva su destino por defecto.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly PI_INSTALLER_URL="https://pi.dev/install.sh"

require_command()
{
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "pi: se requiere '$command_name'"
    return 1
  fi
}

get_pi_version()
{
  if ! command -v pi >/dev/null 2>&1; then
    return 0
  fi

  pi --version 2>/dev/null || true
}

run_official_installer()
{
  require_command curl || return 1
  require_command sh || return 1

  log_info "pi: instalando la última versión estable"

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 300 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      "$PI_INSTALLER_URL" \
    | sh; then
    log_error "pi: el instalador oficial falló"
    return 1
  fi
}

validate_installation()
{
  local installed_version

  if ! command -v pi >/dev/null 2>&1; then
    log_error "pi: el binario no quedó accesible tras la instalación"
    return 1
  fi

  installed_version="$(get_pi_version)"

  if [ -z "$installed_version" ]; then
    log_error "pi: no se pudo validar la versión instalada"
    return 1
  fi
}

install_pi()
{
  local installed_version

  if command -v pi >/dev/null 2>&1; then
    installed_version="$(get_pi_version)"

    if [ -n "$installed_version" ]; then
      log_info "pi: ya instalado ($installed_version)"
      return 0
    fi

    log_info "pi: instalación existente no válida; se reinstalará"
  fi

  require_command node || return 1
  require_command npm || return 1

  run_official_installer || return 1
  validate_installation || return 1

  log_info "pi: listo ($(get_pi_version))"
}

update_pi()
{
  local installed_version

  if ! command -v pi >/dev/null 2>&1; then
    log_info "pi: no hay instalación previa; ejecutando instalación"
    install_pi
    return
  fi

  installed_version="$(get_pi_version)"

  if [ -z "$installed_version" ]; then
    log_error "pi: la instalación existente no es válida"
    return 1
  fi

  log_info "pi: actualizando ($installed_version)"

  if ! pi update --self; then
    log_error "pi: la actualización falló"
    return 1
  fi

  validate_installation || return 1

  log_info "pi: actualizado ($installed_version → $(get_pi_version))"
}

main()
{
  case "${1:-install}" in
    install)
      install_pi
      ;;
    update)
      update_pi
      ;;
    *)
      log_error "pi: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"