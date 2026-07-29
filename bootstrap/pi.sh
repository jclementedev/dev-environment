#!/bin/bash
# Instala o actualiza Pi, agente IA para desarrollo.
# Usa el paquete npm oficial y el prefijo global predeterminado de npm.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

# shellcheck source=lib/node-env.sh
. "$SCRIPT_DIR/lib/node-env.sh"

readonly PI_PACKAGE="@earendil-works/pi-coding-agent"

get_pi_version()
{
  if ! command -v pi >/dev/null 2>&1; then
    return 0
  fi

  pi --version 2>/dev/null || true
}

install_package()
{
  if ! npm install \
      --global \
      --ignore-scripts \
      "$PI_PACKAGE"; then
    log_error "pi: la operación mediante npm falló"
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

  load_node_env \
    || die "pi: requiere Node.js y npm; ejecuta bootstrap/node.sh primero"

  installed_version="$(get_pi_version)"

  if [ -n "$installed_version" ]; then
    log_info "pi: ya instalado ($installed_version)"
    return 0
  fi

  log_info "pi: instalando la última versión estable vía npm"

  install_package || return 1
  validate_installation || return 1

  log_info "pi: listo ($(get_pi_version))"
}

update_pi()
{
  local previous_version
  local current_version

  load_node_env \
    || die "pi: requiere Node.js y npm; ejecuta bootstrap/node.sh primero"

  previous_version="$(get_pi_version)"

  if [ -n "$previous_version" ]; then
    log_info "pi: actualizando ($previous_version)"
  else
    log_info "pi: no hay instalación previa; ejecutando instalación"
  fi

  install_package || return 1
  validate_installation || return 1

  current_version="$(get_pi_version)"

  if [ -n "$previous_version" ]; then
    log_info "pi: actualizado ($previous_version → $current_version)"
  else
    log_info "pi: listo ($current_version)"
  fi
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
