#!/bin/bash
# Operaciones de paquetes del sistema mediante APT.
#
# Los scripts bootstrap/*.sh usan pkg_install y pkg_update en lugar de
# invocar apt-get directamente.
#
# Requiere una distribución basada en APT y acceso a sudo.

if [ -n "${_BOOTSTRAP_LIB_PKG_LOADED:-}" ]; then
  return 0
fi
_BOOTSTRAP_LIB_PKG_LOADED=1

# shellcheck source=log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log.sh"

_require_apt() {
  command -v apt-get >/dev/null 2>&1 ||
    die "apt-get no está disponible"
}

# pkg_install <package> [<package>...]
pkg_install() {
  [ "$#" -gt 0 ] ||
    die "pkg_install requiere al menos un paquete"

  _require_apt
  sudo apt-get install -y "$@"
}

pkg_update() {
  _require_apt
  sudo apt-get update
}
