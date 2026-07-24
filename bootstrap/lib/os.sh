#!/bin/bash
# Detección de OS/distro y validación de plataforma soportada.

if [ -n "${_BOOTSTRAP_LIB_OS_LOADED:-}" ]; then
  return 0
fi
_BOOTSTRAP_LIB_OS_LOADED=1

# shellcheck source=log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log.sh"

_supported_ubuntu_versions() {
  printf '%s\n' "24.04 26.04"
}

# Valida que la plataforma sea una versión soportada de Ubuntu.
# Retorna 0 si es válida; termina el proceso mediante die() si no lo es.
validate_supported_platform() {
  local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
  local id="unknown"
  local version_id="unknown"
  local supported_versions
  local version

  if [ -r "$os_release_file" ]; then
    # shellcheck disable=SC1090
    . "$os_release_file"

    id="${ID:-unknown}"
    version_id="${VERSION_ID:-unknown}"
  fi

  if [ "$id" != "ubuntu" ]; then
    die "Plataforma no soportada: se requiere Ubuntu (detectado: ID=$id)."
  fi

  supported_versions="$(_supported_ubuntu_versions)"

  for version in $supported_versions; do
    if [ "$version_id" = "$version" ]; then
      return 0
    fi
  done

  die "Plataforma no soportada: Ubuntu $version_id no está entre las versiones soportadas ($supported_versions)."
}