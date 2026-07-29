#!/bin/bash
# Instala Zsh y sus plugins.
# Idempotente mediante el gestor de paquetes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

log_info "shell: instalando zsh y plugins"

pkg_install \
  zsh \
  zsh-autosuggestions \
  zsh-syntax-highlighting

if ! command -v zsh >/dev/null 2>&1; then
  die "shell: zsh no quedó accesible tras la instalación"
fi

log_info "shell: listo"