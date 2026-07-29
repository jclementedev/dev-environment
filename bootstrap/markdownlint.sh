#!/bin/bash
# Instala o actualiza markdownlint-cli2, linter para archivos Markdown.
# Usa el paquete npm oficial y el prefijo global predeterminado de npm.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

# shellcheck source=lib/node-env.sh
. "$SCRIPT_DIR/lib/node-env.sh"

readonly MARKDOWNLINT_PACKAGE="markdownlint-cli2"

get_markdownlint_version()
{
  if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
    return 0
  fi

  markdownlint-cli2 --version 2>/dev/null || true
}

install_package()
{
  if ! npm install \
      --global \
      --ignore-scripts \
      "$MARKDOWNLINT_PACKAGE"; then
    log_error "markdownlint-cli2: la operación mediante npm falló"
    return 1
  fi
}

validate_installation()
{
  local installed_version

  if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
    log_error "markdownlint-cli2: el ejecutable no quedó accesible tras la instalación"
    return 1
  fi

  installed_version="$(get_markdownlint_version)"

  if [ -z "$installed_version" ]; then
    log_error "markdownlint-cli2: no se pudo validar la versión instalada"
    return 1
  fi
}

install_markdownlint()
{
  local installed_version

  load_node_env \
    || die "markdownlint-cli2: requiere Node.js y npm; ejecuta bootstrap/node.sh primero"

  installed_version="$(get_markdownlint_version)"

  if [ -n "$installed_version" ]; then
    log_info "markdownlint-cli2: ya instalado ($installed_version)"
    return 0
  fi

  log_info "markdownlint-cli2: instalando la última versión estable vía npm"

  install_package || return 1
  validate_installation || return 1

  log_info "markdownlint-cli2: listo ($(get_markdownlint_version))"
}

update_markdownlint()
{
  local previous_version
  local current_version

  load_node_env \
    || die "markdownlint-cli2: requiere Node.js y npm; ejecuta bootstrap/node.sh primero"

  previous_version="$(get_markdownlint_version)"

  if [ -n "$previous_version" ]; then
    log_info "markdownlint-cli2: actualizando ($previous_version)"
  else
    log_info "markdownlint-cli2: no hay instalación previa; ejecutando instalación"
  fi

  install_package || return 1
  validate_installation || return 1

  current_version="$(get_markdownlint_version)"

  if [ -n "$previous_version" ]; then
    log_info "markdownlint-cli2: actualizado ($previous_version → $current_version)"
  else
    log_info "markdownlint-cli2: listo ($current_version)"
  fi
}

main()
{
  case "${1:-install}" in
    install)
      install_markdownlint
      ;;
    update)
      update_markdownlint
      ;;
    *)
      log_error "markdownlint-cli2: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
