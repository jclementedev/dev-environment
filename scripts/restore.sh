#!/bin/bash
#
# restore.sh — restaura en HOME un snapshot creado por backup.sh.
#
# Flujo:
#   1. valida el snapshot solicitado;
#   2. crea un snapshot defensivo del estado actual;
#   3. restaura los archivos conservando sus atributos;
#   4. informa cómo revertir la restauración.
#
# Uso:
#   restore.sh <snapshot>
#
# El snapshot puede indicarse como:
#   - nombre relativo dentro del directorio de backups;
#   - ruta absoluta dentro del directorio de backups.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=bootstrap/lib/log.sh
. "$REPO_ROOT/bootstrap/lib/log.sh"

readonly STATE_DIR="${DEV_ENV_STATE_DIR:-$HOME/.local/state/dev-env-bootstrap}"
readonly BACKUP_ROOT="$STATE_DIR/backups"

SNAPSHOT_ARGUMENT=""
CANONICAL_HOME=""

usage()
{
  cat <<EOF
Uso:
  restore.sh <snapshot>

Argumentos:
  <snapshot>
      Nombre de un snapshot existente dentro de:

        $BACKUP_ROOT

      También puede proporcionarse su ruta absoluta.

Ejemplos:
  bash scripts/restore.sh 20260722-164510.A3x9Ld
  bash scripts/restore.sh "$BACKUP_ROOT/pre-chezmoi"

Ver snapshots disponibles:
  bash scripts/backup.sh --list
EOF
}

parse_arguments()
{
  if [ "$#" -eq 0 ]; then
    usage
    exit 1
  fi

  case "$1" in
    --help | -h)
      usage
      exit 0
      ;;

    -*)
      die "restore: opción desconocida: $1"
      ;;
  esac

  if [ "$#" -ne 1 ]; then
    die "restore: se requiere exactamente un snapshot"
  fi

  SNAPSHOT_ARGUMENT="$1"
}

require_command()
{
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 \
    || die "restore: $command_name es requerido"
}

