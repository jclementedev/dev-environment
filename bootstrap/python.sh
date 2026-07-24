#!/bin/bash
# Instala Python 3, soporte para entornos virtuales y pipx.
# Las dependencias de cada proyecto deben instalarse en entornos aislados.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

python_is_ready()
{
  command -v python3 >/dev/null 2>&1 \
    && command -v pipx >/dev/null 2>&1 \
    && python3 -m venv --help >/dev/null 2>&1
}

if python_is_ready; then
  log_info "python: ya instalado ($(python3 --version), pipx $(pipx --version))"
  exit 0
fi

log_info "python: instalando"

pkg_install \
  python3 \
  python3-venv \
  pipx

if ! command -v python3 >/dev/null 2>&1; then
  die "python: python3 no quedó accesible tras la instalación"
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
  die "python: el módulo venv no quedó disponible tras la instalación"
fi

if ! command -v pipx >/dev/null 2>&1; then
  die "python: pipx no quedó accesible tras la instalación"
fi

log_info "python: listo ($(python3 --version), pipx $(pipx --version))"