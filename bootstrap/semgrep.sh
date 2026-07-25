#!/bin/bash
# Instala Semgrep, analizador estático multilenguaje.
# Usa pipx para mantener un entorno aislado.
# Instala o actualiza Semgrep a la última versión estable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly SEMGREP_INSTALL_DIR="$HOME/.local/bin"
readonly SEMGREP_TARGET="$SEMGREP_INSTALL_DIR/semgrep"

export PIPX_BIN_DIR="$SEMGREP_INSTALL_DIR"

case ":$PATH:" in
  *":$SEMGREP_INSTALL_DIR:"*) ;;
  *) export PATH="$SEMGREP_INSTALL_DIR:$PATH" ;;
esac

if ! command -v pipx >/dev/null 2>&1; then
  die "semgrep: requiere pipx; ejecuta bootstrap/python.sh primero"
fi

log_info "semgrep: instalando o actualizando la última versión estable vía pipx"

if ! pipx install --upgrade semgrep; then
  die "semgrep: la instalación o actualización mediante pipx falló"
fi

if [ ! -x "$SEMGREP_TARGET" ]; then
  die "semgrep: el ejecutable no quedó instalado en $SEMGREP_INSTALL_DIR"
fi

installed_version="$("$SEMGREP_TARGET" --version 2>/dev/null || true)"

log_info "semgrep: listo (${installed_version:-versión desconocida})"
