#!/bin/bash
# Instala actionlint, linter para workflows de GitHub Actions.
# Descarga el binario oficial desde GitHub Releases y verifica su SHA256.
# Idempotente: no reinstala si la versión esperada ya está disponible.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly ACTIONLINT_VERSION="1.7.12"
readonly ACTIONLINT_INSTALL_DIR="$HOME/.local/bin"
readonly ACTIONLINT_TARGET="$ACTIONLINT_INSTALL_DIR/actionlint"

# SHA256 de actionlint_${ACTIONLINT_VERSION}_linux_{amd64,arm64}.tar.gz
# Fuente: release oficial de rhysd/actionlint.
declare -Ar ACTIONLINT_SHA256=(
  [amd64]="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
  [arm64]="325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6"
)

case ":$PATH:" in
  *":$ACTIONLINT_INSTALL_DIR:"*) ;;
  *) export PATH="$ACTIONLINT_INSTALL_DIR:$PATH" ;;
esac

for dependency in curl tar sha256sum install; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    die "actionlint: requiere $dependency; ejecuta essentials.sh primero"
  fi
done

installed_version=""

if command -v actionlint >/dev/null 2>&1; then
  installed_version="$(actionlint -version 2>/dev/null || true)"

  if [ "$installed_version" = "v${ACTIONLINT_VERSION}" ] \
    || [ "$installed_version" = "$ACTIONLINT_VERSION" ]; then
    log_info "actionlint: versión esperada ya instalada ($installed_version)"
    exit 0
  fi

  log_info "actionlint: versión encontrada '${installed_version:-desconocida}'; se instalará v${ACTIONLINT_VERSION}"
fi

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

expected_sha="${ACTIONLINT_SHA256[$arch]}"
asset_url="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz"

temp_dir="$(mktemp -d)" \
  || die "actionlint: no se pudo crear el directorio temporal"

trap 'rm -rf "$temp_dir"' EXIT

archive_path="$temp_dir/actionlint.tar.gz"

log_info "actionlint: descargando v${ACTIONLINT_VERSION} (${arch})"

if ! curl -fsSL \
  --connect-timeout 10 \
  --max-time 60 \
  --retry 3 \
  --retry-delay 2 \
  --retry-connrefused \
  "$asset_url" \
  -o "$archive_path"; then
  die "actionlint: no se pudo descargar el binario oficial"
fi

actual_sha="$(sha256sum "$archive_path" | awk '{print $1}')"

if [ "$actual_sha" != "$expected_sha" ]; then
  die "actionlint: SHA256 no coincide (esperado=$expected_sha actual=$actual_sha)"
fi

log_info "actionlint: SHA256 verificado"

if ! tar -xzf "$archive_path" -C "$temp_dir" actionlint; then
  die "actionlint: no se pudo extraer el binario"
fi

if [ ! -s "$temp_dir/actionlint" ]; then
  die "actionlint: el binario extraído está vacío o no existe"
fi

mkdir -p "$ACTIONLINT_INSTALL_DIR"

if ! install -m 0755 "$temp_dir/actionlint" "$ACTIONLINT_TARGET"; then
  die "actionlint: no se pudo instalar el binario"
fi

installed_version="$("$ACTIONLINT_TARGET" -version 2>/dev/null || true)"

if [ "$installed_version" != "v${ACTIONLINT_VERSION}" ] \
  && [ "$installed_version" != "$ACTIONLINT_VERSION" ]; then
  die "actionlint: versión instalada inesperada: '${installed_version:-desconocida}'"
fi

log_info "actionlint: listo ($installed_version)"