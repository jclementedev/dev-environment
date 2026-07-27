#!/bin/bash
# Instala o actualiza OpenCode, agente IA para desarrollo.
# Usa el instalador oficial del proveedor y conserva su destino por defecto.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly OPENCODE_INSTALL_DIR="$HOME/.opencode/bin"
readonly OPENCODE_TARGET="$OPENCODE_INSTALL_DIR/opencode"
readonly OPENCODE_INSTALLER_URL="https://opencode.ai/install"

case ":$PATH:" in
  *":$OPENCODE_INSTALL_DIR:"*) ;;
  *) export PATH="$OPENCODE_INSTALL_DIR:$PATH" ;;
esac

require_command()
{
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "opencode: se requiere '$command_name'"
    return 1
  fi
}

get_opencode_version()
{
  if [ ! -x "$OPENCODE_TARGET" ]; then
    return 0
  fi

  "$OPENCODE_TARGET" --version 2>/dev/null || true
}

validate_installation()
{
  local installed_version

  if [ ! -x "$OPENCODE_TARGET" ]; then
    log_error "opencode: el binario no quedó disponible en $OPENCODE_TARGET"
    return 1
  fi

  installed_version="$(get_opencode_version)"

  if [ -z "$installed_version" ]; then
    log_error "opencode: no se pudo validar la versión instalada"
    return 1
  fi
}

run_official_installer()
{
  require_command curl || return 1
  require_command bash || return 1

  log_info "opencode: instalando la última versión estable"

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 300 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      "$OPENCODE_INSTALLER_URL" \
    | bash -s -- --no-modify-path; then
    log_error "opencode: el instalador oficial falló"
    return 1
  fi
}

install_opencode()
{
  local installed_version

  if [ -x "$OPENCODE_TARGET" ]; then
    installed_version="$(get_opencode_version)"

    if [ -n "$installed_version" ]; then
      log_info "opencode: ya instalado ($installed_version)"
      return 0
    fi

    log_info "opencode: instalación existente no válida; se reinstalará"
  fi

  run_official_installer || return 1
  validate_installation || return 1

  log_info "opencode: listo ($(get_opencode_version))"
}

update_opencode()
{
  local installed_version

  if [ ! -x "$OPENCODE_TARGET" ]; then
    log_info "opencode: no hay instalación previa; ejecutando instalación"
    install_opencode
    return
  fi

  installed_version="$(get_opencode_version)"

  if [ -z "$installed_version" ]; then
    log_error "opencode: la instalación existente no es válida"
    return 1
  fi

  log_info "opencode: actualizando ($installed_version)"

  if ! "$OPENCODE_TARGET" upgrade --method curl; then
    log_error "opencode: la actualización falló"
    return 1
  fi

  validate_installation || return 1

  log_info "opencode: actualizado ($installed_version → $(get_opencode_version))"
}

main()
{
  case "${1:-install}" in
    install)
      install_opencode
      ;;
    update)
      update_opencode
      ;;
    *)
      log_error "opencode: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
