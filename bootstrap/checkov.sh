#!/bin/bash
# Instala checkov, linter de seguridad para infraestructura como código.
# Descarga el binario oficial desde GitHub Releases y verifica su SHA256.
# Idempotente: no reinstala si la versión esperada ya está instalada
# en el destino administrado.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly CHECKOV_VERSION="3.3.8"
readonly CHECKOV_INSTALL_DIR="$HOME/.local/bin"
readonly CHECKOV_TARGET="$CHECKOV_INSTALL_DIR/checkov"

# SHA256 de checkov_linux_{X86_64,arm64}.zip
# Fuente: release oficial de bridgecrewio/checkov.
declare -Ar CHECKOV_SHA256=(
  [amd64]="7f9f62eb3812fee7cb9c570503a266a599f5458b362fe581c14dcf4a44027bd4"
  [arm64]="afe1d3c96df7119f16dd27ac4971eb83d2f9f50ec2150ce9e2bad6f483733b0c"
)

case ":$PATH:" in
  *":$CHECKOV_INSTALL_DIR:"*) ;;
  *) export PATH="$CHECKOV_INSTALL_DIR:$PATH" ;;
esac

installed_version=""

if [ -x "$CHECKOV_TARGET" ]; then
  installed_version="$("$CHECKOV_TARGET" --version 2>/dev/null || true)"

  if [ "$installed_version" = "v${CHECKOV_VERSION}" ] \
    || [ "$installed_version" = "$CHECKOV_VERSION" ]; then
    log_info "checkov: versión esperada ya instalada ($installed_version)"
    exit 0
  fi

  log_info "checkov: versión administrada '${installed_version:-desconocida}'; se instalará v${CHECKOV_VERSION}"
fi

for dependency in curl unzip sha256sum install; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    die "checkov: requiere $dependency; ejecuta essentials.sh primero"
  fi
done

architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"

case "$architecture" in
  amd64 | x86_64)
    arch="amd64"
    asset_name="checkov_linux_X86_64.zip"
    ;;
  arm64 | aarch64)
    arch="arm64"
    asset_name="checkov_linux_arm64.zip"
    ;;
  *)
    die "checkov: arquitectura '$architecture' no soportada"
    ;;
esac

expected_sha="${CHECKOV_SHA256[$arch]}"
asset_url="https://github.com/bridgecrewio/checkov/releases/download/${CHECKOV_VERSION}/${asset_name}"

temp_dir="$(mktemp -d)" \
  || die "checkov: no se pudo crear el directorio temporal"

trap 'rm -rf "$temp_dir"' EXIT

archive_path="$temp_dir/checkov.zip"

log_info "checkov: descargando v${CHECKOV_VERSION} (${arch})"

if ! curl -fsSL \
  --connect-timeout 10 \
  --max-time 60 \
  --retry 3 \
  --retry-delay 2 \
  --retry-connrefused \
  "$asset_url" \
  -o "$archive_path"; then
  die "checkov: no se pudo descargar el binario oficial"
fi

actual_sha="$(sha256sum "$archive_path" | awk '{print $1}')"

if [ "$actual_sha" != "$expected_sha" ]; then
  die "checkov: SHA256 no coincide (esperado=$expected_sha actual=$actual_sha)"
fi

log_info "checkov: SHA256 verificado"

if ! unzip -q "$archive_path" checkov -d "$temp_dir"; then
  die "checkov: no se pudo extraer el binario"
fi

if [ ! -s "$temp_dir/checkov" ]; then
  die "checkov: el binario extraído está vacío o no existe"
fi

mkdir -p "$CHECKOV_INSTALL_DIR"

if ! install -m 0755 "$temp_dir/checkov" "$CHECKOV_TARGET"; then
  die "checkov: no se pudo instalar el binario"
fi

installed_version="$("$CHECKOV_TARGET" --version 2>/dev/null || true)"

if [ "$installed_version" != "v${CHECKOV_VERSION}" ] \
  && [ "$installed_version" != "$CHECKOV_VERSION" ]; then
  die "checkov: versión instalada inesperada: '${installed_version:-desconocida}'"
fi

log_info "checkov: listo ($installed_version)"