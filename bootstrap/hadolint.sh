#!/bin/bash
# Instala Hadolint, linter para Dockerfiles.
# Descarga el binario oficial de la última versión publicada en GitHub Releases.
# Idempotente: no reinstala si el ejecutable administrado ya está disponible.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly HADOLINT_INSTALL_DIR="$HOME/.local/bin"
readonly HADOLINT_TARGET="$HADOLINT_INSTALL_DIR/hadolint"

case ":$PATH:" in
  *":$HADOLINT_INSTALL_DIR:"*) ;;
  *) export PATH="$HADOLINT_INSTALL_DIR:$PATH" ;;
esac

if [ -x "$HADOLINT_TARGET" ]; then
  installed_version="$("$HADOLINT_TARGET" --version 2>/dev/null || true)"

  if [ -n "$installed_version" ]; then
    log_info "hadolint: ya instalado ($installed_version)"
    exit 0
  fi

  log_info "hadolint: instalación existente no válida; se reinstalará"
fi

for dependency in curl install; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    die "hadolint: requiere $dependency; ejecuta essentials.sh primero"
  fi
done

architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"

case "$architecture" in
  amd64 | x86_64)
    asset_name="hadolint-linux-x86_64"
    ;;
  arm64 | aarch64)
    asset_name="hadolint-linux-arm64"
    ;;
  *)
    die "hadolint: arquitectura '$architecture' no soportada"
    ;;
esac

readonly asset_url="https://github.com/hadolint/hadolint/releases/latest/download/${asset_name}"

temp_dir="$(mktemp -d)" ||
  die "hadolint: no se pudo crear el directorio temporal"

trap 'rm -rf "$temp_dir"' EXIT

binary_path="$temp_dir/hadolint"

log_info "hadolint: descargando la última versión estable"

if ! curl -fsSL \
  --connect-timeout 10 \
  --max-time 60 \
  --retry 3 \
  --retry-delay 2 \
  --retry-connrefused \
  "$asset_url" \
  -o "$binary_path"; then
  die "hadolint: no se pudo descargar el binario oficial"
fi

if [ ! -s "$binary_path" ]; then
  die "hadolint: el binario descargado está vacío o no existe"
fi

mkdir -p "$HADOLINT_INSTALL_DIR"

if ! install -m 0755 "$binary_path" "$HADOLINT_TARGET"; then
  die "hadolint: no se pudo instalar el binario"
fi

installed_version="$("$HADOLINT_TARGET" --version 2>/dev/null || true)"

if [ -z "$installed_version" ]; then
  die "hadolint: el ejecutable instalado no funciona correctamente"
fi

log_info "hadolint: listo ($installed_version)"
