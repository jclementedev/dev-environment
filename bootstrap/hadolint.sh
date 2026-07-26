#!/bin/bash
# Instala o actualiza Hadolint, linter para Dockerfiles.
# Descarga el binario oficial de la última versión publicada en GitHub Releases.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/version.sh
. "$SCRIPT_DIR/lib/version.sh"

readonly HADOLINT_INSTALL_DIR="$HOME/.local/bin"
readonly HADOLINT_TARGET="$HADOLINT_INSTALL_DIR/hadolint"

case ":$PATH:" in
  *":$HADOLINT_INSTALL_DIR:"*) ;;
  *) export PATH="$HADOLINT_INSTALL_DIR:$PATH" ;;
esac

get_installed_version_hadolint()
{
  local output

  if ! command -v hadolint >/dev/null 2>&1; then
    return 0
  fi

  output="$(hadolint --version 2>/dev/null || true)"

  printf '%s\n' "$output" \
    | grep -Eo 'v?[0-9]+(\.[0-9]+){1,3}' \
    | head -n 1 \
    || true
}

# download_hadolint_binary <target_version>
# Detecta arquitectura, descarga el binario, asigna permisos y valida la versión.
# Devuelve la ruta del archivo temporal en stdout.
download_hadolint_binary()
{
  local target_version="$1"
  local architecture
  local asset_name
  local asset_url
  local temp_file

  if ! command -v curl >/dev/null 2>&1; then
    log_error "hadolint: curl no está disponible"
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_error "hadolint: jq no está disponible"
    return 1
  fi

  if ! mkdir -p "$HADOLINT_INSTALL_DIR"; then
    log_error "hadolint: no se pudo crear $HADOLINT_INSTALL_DIR"
    return 1
  fi

  architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"

  case "$architecture" in
    amd64 | x86_64)
      asset_name="hadolint-linux-x86_64"
      ;;
    arm64 | aarch64)
      asset_name="hadolint-linux-arm64"
      ;;
    *)
      log_error "hadolint: arquitectura '$architecture' no soportada"
      return 1
      ;;
  esac

  asset_url="https://github.com/hadolint/hadolint/releases/latest/download/${asset_name}"

  if ! temp_file="$(
    mktemp "$HADOLINT_INSTALL_DIR/.hadolint.XXXXXX"
  )"; then
    log_error "hadolint: no se pudo crear el archivo temporal"
    return 1
  fi

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      "$asset_url" \
      -o "$temp_file"; then
    rm -f "$temp_file"
    log_error "hadolint: descarga falló"
    return 1
  fi

  if ! chmod 0755 "$temp_file"; then
    rm -f "$temp_file"
    log_error "hadolint: no se pudieron asignar permisos al binario"
    return 1
  fi

  downloaded_version="$("$temp_file" --version 2>/dev/null | grep -Eo 'v?[0-9]+(\.[0-9]+){1,3}' | head -n 1 || true)"

  if [ -z "$downloaded_version" ]; then
    rm -f "$temp_file"
    log_error "hadolint: no se pudo obtener la versión del binario"
    return 1
  fi

  if ! version_equals "$(normalize_version "$downloaded_version")" "$target_version"; then
    rm -f "$temp_file"
    log_error "hadolint: versión del binario no coincide con la objetivo"
    return 1
  fi

  printf '%s\n' "$temp_file"
}

install_hadolint()
{
  local installed_version
  local target_version
  local temp_file

  if [ -x "$HADOLINT_TARGET" ]; then
    installed_version="$("$HADOLINT_TARGET" --version 2>/dev/null || true)"

    if [ -n "$installed_version" ]; then
      log_info "hadolint: ya instalado ($installed_version)"
      return 0
    fi

    log_info "hadolint: instalación existente no válida; se reinstalará"
  fi

  if ! target_version="$(
    curl -fsSL https://api.github.com/repos/hadolint/hadolint/releases/latest |
      jq -er '.tag_name | select(type == "string" and length > 0)'
  )"; then
    die "hadolint: no se pudo obtener la última versión"
  fi

  if ! temp_file="$(download_hadolint_binary "$target_version")"; then
    return 1
  fi

  if ! mv -- "$temp_file" "$HADOLINT_TARGET"; then
    rm -f "$temp_file"
    log_error "hadolint: no se pudo reemplazar el binario"
    return 1
  fi

  log_info "hadolint: instalado $target_version"
}

update_hadolint()
{
  local installed_version
  local target_version
  local temp_file

  installed_version="$(normalize_version "$(get_installed_version_hadolint)")"

  if ! target_version="$(
    curl -fsSL https://api.github.com/repos/hadolint/hadolint/releases/latest |
      jq -er '.tag_name | select(type == "string" and length > 0)'
  )"; then
    log_error "hadolint: no se pudo obtener la última versión"
    return 1
  fi

  if version_equals "$installed_version" "$target_version"; then
    log_info "hadolint: ya está actualizado ($installed_version)"
    return 0
  fi

  if ! temp_file="$(download_hadolint_binary "$target_version")"; then
    return 1
  fi

  if ! mv -- "$temp_file" "$HADOLINT_TARGET"; then
    rm -f "$temp_file"
    log_error "hadolint: no se pudo reemplazar el binario"
    return 1
  fi

  log_info "hadolint: actualizado $installed_version → $target_version"
}

main()
{
  case "${1:-install}" in
    install)
      install_hadolint
      ;;
    update)
      update_hadolint
      ;;
    *)
      log_error "hadolint: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
