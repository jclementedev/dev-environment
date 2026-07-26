#!/bin/bash
# Instala o actualiza chezmoi mediante su instalador oficial.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly CHEZMOI_INSTALL_DIR="$HOME/.local/bin"

case ":$PATH:" in
  *":$CHEZMOI_INSTALL_DIR:"*) ;;
  *) export PATH="$CHEZMOI_INSTALL_DIR:$PATH" ;;
esac

install_chezmoi()
{
  local installer_file

  if command -v chezmoi >/dev/null 2>&1; then
    log_info "chezmoi: ya instalado ($(chezmoi --version))"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    die "chezmoi: requiere curl; ejecuta essentials.sh primero"
  fi

  if ! mkdir -p "$CHEZMOI_INSTALL_DIR"; then
    die "chezmoi: no se pudo crear $CHEZMOI_INSTALL_DIR"
  fi

  if ! installer_file="$(mktemp)"; then
    die "chezmoi: no se pudo crear el archivo temporal"
  fi

  trap 'rm -f "$installer_file"' EXIT

  log_info "chezmoi: descargando instalador oficial"

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      https://get.chezmoi.io \
      -o "$installer_file"; then
    die "chezmoi: no se pudo descargar el instalador oficial"
  fi

  log_info "chezmoi: instalando"

  if ! sh "$installer_file" -b "$CHEZMOI_INSTALL_DIR"; then
    die "chezmoi: el instalador oficial falló"
  fi

  if [ ! -x "$CHEZMOI_INSTALL_DIR/chezmoi" ]; then
    die "chezmoi: el ejecutable no quedó instalado en $CHEZMOI_INSTALL_DIR"
  fi

  log_info "chezmoi: listo ($("$CHEZMOI_INSTALL_DIR/chezmoi" --version))"
}

update_chezmoi()
{
  local installer_file

  if ! command -v curl >/dev/null 2>&1; then
    log_error "chezmoi: requiere curl; ejecuta essentials.sh primero"
    return 1
  fi

  if ! mkdir -p "$CHEZMOI_INSTALL_DIR"; then
    log_error "chezmoi: no se pudo crear $CHEZMOI_INSTALL_DIR"
    return 1
  fi

  if ! installer_file="$(mktemp)"; then
    log_error "chezmoi: no se pudo crear el archivo temporal"
    return 1
  fi

  trap 'rm -f "$installer_file"' EXIT

  log_info "chezmoi: actualizando mediante el instalador oficial"

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      https://get.chezmoi.io \
      -o "$installer_file"; then
    log_error "chezmoi: no se pudo descargar el instalador oficial"
    return 1
  fi

  if ! sh "$installer_file" -b "$CHEZMOI_INSTALL_DIR"; then
    log_error "chezmoi: el instalador oficial falló"
    return 1
  fi

  if [ ! -x "$CHEZMOI_INSTALL_DIR/chezmoi" ]; then
    log_error "chezmoi: el ejecutable no quedó instalado en $CHEZMOI_INSTALL_DIR"
    return 1
  fi

  log_info "chezmoi: listo ($("$CHEZMOI_INSTALL_DIR/chezmoi" --version))"
}

main()
{
  case "${1:-install}" in
    install)
      install_chezmoi
      ;;
    update)
      update_chezmoi
      ;;
    *)
      log_error "chezmoi: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
