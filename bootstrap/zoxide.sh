#!/bin/bash
# Instala zoxide, reemplazo inteligente de cd.
# Idempotente mediante el gestor de paquetes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

if command -v zoxide >/dev/null 2>&1; then
  log_info "zoxide: ya instalado"
  exit 0
fi

log_info "zoxide: instalando"

pkg_install zoxide

if ! command -v zoxide >/dev/null 2>&1; then
  die "zoxide: no quedó accesible tras la instalación"
fi

log_info "zoxide: listo"