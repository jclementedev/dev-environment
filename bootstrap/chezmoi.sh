#!/bin/bash
# Instala chezmoi mediante su instalador oficial.
# Idempotente: no reinstala si ya está disponible.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

INSTALL_DIR="$HOME/.local/bin"

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) export PATH="$INSTALL_DIR:$PATH" ;;
esac

if command -v chezmoi >/dev/null 2>&1; then
  log_info "chezmoi: ya instalado ($(chezmoi --version))"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  die "chezmoi: requiere curl; ejecuta essentials.sh primero"
fi

installer_file="$(mktemp)"
trap 'rm -f "$installer_file"' EXIT

mkdir -p "$INSTALL_DIR"

log_info "chezmoi: descargando instalador oficial"

if ! curl -fsSL https://get.chezmoi.io -o "$installer_file"; then
  die "chezmoi: no se pudo descargar el instalador oficial"
fi

log_info "chezmoi: instalando"

if ! sh "$installer_file" -b "$INSTALL_DIR"; then
  die "chezmoi: el instalador oficial falló"
fi

if ! command -v chezmoi >/dev/null 2>&1; then
  die "chezmoi: no quedó accesible tras la instalación"
fi

log_info "chezmoi: listo ($(chezmoi --version))"