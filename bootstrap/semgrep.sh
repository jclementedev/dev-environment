#!/bin/bash
# Instala o actualiza Semgrep, analizador estático multilenguaje.
# Usa pipx para mantener un entorno aislado.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly SEMGREP_INSTALL_DIR="$HOME/.local/bin"
readonly SEMGREP_TARGET="$SEMGREP_INSTALL_DIR/semgrep"

export PIPX_BIN_DIR="$SEMGREP_INSTALL_DIR"

case ":$PATH:" in
  *":$SEMGREP_INSTALL_DIR:"*) ;;
  *) export PATH="$SEMGREP_INSTALL_DIR:$PATH" ;;
esac

require_pipx()
{
  command -v pipx >/dev/null 2>&1 \
    || die "semgrep: requiere pipx; ejecuta bootstrap/python.sh primero"
}

install_semgrep()
{
  local installed_version

  require_pipx

  log_info "semgrep: instalando o actualizando la última versión estable vía pipx"

  if ! pipx install --upgrade semgrep; then
    die "semgrep: la instalación o actualización mediante pipx falló"
  fi

  if [ ! -x "$SEMGREP_TARGET" ]; then
    die "semgrep: el ejecutable no quedó instalado en $SEMGREP_INSTALL_DIR"
  fi

  installed_version="$("$SEMGREP_TARGET" --version 2>/dev/null || true)"

  log_info "semgrep: listo (${installed_version:-versión desconocida})"
}

update_semgrep()
{
  local installed_version

  require_pipx

  log_info "semgrep: actualizando la última versión estable vía pipx"

  if ! pipx upgrade --install semgrep; then
    log_error "semgrep: la actualización mediante pipx falló"
    return 1
  fi

  installed_version="$("$SEMGREP_TARGET" --version 2>/dev/null || true)"

  log_info "semgrep: listo (${installed_version:-versión desconocida})"
}

main()
{
  case "${1:-install}" in
    install)
      install_semgrep
      ;;
    update)
      update_semgrep
      ;;
    *)
      log_error "semgrep: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
