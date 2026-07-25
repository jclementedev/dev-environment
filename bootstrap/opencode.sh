#!/bin/bash
# Instala OpenCode, agente IA para desarrollo.
# Usa el instalador oficial del proveedor.
# Instala o actualiza OpenCode a la última versión estable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly OPENCODE_INSTALL_DIR="$HOME/.local/bin"
readonly OPENCODE_TARGET="$OPENCODE_INSTALL_DIR/opencode"

case ":$PATH:" in
  *":$OPENCODE_INSTALL_DIR:"*) ;;
  *) export PATH="$OPENCODE_INSTALL_DIR:$PATH" ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  die "opencode: requiere curl; ejecuta essentials.sh primero"
fi

log_info "opencode: instalando la última versión estable"

if ! curl -fsSL https://opencode.ai/install \
  | OPENCODE_INSTALL_DIR="$OPENCODE_INSTALL_DIR" \
    bash -s -- --no-modify-path; then
  die "opencode: el instalador oficial falló"
fi

if [ ! -x "$OPENCODE_TARGET" ]; then
  die "opencode: el binario no quedó instalado en $OPENCODE_INSTALL_DIR"
fi

installed_version="$("$OPENCODE_TARGET" --version 2>/dev/null || true)"

log_info "opencode: listo (${installed_version:-versión desconocida})"
