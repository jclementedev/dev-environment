#!/bin/bash
#
# bootstrap.sh — obtiene o actualiza el repositorio y delega en install.sh.
#
# Uso:
#   curl -fsSL \
#     https://raw.githubusercontent.com/jclementedev/dev-environment/main/bootstrap.sh \
#     | bash
#
# También puede ejecutarse desde una copia existente:
#   bash bootstrap.sh
#

set -Eeuo pipefail

readonly REPO_URL="https://github.com/jclementedev/dev-environment.git"
readonly REPO_SSH_URL="git@github.com:jclementedev/dev-environment.git"
readonly CLONE_TARGET="${DEV_ENVIRONMENT_HOME:-$HOME/dev-environment}"
readonly EXPECTED_BRANCH="main"

bootstrap_log_info()
{
  printf '[INFO] %s\n' "$*" >&2
}

bootstrap_die()
{
  local exit_code="$1"
  shift

  # Evita que la salida explícita mediante bootstrap_die active también
  # un mensaje genérico del trap ERR.
  trap - ERR

  printf '[ERROR] %s\n' "$*" >&2
  exit "$exit_code"
}

on_error()
{
  local exit_code=$?
  local line_number="$1"
  local command="$2"

  trap - ERR

  printf '[ERROR] bootstrap falló en la línea %s: %s\n' \
    "$line_number" "$command" >&2

  exit "$exit_code"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

check_prerequisites()
{
  local command_name

  for command_name in bash git; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      bootstrap_die \
        2 \
        "$command_name es requerido, pero no está instalado"
    fi
  done
}

validate_ubuntu()
{
  local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
  local id="unknown"
  local version_id="unknown"

  if [ -r "$os_release_file" ]; then
    # shellcheck disable=SC1090
    . "$os_release_file"
    id="${ID:-unknown}"
    version_id="${VERSION_ID:-unknown}"
  fi

  if [ "$id" != "ubuntu" ]; then
    bootstrap_die 1 "plataforma no soportada: se requiere Ubuntu (detectado: ID=$id)"
  fi

  # Debe mantenerse autosuficiente: el repositorio aún no fue obtenido.
  case "$version_id" in
    24.04 | 26.04)
      ;;
    *)
      bootstrap_die \
        1 \
        "plataforma no soportada: Ubuntu $version_id no está entre las versiones soportadas (24.04 26.04)"
      ;;
  esac
}

normalize_repository_url()
{
  local url="$1"

  case "$url" in
    "$REPO_URL" | "$REPO_SSH_URL")
      printf '%s\n' "$REPO_URL"
      ;;

    *)
      printf '%s\n' "$url"
      ;;
  esac
}

repository_origin()
{
  local repository="$1"

  git -C "$repository" remote get-url origin 2>/dev/null || true
}

repository_branch()
{
  local repository="$1"

  git -C "$repository" branch --show-current 2>/dev/null || true
}

repository_status()
{
  local repository="$1"

  git -C "$repository" status --porcelain 2>/dev/null || true
}

validate_repository()
{
  local repository="$1"
  local origin
  local branch

  if [ ! -d "$repository/.git" ]; then
    bootstrap_die \
      1 \
      "$repository existe, pero no es un repositorio Git"
  fi

  origin="$(repository_origin "$repository")"

  if [ "$(normalize_repository_url "$origin")" != "$REPO_URL" ]; then
    bootstrap_die \
      1 \
      "origin inesperado en $repository: ${origin:-no configurado}"
  fi

  branch="$(repository_branch "$repository")"

  if [ "$branch" != "$EXPECTED_BRANCH" ]; then
    bootstrap_die \
      1 \
      "el repositorio debe estar en $EXPECTED_BRANCH; rama actual: ${branch:-desconocida}"
  fi
}

validate_clean_worktree()
{
  local repository="$1"
  local status

  status="$(repository_status "$repository")"

  if [ -n "$status" ]; then
    bootstrap_die \
      1 \
      "existen cambios locales en $repository; haz commit, stash o descártalos antes de continuar"
  fi
}

find_current_repository()
{
  local repository
  local origin

  repository="$(
    git rev-parse --show-toplevel 2>/dev/null
  )" || return 1

  origin="$(repository_origin "$repository")"

  if [ "$(normalize_repository_url "$origin")" != "$REPO_URL" ]; then
    return 1
  fi

  printf '%s\n' "$repository"
}

update_repository()
{
  local repository="$1"

  validate_clean_worktree "$repository"

  bootstrap_log_info "actualizando repositorio en $repository"

  if ! git -C "$repository" pull --ff-only >&2; then
    bootstrap_die \
      1 \
      "no se pudo actualizar $repository mediante fast-forward"
  fi
}

clone_repository()
{
  local repository="$1"
  local parent_directory

  parent_directory="$(dirname "$repository")"
  mkdir -p "$parent_directory"

  bootstrap_log_info "clonando repositorio en $repository"

  if ! git clone \
    --branch "$EXPECTED_BRANCH" \
    --single-branch \
    "$REPO_URL" \
    "$repository" >&2; then
    bootstrap_die 1 "no se pudo clonar el repositorio"
  fi
}

prepare_repository()
{
  local repository

  if repository="$(find_current_repository)"; then
    validate_repository "$repository"

    bootstrap_log_info \
      "repositorio actual detectado en $repository"

    update_repository "$repository"

    printf '%s\n' "$repository"
    return 0
  fi

  if [ -e "$CLONE_TARGET" ]; then
    validate_repository "$CLONE_TARGET"
    update_repository "$CLONE_TARGET"

    printf '%s\n' "$CLONE_TARGET"
    return 0
  fi

  clone_repository "$CLONE_TARGET"
  validate_repository "$CLONE_TARGET"

  printf '%s\n' "$CLONE_TARGET"
}

load_project_libraries()
{
  local repository="$1"
  local log_library="$repository/bootstrap/lib/log.sh"
  local os_library="$repository/bootstrap/lib/os.sh"

  if [ ! -f "$log_library" ]; then
    bootstrap_die 1 "no se encontró $log_library"
  fi

  if [ ! -f "$os_library" ]; then
    bootstrap_die 1 "no se encontró $os_library"
  fi

  # shellcheck source=bootstrap/lib/log.sh
  . "$log_library"

  # shellcheck source=bootstrap/lib/os.sh
  . "$os_library"
}

run_install()
{
  local repository="$1"
  shift

  local installer="$repository/install.sh"

  if [ ! -f "$installer" ]; then
    die "no se encontró el instalador: $installer"
  fi

  log_info "bootstrap: entregando control a install.sh"

  cd "$repository"
  exec bash "$installer" "$@"
}

main()
{
  local repository

  bootstrap_log_info "bootstrap iniciado"

  # La validación debe ocurrir antes de clonar o actualizar el repositorio,
  # porque el bootstrap remoto todavía no puede usar librerías del proyecto.
  validate_ubuntu
  check_prerequisites

  # Los mensajes del bootstrap se envían a stderr para que stdout contenga
  # exclusivamente la ruta retornada por prepare_repository.
  repository="$(prepare_repository)"

  load_project_libraries "$repository"

  log_info "bootstrap: repositorio preparado en $repository"

  validate_supported_platform \
    || die "plataforma no soportada"

  run_install "$repository" "$@"
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
