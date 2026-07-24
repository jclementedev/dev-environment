#!/bin/bash
# Instala Zsh, sus plugins y Starship.
# Idempotente mediante el gestor de paquetes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

log_info "shell: instalando zsh, plugins y starship"

pkg_install \
  zsh \
  zsh-autosuggestions \
  zsh-syntax-highlighting \
  starship

for tool in zsh starship; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    die "shell: $tool no quedó accesible tras la instalación"
  fi
done

log_info "shell: listo"