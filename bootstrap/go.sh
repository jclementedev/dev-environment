#!/bin/bash
# Instala Go, lenguaje de programación desarrollado por Google.
# Idempotente mediante el gestor de paquetes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

if command -v go >/dev/null 2>&1; then
  log_info "go: ya instalado"
  exit 0
fi

log_info "go: instalando"

pkg_install golang

if ! command -v go >/dev/null 2>&1; then
  die "go: no quedó accesible tras la instalación"
fi

log_info "go: listo"
