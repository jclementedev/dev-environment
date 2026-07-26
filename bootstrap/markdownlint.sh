#!/bin/bash
# Instala o actualiza markdownlint-cli2, linter para archivos Markdown.
# Usa el paquete npm oficial en su última versión estable.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly MARKDOWNLINT_PREFIX="$HOME/.local"
readonly MARKDOWNLINT_INSTALL_DIR="$MARKDOWNLINT_PREFIX/bin"
readonly MARKDOWNLINT_TARGET="$MARKDOWNLINT_INSTALL_DIR/markdownlint-cli2"

case ":$PATH:" in
  *":$MARKDOWNLINT_INSTALL_DIR:"*) ;;
  *) export PATH="$MARKDOWNLINT_INSTALL_DIR:$PATH" ;;
esac

require_npm()
{
  command -v npm >/dev/null 2>&1 \
    || die "markdownlint-cli2: requiere npm; ejecuta bootstrap/node.sh primero"
}

install_markdownlint()
{
  local installed_version

  require_npm

  log_info "markdownlint-cli2: instalando o actualizando la última versión estable vía npm"

  if ! npm install \
      --global \
      --prefix "$MARKDOWNLINT_PREFIX" \
      --ignore-scripts \
      markdownlint-cli2@latest; then
    die "markdownlint-cli2: la instalación mediante npm falló"
  fi

  if [ ! -x "$MARKDOWNLINT_TARGET" ]; then
    die "markdownlint-cli2: el ejecutable no quedó instalado en $MARKDOWNLINT_INSTALL_DIR"
  fi

  installed_version="$("$MARKDOWNLINT_TARGET" --version 2>/dev/null || true)"

  log_info "markdownlint-cli2: listo (${installed_version:-versión desconocida})"
}

update_markdownlint()
{
  local installed_version

  require_npm

  log_info "markdownlint-cli2: actualizando la última versión estable vía npm"

  if ! npm install \
      --global \
      --prefix "$MARKDOWNLINT_PREFIX" \
      --ignore-scripts \
      markdownlint-cli2@latest; then
    log_error "markdownlint-cli2: la actualización mediante npm falló"
    return 1
  fi

  if [ ! -x "$MARKDOWNLINT_TARGET" ]; then
    log_error "markdownlint-cli2: el ejecutable no quedó instalado en $MARKDOWNLINT_INSTALL_DIR"
    return 1
  fi

  installed_version="$("$MARKDOWNLINT_TARGET" --version 2>/dev/null || true)"

  log_info "markdownlint-cli2: listo (${installed_version:-versión desconocida})"
}

main()
{
  case "${1:-install}" in
    install)
      install_markdownlint
      ;;
    update)
      update_markdownlint
      ;;
    *)
      log_error "markdownlint-cli2: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
