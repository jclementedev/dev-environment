#!/bin/bash
# Bootstrap brew (Homebrew / Linuxbrew).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=log.sh
. "$SCRIPT_DIR/lib/log.sh"

for candidate in \
  /home/linuxbrew/.linuxbrew/bin/brew \
  /usr/local/bin/brew \
  /opt/homebrew/bin/brew; do
  if [ -x "$candidate" ]; then
    export PATH="$(dirname "$candidate"):$PATH"
  fi
done

if command -v brew >/dev/null 2>&1; then
  log_info "brew: ya instalado"
  exit 0
fi

log_info "brew: instalando Homebrew / Linuxbrew"

command -v git >/dev/null 2>&1 || {
  log_warn "brew: requiere git instalado; corre bootstrap/essentials.sh primero"
  exit 1
}

NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
  die "brew: instalación falló"
}

for candidate in /home/linuxbrew/.linuxbrew/bin/brew /usr/local/bin/brew; do
  if [ -x "$candidate" ]; then
    export PATH="$(dirname "$candidate"):$PATH"
    break
  fi
done

if ! command -v brew >/dev/null 2>&1; then
  die "brew: instalación no produjo un binario accesible"
fi

log_info "brew: listo"
