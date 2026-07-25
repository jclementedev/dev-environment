#!/bin/bash
# Instala Herdr, multiplexor para supervisar agentes IA en paneles.
# Usa el instalador oficial del proveedor y sigue el canal estable.
# Instala o actualiza Herdr mediante su mecanismo oficial.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly LOCAL_BIN="$HOME/.local/bin"

case ":$PATH:" in
  *":$LOCAL_BIN:"*) ;;
  *) export PATH="$LOCAL_BIN:$PATH" ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  die "herdr: requiere curl; ejecuta essentials.sh primero"
fi

log_info "herdr: instalando la última versión estable"

if ! curl -fsSL https://herdr.dev/install.sh | sh; then
  die "herdr: el instalador oficial falló"
fi

if ! command -v herdr >/dev/null 2>&1; then
  die "herdr: el comando no quedó disponible en PATH"
fi

herdr_target="$(command -v herdr)"
installed_version="$("$herdr_target" --version 2>/dev/null || true)"

log_info "herdr: listo (${installed_version:-versión desconocida})"
