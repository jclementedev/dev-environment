#!/bin/bash
# Instala eza, reemplazo moderno de ls.
# Idempotente mediante el gestor de paquetes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

if command -v eza >/dev/null 2>&1; then
  log_info "eza: ya instalado"
  exit 0
fi

log_info "eza: instalando"

pkg_install eza

if ! command -v eza >/dev/null 2>&1; then
  die "eza: no quedó accesible tras la instalación"
fi

log_info "eza: listo"