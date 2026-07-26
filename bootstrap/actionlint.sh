#!/bin/bash
# Instala o actualiza actionlint, linter para workflows de GitHub Actions.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/version.sh
. "$SCRIPT_DIR/lib/version.sh"

readonly ACTIONLINT_INSTALL_DIR="$HOME/.local/bin"
readonly ACTIONLINT_TARGET="$ACTIONLINT_INSTALL_DIR/actionlint"

case ":$PATH:" in
  *":$ACTIONLINT_INSTALL_DIR:"*) ;;
  *) export PATH="$ACTIONLINT_INSTALL_DIR:$PATH" ;;
esac

get_installed_version_actionlint()
{
  local output

  if ! command -v actionlint >/dev/null 2>&1; then
    return 0
  fi

  output="$(actionlint --version 2>/dev/null || true)"

  printf '%s\n' "$output" \
    | grep -Eo 'v?[0-9]+(\.[0-9]+){1,3}' \
    | head -n 1 \
    || true
}

# download_actionlint_binary <target_version>
# Descarga el tar.gz, extrae el binario, asigna permisos y valida la versión.
# Devuelve la ruta del archivo temporal en stdout.
download_actionlint_binary()
{
  local target_version="$1"
  local archive_file
  local archive_entry
  local archive_count
  local temp_file

  for dependency in curl jq tar; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
      log_error "actionlint: $dependency no está disponible"
      return 1
    fi
  done

  if ! mkdir -p "$ACTIONLINT_INSTALL_DIR"; then
    log_error "actionlint: no se pudo crear $ACTIONLINT_INSTALL_DIR"
    return 1
  fi

  if ! archive_file="$(
    mktemp "$ACTIONLINT_INSTALL_DIR/.actionlint.XXXXXX.tar.gz"
  )"; then
    log_error "actionlint: no se pudo crear el archivo temporal"
    return 1
  fi

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      "https://github.com/rhysd/actionlint/releases/download/${target_version}/actionlint_${target_version#v}_linux_amd64.tar.gz" \
      -o "$archive_file"; then
    rm -f "$archive_file"
    log_error "actionlint: descarga falló"
    return 1
  fi

  archive_entry="$(tar -tzf "$archive_file" | awk -F/ '$NF == "actionlint" { print }')"
  archive_count="$(printf '%s\n' "$archive_entry" | grep -c . || true)"

  if [ "$archive_count" -ne 1 ]; then
    rm -f "$archive_file"
    log_error "actionlint: se esperaba exactamente 1 binario; se encontraron $archive_count"
    return 1
  fi

  if ! temp_file="$(
    mktemp "$ACTIONLINT_INSTALL_DIR/.actionlint.XXXXXX"
  )"; then
    rm -f "$archive_file"
    log_error "actionlint: no se pudo crear el binario temporal"
    return 1
  fi

  if ! tar -xzf "$archive_file" -O "$archive_entry" >"$temp_file"; then
    rm -f "$archive_file" "$temp_file"
    log_error "actionlint: extracción falló"
    return 1
  fi

  rm -f "$archive_file"

  if ! chmod 0755 "$temp_file"; then
    rm -f "$temp_file"
    log_error "actionlint: no se pudieron asignar permisos al binario"
    return 1
  fi

  downloaded_version="$("$temp_file" --version 2>/dev/null | grep -Eo 'v?[0-9]+(\.[0-9]+){1,3}' | head -n 1 || true)"

  if [ -z "$downloaded_version" ]; then
    rm -f "$temp_file"
    log_error "actionlint: no se pudo obtener la versión del binario"
    return 1
  fi

  if ! version_equals "$(normalize_version "$downloaded_version")" "$target_version"; then
    rm -f "$temp_file"
    log_error "actionlint: versión del binario no coincide con la objetivo"
    return 1
  fi

  printf '%s\n' "$temp_file"
}

install_actionlint()
{
  local installed_version
  local target_version
  local temp_file

  if [ -x "$ACTIONLINT_TARGET" ]; then
    installed_version="$("$ACTIONLINT_TARGET" --version 2>/dev/null || true)"

    if [ -n "$installed_version" ]; then
      log_info "actionlint: ya instalado ($installed_version)"
      return 0
    fi

    log_info "actionlint: instalación existente no válida; se reinstalará"
  fi

  if ! target_version="$(
    curl -fsSL https://api.github.com/repos/rhysd/actionlint/releases/latest |
      jq -er '.tag_name | select(type == "string" and length > 0)'
  )"; then
    die "actionlint: no se pudo obtener la última versión"
  fi

  if ! temp_file="$(download_actionlint_binary "$target_version")"; then
    return 1
  fi

  if ! mv -- "$temp_file" "$ACTIONLINT_TARGET"; then
    rm -f "$temp_file"
    log_error "actionlint: no se pudo reemplazar el binario"
    return 1
  fi

  log_info "actionlint: instalado $target_version"
}

update_actionlint()
{
  local installed_version
  local target_version
  local temp_file

  installed_version="$(normalize_version "$(get_installed_version_actionlint)")"

  if ! target_version="$(
    curl -fsSL https://api.github.com/repos/rhysd/actionlint/releases/latest |
      jq -er '.tag_name | select(type == "string" and length > 0)'
  )"; then
    log_error "actionlint: no se pudo obtener la última versión"
    return 1
  fi

  if version_equals "$installed_version" "$target_version"; then
    log_info "actionlint: ya está actualizado ($installed_version)"
    return 0
  fi

  if ! temp_file="$(download_actionlint_binary "$target_version")"; then
    return 1
  fi

  if ! mv -- "$temp_file" "$ACTIONLINT_TARGET"; then
    rm -f "$temp_file"
    log_error "actionlint: no se pudo reemplazar el binario"
    return 1
  fi

  log_info "actionlint: actualizado $installed_version → $target_version"
}

main()
{
  case "${1:-install}" in
    install)
      install_actionlint
      ;;
    update)
      update_actionlint
      ;;
    *)
      log_error "actionlint: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
