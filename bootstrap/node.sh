#!/bin/bash
# Instala fnm y la versión LTS de Node.js.
# La configuración persistente del shell se administra mediante Chezmoi.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

FNM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"

export PATH="$FNM_DIR:$PATH"

for dependency in curl unzip; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    die "node: requiere $dependency; ejecuta essentials.sh primero"
  fi
done

if ! command -v fnm >/dev/null 2>&1; then
  log_info "node: instalando fnm"

  curl -fsSL https://fnm.vercel.app/install \
    | bash -s -- \
        --install-dir "$FNM_DIR" \
        --skip-shell
fi

if ! command -v fnm >/dev/null 2>&1; then
  die "node: fnm no quedó accesible tras la instalación"
fi

# Configura fnm únicamente para esta ejecución de Bash.
eval "$(fnm env --shell bash)"

log_info "node: instalando la versión LTS"

fnm install --lts
fnm default lts-latest
fnm use lts-latest

for tool in node npm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    die "node: $tool no quedó accesible tras la instalación"
  fi
done

log_info "node: listo ($(node --version), npm $(npm --version))"