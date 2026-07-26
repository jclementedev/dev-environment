#!/bin/bash
# Instala o actualiza Pi, agente IA para desarrollo.
# Usa el paquete npm oficial y sigue la última versión estable.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly PI_PREFIX="$HOME/.local"
readonly PI_INSTALL_DIR="$PI_PREFIX/bin"
readonly PI_TARGET="$PI_INSTALL_DIR/pi"

case ":$PATH:" in
  *":$PI_INSTALL_DIR:"*) ;;
  *) export PATH="$PI_INSTALL_DIR:$PATH" ;;
esac

require_node()
{
  local dependency

  for dependency in node npm; do
    command -v "$dependency" >/dev/null 2>&1 \
      || die "pi: requiere $dependency; ejecuta bootstrap/node.sh primero"
  done
}

install_pi()
{
  local installed_version

  require_node

  log_info "pi: instalando o actualizando la última versión estable vía npm"

  if ! npm install \
      --global \
      --prefix "$PI_PREFIX" \
      --ignore-scripts \
      @earendil-works/pi-coding-agent@latest; then
    die "pi: la instalación mediante npm falló"
  fi

  if [ ! -x "$PI_TARGET" ]; then
    die "pi: el ejecutable no quedó instalado en $PI_INSTALL_DIR"
  fi

  installed_version="$("$PI_TARGET" --version 2>/dev/null || true)"

  log_info "pi: listo (${installed_version:-versión desconocida})"
}

update_pi()
{
  local installed_version

  require_node

  log_info "pi: actualizando la última versión estable vía npm"

  if ! npm install \
      --global \
      --prefix "$PI_PREFIX" \
      --ignore-scripts \
      @earendil-works/pi-coding-agent@latest; then
    log_error "pi: la actualización mediante npm falló"
    return 1
  fi

  if [ ! -x "$PI_TARGET" ]; then
    log_error "pi: el ejecutable no quedó instalado en $PI_INSTALL_DIR"
    return 1
  fi

  installed_version="$("$PI_TARGET" --version 2>/dev/null || true)"

  log_info "pi: listo (${installed_version:-versión desconocida})"
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