resolve_snapshot()
{
  local requested="$1"
  local candidate
  local canonical_root
  local canonical_snapshot

  if [ -d "$requested" ]; then
    candidate="$requested"
  elif [ -d "$BACKUP_ROOT/$requested" ]; then
    candidate="$BACKUP_ROOT/$requested"
  else
    die \
      "restore: '$requested' no existe ni como ruta ni dentro de $BACKUP_ROOT"
  fi

  canonical_root="$(
    realpath "$BACKUP_ROOT"
  )" || die "restore: no se pudo resolver $BACKUP_ROOT"

  canonical_snapshot="$(
    realpath "$candidate"
  )" || die "restore: no se pudo resolver $candidate"

  case "$canonical_snapshot" in
    "$canonical_root"/*)
      ;;

    *)
      die \
        "restore: el snapshot debe permanecer dentro de $BACKUP_ROOT"
      ;;
  esac

  if [ ! -d "$canonical_snapshot/.complete" ] ||
     [ -L "$canonical_snapshot/.complete" ]; then
    die "restore: el snapshot no fue completado por backup.sh: $canonical_snapshot"
  fi

  printf '%s\n' "$canonical_snapshot"
}

validate_relative_path()
{
  local relative_path="$1"
  local component
  local old_ifs="$IFS"

  if [ -z "$relative_path" ]; then
    return 1
  fi

  case "$relative_path" in
    /*)
      return 1
      ;;
  esac

  IFS='/'

  for component in $relative_path; do
    case "$component" in
      "" | . | ..)
        IFS="$old_ifs"
        return 1
        ;;
    esac
  done

  IFS="$old_ifs"
  return 0
}

validate_destination()
{
  local destination="$1"
  local parent_directory
  local relative_parent
  local current_path
  local component
  local canonical_parent
  local canonical_link
  local -a parent_components=()

  parent_directory="$(dirname "$destination")"

  if [ "$parent_directory" = "$CANONICAL_HOME" ]; then
    relative_parent=""
  else
    relative_parent="${parent_directory#"$CANONICAL_HOME"/}"
  fi

  current_path="$CANONICAL_HOME"

  # Check existing path components before mkdir -p can traverse a link.
  if [ -n "$relative_parent" ]; then
    IFS='/' read -r -a parent_components <<< "$relative_parent"

    for component in "${parent_components[@]}"; do
      current_path="$current_path/$component"

      if [ -L "$current_path" ]; then
        canonical_link="$(
          realpath "$current_path"
        )" || return 1

        case "$canonical_link" in
          "$CANONICAL_HOME" | "$CANONICAL_HOME"/*)
            current_path="$canonical_link"
            ;;

          *)
            return 1
            ;;
        esac
      fi
    done
  fi

  mkdir -p "$parent_directory" || return 1

  canonical_parent="$(
    realpath "$parent_directory"
  )" || return 1

  case "$canonical_parent" in
    "$CANONICAL_HOME" | "$CANONICAL_HOME"/*)
      ;;

    *)
      return 1
      ;;
  esac

  if [ -L "$destination" ]; then
    canonical_link="$(
      realpath "$destination"
    )" || return 1

    case "$canonical_link" in
      "$CANONICAL_HOME" | "$CANONICAL_HOME"/*)
        ;;

      *)
        return 1
        ;;
    esac
  fi

  return 0
}

validate_source_symlink()
{
  local source_path="$1"
  local snapshot="$2"
  local canonical_target

  canonical_target="$(
    realpath "$source_path"
  )" || return 1

  case "$canonical_target" in
    "$snapshot" | "$snapshot"/*)
      return 0
      ;;

    *)
      return 1
      ;;
  esac
}

create_defensive_snapshot()
{
  local backup_script="$SCRIPT_DIR/backup.sh"
  local snapshot

  if [ ! -f "$backup_script" ]; then
    die "restore: no se encontró $backup_script"
  fi

  log_info "restore: creando snapshot defensivo del estado actual"

  snapshot="$(
    bash "$backup_script"
  )" || die "restore: no se pudo crear el snapshot defensivo"

  if [ -z "$snapshot" ]; then
    die "restore: backup.sh devolvió una ruta vacía"
  fi

  if [ ! -d "$snapshot" ] || [ ! -r "$snapshot" ]; then
    die "restore: snapshot defensivo no utilizable: $snapshot"
  fi

  printf '%s\n' "$snapshot"
}

should_inject_failure()
{
  local relative_path="$1"

  if [ -z "${BOOTSTRAP_TEST_FAIL:-}" ]; then
    return 1
  fi

  case "$BOOTSTRAP_TEST_FAIL" in
    *"$relative_path"*)
      return 0
      ;;

    *)
      return 1
      ;;
  esac
}

restore_snapshot()
{
  local snapshot="$1"
  local source_path
  local relative_path
  local destination
  local count=0
  local total=0

  local -a failed_files=()
  local -a skipped_files=()

  while IFS= read -r -d '' source_path; do
    total=$((total + 1))
    relative_path="${source_path#"$snapshot"/}"

    if ! validate_relative_path "$relative_path"; then
      log_warn \
        "restore: omitiendo ruta sospechosa: $relative_path"

      skipped_files+=("$relative_path")
      continue
    fi

    if [ -L "$source_path" ] &&
       ! validate_source_symlink "$source_path" "$snapshot"; then
      log_warn \
        "restore: '$relative_path' referencia fuera del snapshot; omitido"

      skipped_files+=("$relative_path")
      continue
    fi

    destination="$CANONICAL_HOME/$relative_path"

    if ! validate_destination "$destination"; then
      log_warn \
        "restore: '$relative_path' escaparía de HOME; omitido"

      skipped_files+=("$relative_path")
      continue
    fi

    if should_inject_failure "$relative_path"; then
      log_warn \
        "  ! falló restaurando $relative_path (test inyectado)"

      failed_files+=("$relative_path")
      continue
    fi

    if cp -a -- "$source_path" "$destination"; then
      log_info "  + $relative_path"
      count=$((count + 1))
    else
      log_warn "  ! falló restaurando $relative_path"
      failed_files+=("$relative_path")
    fi
  done < <(
    find "$snapshot" \
      -mindepth 1 \
      \( -type f -o -type l \) \
      -print0
  )

  log_info "restore: $count de $total elementos restaurados"

  if [ "${#skipped_files[@]}" -gt 0 ]; then
    log_error \
      "restore: ${#skipped_files[@]} elemento(s) fueron omitidos por seguridad"

    for relative_path in "${skipped_files[@]}"; do
      log_info "  - $relative_path"
    done
  fi

  if [ "${#failed_files[@]}" -gt 0 ]; then
    log_error \
      "restore: ${#failed_files[@]} elemento(s) no pudieron restaurarse"

    for relative_path in "${failed_files[@]}"; do
      log_info "  - $relative_path"
    done
  fi

  if [ "${#failed_files[@]}" -gt 0 ] ||
     [ "${#skipped_files[@]}" -gt 0 ]; then
    return 1
  fi
}

main()
{
  local snapshot
  local defensive_snapshot

  parse_arguments "$@"

  require_command realpath
  require_command find
  require_command cp

  CANONICAL_HOME="$(
    realpath "$HOME"
  )" || die "restore: no se pudo resolver HOME"

  if [ ! -d "$BACKUP_ROOT" ]; then
    die "restore: no existe el directorio de backups: $BACKUP_ROOT"
  fi

  snapshot="$(resolve_snapshot "$SNAPSHOT_ARGUMENT")"
  defensive_snapshot="$(create_defensive_snapshot)"

  log_info "restore: restaurando $snapshot en HOME"

  if ! restore_snapshot "$snapshot"; then
    log_error "restore: la restauración no pudo completarse"
    log_info "restore: para volver al estado anterior ejecuta:"
    log_info \
      "  bash scripts/restore.sh $(basename "$defensive_snapshot")"

    exit 1
  fi

  log_info "restore: restauración completada correctamente"
  log_info "restore: para revertir esta operación ejecuta:"
  log_info \
    "  bash scripts/restore.sh $(basename "$defensive_snapshot")"
}

main "$@"
