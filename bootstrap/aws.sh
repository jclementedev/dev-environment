#!/bin/bash
# Instala AWS CLI v2 mediante el instalador oficial.
# Idempotente: no reinstala si AWS CLI v2 ya está disponible.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

get_aws_version() {
  aws --version 2>&1 | head -n 1
}

if command -v aws >/dev/null 2>&1; then
  aws_version="$(get_aws_version)"

  case "$aws_version" in
    aws-cli/2.*)
      log_info "aws: ya instalado ($aws_version)"
      exit 0
      ;;
    *)
      die "aws: se encontró una versión no compatible ($aws_version); se requiere AWS CLI v2"
      ;;
  esac
fi

if ! command -v curl >/dev/null 2>&1; then
  die "aws: curl es requerido"
fi

if ! command -v unzip >/dev/null 2>&1; then
  die "aws: unzip es requerido"
fi

architecture="$(dpkg --print-architecture)"

case "$architecture" in
  amd64)
    asset_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    ;;
  arm64)
    asset_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
    ;;
  *)
    die "aws: arquitectura '$architecture' no soportada"
    ;;
esac

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

log_info "aws: descargando instalador oficial para $architecture"

if ! curl -fsSL "$asset_url" -o "$temp_dir/awscliv2.zip"; then
  die "aws: no se pudo descargar el instalador"
fi

if ! unzip -q "$temp_dir/awscliv2.zip" -d "$temp_dir"; then
  die "aws: no se pudo extraer el instalador"
fi

log_info "aws: instalando AWS CLI v2"

if ! sudo "$temp_dir/aws/install"; then
  die "aws: el instalador oficial falló"
fi

if ! command -v aws >/dev/null 2>&1; then
  die "aws: el binario no quedó accesible tras la instalación"
fi

aws_version="$(get_aws_version)"

case "$aws_version" in
  aws-cli/2.*) ;;
  *) die "aws: la versión instalada no corresponde a AWS CLI v2 ($aws_version)" ;;
esac

log_info "aws: listo ($aws_version)"
log_info "aws: configura el acceso mediante AWS IAM Identity Center o credenciales"