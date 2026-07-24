#!/bin/bash
# Instala Terraform desde el repositorio oficial de HashiCorp.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

if command -v terraform >/dev/null 2>&1; then
  log_info "terraform: ya instalado ($(terraform version | head -n 1))"
  exit 0
fi

for dependency in curl gpg; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    die "terraform: requiere $dependency; ejecuta essentials.sh primero"
  fi
done

if [ ! -r /etc/os-release ]; then
  die "terraform: no se pudo leer /etc/os-release"
fi

# shellcheck disable=SC1091
. /etc/os-release

UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

if [ -z "$UBUNTU_CODENAME" ]; then
  die "terraform: no se pudo detectar el codename de Ubuntu"
fi

log_info "terraform: configurando repositorio oficial de HashiCorp"

sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
  --connect-timeout 10 \
  --max-time 60 \
  --retry 3 \
  --retry-delay 2 \
  --retry-connrefused \
  https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor \
  | sudo tee /etc/apt/keyrings/hashicorp-archive-keyring.gpg >/dev/null

sudo chmod a+r /etc/apt/keyrings/hashicorp-archive-keyring.gpg

echo \
  "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${UBUNTU_CODENAME} main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

log_info "terraform: instalando"

pkg_update
pkg_install terraform

if ! command -v terraform >/dev/null 2>&1; then
  die "terraform: no quedó accesible tras la instalación"
fi

log_info "terraform: listo ($(terraform version | head -n 1))"
