#!/bin/bash
# Instala o actualiza Checkov, linter de seguridad para infraestructura como código.
# Usa pipx para mantener un entorno aislado.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly CHECKOV_INSTALL_DIR="$HOME/.local/bin"
readonly CHECKOV_TARGET="$CHECKOV_INSTALL_DIR/checkov"

export PIPX_BIN_DIR="$CHECKOV_INSTALL_DIR"

case ":$PATH:" in
  *":$CHECKOV_INSTALL_DIR:"*) ;;
  *) export PATH="$CHECKOV_INSTALL_DIR:$PATH" ;;
esac

require_pipx()
{
  command -v pipx >/dev/null 2>&1 \
    || die "checkov: requiere pipx; ejecuta bootstrap/python.sh primero"
}

install_checkov()
{
  local installed_version

  require_pipx

  log_info "checkov: instalando o actualizando la última versión estable vía pipx"

  if ! pipx install checkov; then
    die "checkov: la instalación o actualización mediante pipx falló"
  fi

  if [ ! -x "$CHECKOV_TARGET" ]; then
    die "checkov: el ejecutable no quedó instalado en $CHECKOV_INSTALL_DIR"
  fi

  installed_version="$("$CHECKOV_TARGET" --version 2>/dev/null || true)"

  log_info "checkov: listo (${installed_version:-versión desconocida})"
}

update_checkov()
{
  local installed_version

  require_pipx

  log_info "checkov: actualizando la última versión estable vía pipx"

  if ! pipx upgrade checkov; then
    log_error "checkov: la actualización mediante pipx falló"
    return 1
  fi

  installed_version="$("$CHECKOV_TARGET" --version 2>/dev/null || true)"

  log_info "checkov: listo (${installed_version:-versión desconocida})"
}

main()
{
  case "${1:-install}" in
    install)
      install_checkov
      ;;
    update)
      update_checkov
      ;;
    *)
      log_error "checkov: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
