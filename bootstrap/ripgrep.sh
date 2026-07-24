#!/bin/bash
# Instala ripgrep, herramienta de búsqueda recursiva.
# Idempotente mediante el gestor de paquetes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

if command -v rg >/dev/null 2>&1; then
  log_info "ripgrep: ya instalado"
  exit 0
fi

log_info "ripgrep: instalando"

pkg_install ripgrep

if ! command -v rg >/dev/null 2>&1; then
  die "ripgrep: no quedó accesible tras la instalación"
fi

log_info "ripgrep: listo"
