#!/bin/bash
# Instala Docker Engine, Docker CLI, Buildx y Docker Compose.
# Configura el repositorio oficial de Docker para Ubuntu.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/pkg-manager.sh
. "$SCRIPT_DIR/lib/pkg-manager.sh"

docker_is_ready()
{
  command -v docker >/dev/null 2>&1 \
    && docker compose version >/dev/null 2>&1 \
    && docker buildx version >/dev/null 2>&1
}

if docker_is_ready; then
  log_info "docker: ya instalado"
else
  if ! command -v curl >/dev/null 2>&1; then
    die "docker: requiere curl; ejecuta essentials.sh primero"
  fi

  if [ ! -r /etc/os-release ]; then
    die "docker: no se pudo leer /etc/os-release"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

  if [ -z "$UBUNTU_CODENAME" ]; then
    die "docker: no se pudo detectar el codename de Ubuntu"
  fi

  ARCH="$(dpkg --print-architecture)"

  log_info "docker: configurando repositorio oficial"

  sudo install -m 0755 -d /etc/apt/keyrings

  sudo curl -fsSL \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

  sudo chmod a+r /etc/apt/keyrings/docker.asc

  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $UBUNTU_CODENAME
Components: stable
Architectures: $ARCH
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  log_info "docker: instalando paquetes"

  pkg_update

  pkg_install \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
fi

if ! getent group docker >/dev/null 2>&1; then
  die "docker: el grupo docker no fue creado durante la instalación"
fi

CURRENT_USER="$(id -un)"

if ! id -nG "$CURRENT_USER" | grep -qw docker; then
  log_info "docker: agregando $CURRENT_USER al grupo docker"
  sudo usermod -aG docker "$CURRENT_USER"
fi

if [ "$(ps -p 1 -o comm= 2>/dev/null)" = "systemd" ]; then
  if ! sudo systemctl enable --now docker; then
    die "docker: no se pudo habilitar o iniciar el servicio"
  fi
else
  log_warn "docker: PID 1 no es systemd; el servicio no se inició. Inicia Docker manualmente o habilita systemd y vuelve a ejecutar este script"
fi

if ! docker_is_ready; then
  die "docker: la instalación quedó incompleta"
fi

log_info "docker: listo ($(docker --version))"

if ! id -nG "$CURRENT_USER" | grep -qw docker; then
  log_warn "docker: debes reiniciar la sesión para aplicar el grupo docker"
else
  log_info "docker: reinicia la sesión si el grupo fue agregado durante esta ejecución"
fi
