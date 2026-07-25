#!/bin/bash
# Instala actionlint, linter para workflows de GitHub Actions.
# Descarga el binario oficial de la última release disponible.
# Idempotente: no reinstala si el ejecutable administrado ya existe.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly ACTIONLINT_INSTALL_DIR="$HOME/.local/bin"
readonly ACTIONLINT_TARGET="$ACTIONLINT_INSTALL_DIR/actionlint"

case ":$PATH:" in
  *":$ACTIONLINT_INSTALL_DIR:"*) ;;
  *) export PATH="$ACTIONLINT_INSTALL_DIR:$PATH" ;;
esac

if [ -x "$ACTIONLINT_TARGET" ]; then
  installed_version="$("$ACTIONLINT_TARGET" -version 2>/dev/null || true)"

  if [ -n "$installed_version" ]; then
    log_info "actionlint: ya instalado ($installed_version)"
    exit 0
  fi

  log_info "actionlint: instalación existente no válida; se reinstalará"
fi

for dependency in curl tar install; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    die "actionlint: requiere $dependency; ejecuta essentials.sh primero"
  fi
done

architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"

case "$architecture" in
  amd64 | x86_64)
    arch="amd64"
    ;;
  arm64 | aarch64)
    arch="arm64"
    ;;
  *)
    die "actionlint: arquitectura '$architecture' no soportada"
    ;;
esac

temp_dir="$(mktemp -d)" ||
  die "actionlint: no se pudo crear el directorio temporal"

trap 'rm -rf "$temp_dir"' EXIT

log_info "actionlint: descargando el instalador oficial"

if ! curl -fsSL \
  --connect-timeout 10 \
  --max-time 60 \
  --retry 3 \
  --retry-delay 2 \
  --retry-connrefused \
  https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash |
  bash -s -- latest "$temp_dir"; then
  die "actionlint: la instalación mediante el script oficial falló"
fi

binary_path="$temp_dir/actionlint"

if [ ! -s "$binary_path" ]; then
  die "actionlint: el binario descargado está vacío o no existe"
fi

mkdir -p "$ACTIONLINT_INSTALL_DIR"

if ! install -m 0755 "$binary_path" "$ACTIONLINT_TARGET"; then
  die "actionlint: no se pudo instalar el binario"
fi

installed_version="$("$ACTIONLINT_TARGET" -version 2>/dev/null || true)"

if [ -z "$installed_version" ]; then
  die "actionlint: el ejecutable instalado no funciona correctamente"
fi

log_info "actionlint: listo ($installed_version)"