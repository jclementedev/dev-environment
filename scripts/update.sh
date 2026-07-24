#!/bin/bash
#
# update.sh — actualiza el repositorio y reaplica los dotfiles.
#
# Flujo:
#   1. valida el repositorio;
#   2. valida que no existan cambios locales;
#   3. crea un snapshot defensivo timestamped;
#   4. actualiza mediante git pull --ff-only;
#   5. aplica Chezmoi.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

readonly EXPECTED_BRANCH="main"
readonly EXPECTED_HTTPS_REMOTE="https://github.com/jclementedev/dev-environment.git"
readonly EXPECTED_SSH_REMOTE="git@github.com:jclementedev/dev-environment.git"
readonly CHEZMOI_SOURCE_DIR="$REPO_ROOT/dotfiles"

# shellcheck source=bootstrap/lib/log.sh
. "$REPO_ROOT/bootstrap/lib/log.sh"

require_command()
{
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 \
    || die "actualizando: $command_name es requerido"
}

validate_repository()
{
  local current_branch
  local remote_url

  if [ ! -d "$REPO_ROOT/.git" ]; then
    die "actualizando: $REPO_ROOT no es un repositorio Git"
  fi

  current_branch="$(
    git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true
  )"

  if [ "$current_branch" != "$EXPECTED_BRANCH" ]; then
    die \
      "actualizando: rama actual '${current_branch:-desconocida}'; se requiere '$EXPECTED_BRANCH'"
  fi

  remote_url="$(
    git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true
  )"

  case "$remote_url" in
    "$EXPECTED_HTTPS_REMOTE" | "$EXPECTED_SSH_REMOTE")
      ;;

    *)
      die \
        "actualizando: origin no apunta al repositorio esperado: ${remote_url:-no configurado}"
      ;;
  esac
}

validate_clean_worktree()
{
  local status

  status="$(
    git -C "$REPO_ROOT" status --porcelain
  )"

  if [ -n "$status" ]; then
    die \
      "actualizando: existen cambios locales; haz commit, stash o descártalos antes de actualizar"
  fi
}

create_defensive_snapshot()
{
  local backup_script="$SCRIPT_DIR/backup.sh"
  local snapshot

  if [ ! -f "$backup_script" ]; then
    die "actualizando: no se encontró $backup_script"
  fi

  log_info "actualizando: creando snapshot defensivo"

  # Sin --name: cada actualización debe generar un snapshot nuevo
  # para conservar un punto de rollback correspondiente a esa ejecución.
  snapshot="$(
    bash "$backup_script"
  )" || die "actualizando: no se pudo crear el snapshot defensivo"

  if [ -z "$snapshot" ]; then
    die "actualizando: backup.sh devolvió una ruta vacía"
  fi

  if [ ! -d "$snapshot" ]; then
    die "actualizando: el snapshot no existe: $snapshot"
  fi

  if [ ! -r "$snapshot" ]; then
    die "actualizando: el snapshot no es legible: $snapshot"
  fi

  log_info "actualizando: snapshot creado en $snapshot"
}

update_repository()
{
  log_info "actualizando: obteniendo cambios mediante git pull --ff-only"

  if ! git -C "$REPO_ROOT" pull --ff-only; then
    die \
      "actualizando: git pull --ff-only falló; revisa conectividad o divergencias manualmente"
  fi
}

apply_dotfiles()
{
  require_command chezmoi

  if [ ! -d "$CHEZMOI_SOURCE_DIR" ]; then
    die \
      "actualizando: no se encontró la fuente de Chezmoi: $CHEZMOI_SOURCE_DIR"
  fi

  log_info "actualizando: aplicando dotfiles con Chezmoi"

  if ! chezmoi apply --source "$CHEZMOI_SOURCE_DIR"; then
    die "actualizando: chezmoi apply falló"
  fi
}

main()
{
  require_command git

  validate_repository
  validate_clean_worktree
  create_defensive_snapshot
  update_repository
  apply_dotfiles

  log_info "actualizando: proceso finalizado correctamente"
}

main "$@"
