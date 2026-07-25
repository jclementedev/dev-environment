#!/bin/bash
# Instala Markdownlint, linter para archivos Markdown.
# Usa el paquete npm oficial en su última versión estable.
# Idempotente: instala o actualiza Markdownlint cuando se vuelve a ejecutar.
# --ignore-scripts evita ejecutar scripts de ciclo de vida de dependencias.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly MARKDOWNLINT_PREFIX="$HOME/.local"
readonly MARKDOWNLINT_INSTALL_DIR="$MARKDOWNLINT_PREFIX/bin"
readonly MARKDOWNLINT_TARGET="$MARKDOWNLINT_INSTALL_DIR/markdownlint"

case ":$PATH:" in
  *":$MARKDOWNLINT_INSTALL_DIR:"*) ;;
  *) export PATH="$MARKDOWNLINT_INSTALL_DIR:$PATH" ;;
esac

if ! command -v npm >/dev/null 2>&1; then
  die "markdownlint: requiere npm; ejecuta bootstrap/node.sh primero"
fi

log_info "markdownlint: instalando o actualizando la última versión estable vía npm"

if ! npm install \
  --global \
  --prefix "$MARKDOWNLINT_PREFIX" \
  --ignore-scripts \
  markdownlint-cli@latest; then
  die "markdownlint: la instalación mediante npm falló"
fi

if [ ! -x "$MARKDOWNLINT_TARGET" ]; then
  die "markdownlint: el ejecutable no quedó instalado en $MARKDOWNLINT_INSTALL_DIR"
fi

installed_version="$("$MARKDOWNLINT_TARGET" --version 2>/dev/null || true)"

log_info "markdownlint: listo (${installed_version:-versión desconocida})"
