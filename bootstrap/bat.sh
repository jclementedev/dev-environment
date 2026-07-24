#!/bin/bash
# Instala bat, clon de cat con resaltado de sintaxis.
# En Ubuntu, el binario puede instalarse como batcat.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

if command -v bat >/dev/null 2>&1; then
  log_info "bat: ya instalado"
  exit 0
fi

if ! command -v batcat >/dev/null 2>&1; then
  log_info "bat: instalando"
  pkg_install bat
fi

if command -v batcat >/dev/null 2>&1; then
  log_info "bat: batcat disponible; Zsh expone el comando bat"
fi

if ! command -v bat >/dev/null 2>&1 && ! command -v batcat >/dev/null 2>&1; then
  die "bat: ni bat ni batcat quedaron accesibles tras la instalación"
fi

log_info "bat: listo"
