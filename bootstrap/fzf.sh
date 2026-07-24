#!/bin/bash
# Instala fzf, buscador difuso para la línea de comandos.
# Idempotente mediante el gestor de paquetes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

if command -v fzf >/dev/null 2>&1; then
  log_info "fzf: ya instalado"
  exit 0
fi

log_info "fzf: instalando"

pkg_install fzf

if ! command -v fzf >/dev/null 2>&1; then
  die "fzf: no quedó accesible tras la instalación"
fi

log_info "fzf: listo"