#!/bin/bash
# Instala los paquetes esenciales del sistema.
# Idempotente mediante el gestor de paquetes.
#
# Criterio de diseño:
# Este script contiene únicamente las dependencias base sobre las que se apoya
# el bootstrap (por ejemplo, herramientas para descargar, verificar, extraer o
# compilar software). No debe incluir herramientas de desarrollo ni paquetes
# que requieran configuración específica.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

log_info "essentials: instalando paquetes base"

pkg_install \
  build-essential \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  unzip \
  xz-utils

for tool in curl git jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    die "essentials: $tool no quedó accesible tras la instalación"
  fi
done

log_info "essentials: listo"
