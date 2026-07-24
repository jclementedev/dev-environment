#!/bin/bash
# Instala utilidades de desarrollo y calidad.
# Idempotente mediante el gestor de paquetes.
#
# Criterio de diseño:
# Agrupar aquí únicamente utilidades de desarrollo relacionadas con validación,
# pruebas, formato o procesamiento de datos que puedan instalarse directamente
# mediante el gestor de paquetes y no requieran configuración adicional.
#
# Las herramientas que formen parte del entorno interactivo del usuario o que
# puedan evolucionar de manera independiente deben tener su propio script,
# aunque actualmente su instalación sea simple.
#
# Si una herramienta requiere repositorios adicionales, instaladores oficiales,
# configuración posterior o validaciones específicas, también debe tener su
# propio script de bootstrap.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

log_info "dev-tools: instalando herramientas de desarrollo"

pkg_install \
  bats \
  shellcheck \
  shfmt

for tool in bats shellcheck shfmt; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    die "dev-tools: $tool no quedó accesible tras la instalación"
  fi
done

log_info "dev-tools: listo"
