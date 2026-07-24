#!/bin/bash
# Instala semgrep, analizador estático multilenguaje.
# Se instala desde PyPI mediante pipx en un entorno aislado.
# Idempotente: no reinstala si la versión esperada ya está instalada
# en el destino administrado.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly SEMGREP_VERSION="1.171.0"
readonly SEMGREP_INSTALL_DIR="$HOME/.local/bin"
readonly SEMGREP_TARGET="$SEMGREP_INSTALL_DIR/semgrep"

case ":$PATH:" in
  *":$SEMGREP_INSTALL_DIR:"*) ;;
  *) export PATH="$SEMGREP_INSTALL_DIR:$PATH" ;;
esac

installed_version=""

if [ -x "$SEMGREP_TARGET" ]; then
  installed_version="$("$SEMGREP_TARGET" --version 2>/dev/null || true)"

  if [ "$installed_version" = "v${SEMGREP_VERSION}" ] \
    || [ "$installed_version" = "$SEMGREP_VERSION" ]; then
    log_info "semgrep: versión esperada ya instalada ($installed_version)"
    exit 0
  fi

  log_info "semgrep: versión administrada '${installed_version:-desconocida}'; se instalará v${SEMGREP_VERSION}"
fi

for dependency in pipx python3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    die "semgrep: requiere $dependency; ejecuta bootstrap/python.sh primero"
  fi
done

python_version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
python_major="${python_version%%.*}"
python_minor="${python_version#*.}"

if [ "$python_major" -lt 3 ] \
  || { [ "$python_major" -eq 3 ] && [ "$python_minor" -lt 10 ]; }; then
  die "semgrep: requiere Python 3.10 o superior; versión encontrada: $python_version"
fi

log_info "semgrep: instalando v${SEMGREP_VERSION} vía pipx"

if ! pipx install --force "semgrep==${SEMGREP_VERSION}"; then
  die "semgrep: pipx install falló"
fi

if [ ! -x "$SEMGREP_TARGET" ]; then
  die "semgrep: el binario no quedó accesible tras la instalación"
fi

installed_version="$("$SEMGREP_TARGET" --version 2>/dev/null || true)"

if [ "$installed_version" != "v${SEMGREP_VERSION}" ] \
  && [ "$installed_version" != "$SEMGREP_VERSION" ]; then
  die "semgrep: versión instalada inesperada: '${installed_version:-desconocida}'"
fi

log_info "semgrep: listo ($installed_version)"