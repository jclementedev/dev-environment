#!/bin/bash
# Instala los SDK de .NET 8 y .NET 10.
# Prioriza el feed integrado de Ubuntu y usa dotnet/backports cuando es necesario.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

DOTNET_VERSIONS=(
  "8.0"
  "10.0"
)

dotnet_has_sdk()
{
  local version="$1"

  command -v dotnet >/dev/null 2>&1 \
    && dotnet --list-sdks 2>/dev/null \
      | grep -qE "^${version//./\\.}\."
}

missing_packages()
{
  local version

  for version in "${DOTNET_VERSIONS[@]}"; do
    if ! dotnet_has_sdk "$version"; then
      printf 'dotnet-sdk-%s\n' "$version"
    fi
  done
}

if missing=($(missing_packages)) && [ "${#missing[@]}" -eq 0 ]; then
  log_info "dotnet: ya instalado (SDKs: ${DOTNET_VERSIONS[*]})"
  exit 0
fi

log_info "dotnet: instalando SDKs desde el feed de Ubuntu"

pkg_update

if ! pkg_install "${missing[@]}"; then
  log_warn "dotnet: algunas versiones no están disponibles en el feed integrado"
fi

mapfile -t missing < <(missing_packages)

if [ "${#missing[@]}" -gt 0 ]; then
  log_info "dotnet: habilitando Ubuntu .NET Backports"

  if ! command -v add-apt-repository >/dev/null 2>&1; then
    pkg_install software-properties-common
  fi

  if ! grep -RqsE \
    '(^|[[:space:]])ppa\.launchpadcontent\.net/dotnet/backports|dotnet/backports' \
    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    sudo add-apt-repository -y ppa:dotnet/backports
  else
    log_info "dotnet: Ubuntu .NET Backports ya configurado"
  fi

  pkg_update
  pkg_install "${missing[@]}"
fi

for version in "${DOTNET_VERSIONS[@]}"; do
  if ! dotnet_has_sdk "$version"; then
    die "dotnet: SDK ${version}.x no quedó accesible tras la instalación"
  fi
done

installed_versions="$(
  dotnet --list-sdks \
    | awk '{print $1}' \
    | sort -V \
    | tr '\n' ' '
)"

log_info "dotnet: listo (SDKs: ${installed_versions% })"