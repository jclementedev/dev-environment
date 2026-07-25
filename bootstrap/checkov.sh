#!/bin/bash
# Instala Checkov, linter de seguridad para infraestructura como código.
# Usa pipx para mantener un entorno aislado.
# Instala o actualiza Checkov a la última versión estable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly CHECKOV_INSTALL_DIR="$HOME/.local/bin"
readonly CHECKOV_TARGET="$CHECKOV_INSTALL_DIR/checkov"

export PIPX_BIN_DIR="$CHECKOV_INSTALL_DIR"

case ":$PATH:" in
  *":$CHECKOV_INSTALL_DIR:"*) ;;
  *) export PATH="$CHECKOV_INSTALL_DIR:$PATH" ;;
esac

if ! command -v pipx >/dev/null 2>&1; then
  die "checkov: requiere pipx; ejecuta bootstrap/python.sh primero"
fi

log_info "checkov: instalando o actualizando la última versión estable vía pipx"

if ! pipx install --upgrade checkov; then
  die "checkov: la instalación o actualización mediante pipx falló"
fi

if [ ! -x "$CHECKOV_TARGET" ]; then
  die "checkov: el ejecutable no quedó instalado en $CHECKOV_INSTALL_DIR"
fi

installed_version="$("$CHECKOV_TARGET" --version 2>/dev/null || true)"

log_info "checkov: listo (${installed_version:-versión desconocida})"
