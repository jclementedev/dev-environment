#!/bin/bash
# Instala o actualiza AWS CLI v2 mediante el instalador oficial.
# La instalación usa los destinos predeterminados del proveedor.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

readonly AWS_INSTALLER_URL_LINUX_X86_64="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
readonly AWS_INSTALLER_URL_LINUX_AARCH64="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"

require_command()
{
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "aws: se requiere '$command_name'"
    return 1
  fi
}

require_dependencies()
{
  local command_name

  for command_name in curl unzip dpkg sudo mktemp; do
    require_command "$command_name" || return 1
  done
}

get_aws_version()
{
  if ! command -v aws >/dev/null 2>&1; then
    return 0
  fi

  aws --version 2>&1 || true
}

validate_existing_version()
{
  local installed_version="$1"

  case "$installed_version" in
    "")
      return 0
      ;;
    aws-cli/2.*)
      return 0
      ;;
    *)
      log_error \
        "aws: se encontró una versión no compatible ($installed_version); se requiere AWS CLI v2"
      return 1
      ;;
  esac
}

detect_installer_url()
{
  local architecture

  if ! architecture="$(dpkg --print-architecture)"; then
    log_error "aws: no se pudo detectar la arquitectura"
    return 1
  fi

  case "$architecture" in
    amd64)
      printf '%s\n' "$AWS_INSTALLER_URL_LINUX_X86_64"
      ;;
    arm64)
      printf '%s\n' "$AWS_INSTALLER_URL_LINUX_AARCH64"
      ;;
    *)
      log_error "aws: arquitectura '$architecture' no soportada"
      return 1
      ;;
  esac
}

download_official_installer()
{
  local installer_url="$1"
  local temp_dir="$2"
  local archive_path="$temp_dir/awscliv2.zip"

  log_info "aws: descargando instalador oficial"

  if ! curl -fsSL \
      --connect-timeout 10 \
      --max-time 300 \
      --retry 3 \
      --retry-delay 2 \
      --retry-connrefused \
      "$installer_url" \
      -o "$archive_path"; then
    log_error "aws: no se pudo descargar el instalador"
    return 1
  fi

  if ! unzip -q "$archive_path" -d "$temp_dir"; then
    log_error "aws: no se pudo extraer el instalador"
    return 1
  fi

  if [ ! -x "$temp_dir/aws/install" ]; then
    log_error "aws: el instalador descargado no es válido"
    return 1
  fi
}

run_official_installer()
{
  local temp_dir="$1"
  local action="$2"
  local -a installer_args=()

  case "$action" in
    install)
      ;;
    update)
      installer_args+=(--update)
      ;;
    *)
      log_error "aws: acción interna no soportada: $action"
      return 1
      ;;
  esac

  log_info "aws: ejecutando instalador oficial"

  if ! sudo "$temp_dir/aws/install" "${installer_args[@]}"; then
    log_error "aws: el instalador oficial falló"
    return 1
  fi
}

validate_installation()
{
  local installed_version

  if ! command -v aws >/dev/null 2>&1; then
    log_error "aws: el binario no quedó accesible tras la instalación"
    return 1
  fi

  installed_version="$(get_aws_version)"

  case "$installed_version" in
    aws-cli/2.*)
      return 0
      ;;
    *)
      log_error \
        "aws: la versión instalada no corresponde a AWS CLI v2 ($installed_version)"
      return 1
      ;;
  esac
}

apply_aws_installer()
(
  local action="$1"
  local installer_url
  local temp_dir

  require_dependencies || return 1

  if ! installer_url="$(detect_installer_url)"; then
    return 1
  fi

  if ! temp_dir="$(mktemp -d)"; then
    log_error "aws: no se pudo crear el directorio temporal"
    return 1
  fi

  trap 'rm -rf -- "$temp_dir"' EXIT

  download_official_installer "$installer_url" "$temp_dir" || return 1
  run_official_installer "$temp_dir" "$action" || return 1
  validate_installation || return 1
)

install_aws()
{
  local installed_version

  installed_version="$(get_aws_version)"

  if ! validate_existing_version "$installed_version"; then
    return 1
  fi

  if [ -n "$installed_version" ]; then
    log_info "aws: ya instalado ($installed_version)"
    return 0
  fi

  apply_aws_installer install || return 1

  log_info "aws: listo ($(get_aws_version))"
  log_info "aws: configura el acceso mediante AWS IAM Identity Center o credenciales"
}

update_aws()
{
  local installed_version

  installed_version="$(get_aws_version)"

  if ! validate_existing_version "$installed_version"; then
    return 1
  fi

  if [ -z "$installed_version" ]; then
    log_info "aws: no hay instalación previa; ejecutando instalación"
    install_aws
    return
  fi

  apply_aws_installer update || return 1

  log_info "aws: actualizado ($(get_aws_version))"
}

main()
{
  case "${1:-install}" in
    install)
      install_aws
      ;;
    update)
      update_aws
      ;;
    *)
      log_error "aws: acción no soportada: $1"
      exit 2
      ;;
  esac
}

main "$@"
