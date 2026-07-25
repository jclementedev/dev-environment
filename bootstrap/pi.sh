#!/bin/bash
# Instala Pi, agente IA para desarrollo.
# Usa el paquete npm oficial y sigue la última versión estable.
# Instala Pi en ~/.local para mantener los binarios de usuario centralizados.

set -euo pipefail

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

for dependency in node npm; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    die "pi: requiere $dependency; ejecuta bootstrap/node.sh primero"
  fi
done

log_info "pi: instalando la última versión estable vía npm"

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
