#!/bin/bash
#
# backup.sh — crea snapshots defensivos de archivos de configuración.
#
# Uso:
#   backup.sh
#   backup.sh --name=pre-chezmoi
#   backup.sh --list
#
# Contrato:
#   - los mensajes se escriben mediante la librería de logging;
#   - al crear un snapshot, stdout devuelve únicamente su ruta;
#   - los snapshots timestamped son únicos;
#   - los snapshots con nombre fijo son idempotentes y no se sobrescriben.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=bootstrap/lib/log.sh
. "$REPO_ROOT/bootstrap/lib/log.sh"

readonly STATE_DIR="${DEV_ENV_STATE_DIR:-$HOME/.local/state/dev-env-bootstrap}"
readonly BACKUP_ROOT="$STATE_DIR/backups"
readonly SNAPSHOT_COMPLETE_MARKER=".complete"

LIST_MODE=0
NAME_OVERRIDE=""

usage()
{
  cat <<'EOF'
Uso:
  backup.sh
  backup.sh --list
  backup.sh --name=<nombre>

Opciones:
  --list
      Lista los snapshots existentes y su tamaño.

  --name=<nombre>
      Usa un nombre fijo en lugar de un timestamp.

      El snapshot no se sobrescribe si ya existe y contiene archivos.
      Este modo es útil para snapshots únicos e idempotentes, como
      "pre-chezmoi".

  --help, -h
      Muestra esta ayuda.
EOF
}

parse_arguments()
{
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --list)
        LIST_MODE=1
        shift
        ;;

      --name=*)
        NAME_OVERRIDE="${1#*=}"
        shift
        ;;

      --help | -h)
        usage
        exit 0
        ;;

      *)
        die "backup: opción desconocida: $1"
        ;;
    esac
  done
}

ensure_backup_root()
{
  mkdir -p "$BACKUP_ROOT"
  chmod 700 "$STATE_DIR" "$BACKUP_ROOT" 2>/dev/null || true
}

validate_snapshot_name()
{
  local name="$1"

  if [ -z "$name" ]; then
    die "backup: --name no puede estar vacío"
  fi

  if [[ "$name" =~ [[:cntrl:]] ]]; then
    die "backup: --name contiene caracteres de control"
  fi

  if [[ "$name" == */* ]]; then
    die "backup: --name debe ser un nombre, no una ruta"
  fi

  case "$name" in
    . | ..)
      die "backup: --name no puede ser '$name'"
      ;;

    *)
      ;;
  esac
}

directory_has_content()
{
  local directory="$1"

  [ -d "$directory" ] &&
    [ -n "$(find "$directory" -mindepth 1 -print -quit 2>/dev/null)" ]
}

snapshot_is_complete()
{
  local snapshot="$1"
  local marker="$snapshot/$SNAPSHOT_COMPLETE_MARKER"

  [ -d "$marker" ] && [ ! -L "$marker" ]
}

validate_target_location()
{
  local target="$1"
  local canonical_root
  local canonical_target

  canonical_root="$(
    realpath -m "$BACKUP_ROOT"
  )" || die "backup: no se pudo resolver $BACKUP_ROOT"

  canonical_target="$(
    realpath -m "$target"
  )" || die "backup: no se pudo resolver $target"

  case "$canonical_target" in
    "$canonical_root"/*)
      ;;

    *)
      die "backup: el destino escapa del directorio de backups: $target"
      ;;
  esac
}

list_snapshots()
{
  local directory
  local name
  local size
  local files
  local found=0

  log_info "backup: snapshots en $BACKUP_ROOT"

  for directory in "$BACKUP_ROOT"/*/; do
    [ -d "$directory" ] || continue

    found=1
    name="$(basename "$directory")"
    size="$(du -sh "$directory" 2>/dev/null | cut -f1)"
    files="$(
      find "$directory" -type f -print 2>/dev/null |
        wc -l |
        tr -d '[:space:]'
    )"

    log_info "  $name ($files archivos, ${size:-tamaño desconocido})"
  done

  if [ "$found" -eq 0 ]; then
    log_info "  (ninguno)"
  fi
}

create_snapshot_target()
{
  local timestamp
  local target

  if [ -n "$NAME_OVERRIDE" ]; then
    validate_snapshot_name "$NAME_OVERRIDE"

    target="$BACKUP_ROOT/$NAME_OVERRIDE"
    validate_target_location "$target"

    mkdir -p "$target"
    chmod 700 "$target"

    printf '%s\n' "$target"
    return 0
  fi

  timestamp="$(date +%Y%m%d-%H%M%S)"

  target="$(
    mktemp -d "$BACKUP_ROOT/${timestamp}.XXXXXX"
  )" || die "backup: mktemp falló"

  chmod 700 "$target"

  printf '%s\n' "$target"
}

copy_snapshot_files()
{
  local target="$1"
  local source_path
  local relative_path
  local failed=0
  local count=0

  local -a default_targets=(
    ".zshrc"
    ".zshenv"
    ".bashrc"
    ".bash_profile"
    ".profile"
    ".gitconfig"
    ".ssh/config"
    ".config/starship.toml"
    ".config/git/ignore"
    ".config/fish"
  )

  local -a failed_files=()

  for relative_path in "${default_targets[@]}"; do
    source_path="$HOME/$relative_path"

    if [ ! -e "$source_path" ] && [ ! -L "$source_path" ]; then
      continue
    fi

    mkdir -p "$target/$(dirname "$relative_path")"

    if cp -a "$source_path" "$target/$relative_path" 2>/dev/null; then
      count=$((count + 1))
    else
      failed=1
      failed_files+=("$relative_path")
      log_warn "backup: fallo copiando $relative_path"
    fi
  done

  if [ "$failed" -ne 0 ]; then
    log_error \
      "backup: ${#failed_files[@]} elemento(s) no pudieron copiarse"

    for relative_path in "${failed_files[@]}"; do
      log_info "  - $relative_path"
    done

    return 1
  fi

  if ! mkdir "$target/$SNAPSHOT_COMPLETE_MARKER"; then
    log_error "backup: no se pudo marcar el snapshot como completado"
    return 1
  fi

  log_info "backup: $count elementos copiados en $target"
}

create_snapshot()
{
  local target
  local target_existed=0

  if [ -n "$NAME_OVERRIDE" ]; then
    target="$BACKUP_ROOT/$NAME_OVERRIDE"

    if snapshot_is_complete "$target"; then
      log_info \
        "backup: $NAME_OVERRIDE ya existe y está completado; omitiendo"

      printf '%s\n' "$target"
      return 0
    fi

    if directory_has_content "$target"; then
      die \
        "backup: el snapshot fijo existente está incompleto: $target; conserva sus archivos y elimínalo o complétalo antes de reintentar"
    fi

    if [ -d "$target" ]; then
      target_existed=1
    fi
  fi

  target="$(create_snapshot_target)"

  if ! copy_snapshot_files "$target"; then
    # Los snapshots timestamped fallidos se eliminan porque fueron creados
    # exclusivamente para esta ejecución.
    #
    # Un directorio fixed-name que ya existía vacío se conserva para evitar
    # eliminar una ruta creada externamente.
    if [ -z "$NAME_OVERRIDE" ] || [ "$target_existed" -eq 0 ]; then
      rm -rf "$target"
    fi

    die "backup: el snapshot no pudo completarse"
  fi

  # La ruta es el único valor funcional emitido por stdout.
  printf '%s\n' "$target"
}

main()
{
  parse_arguments "$@"
  ensure_backup_root

  if [ "$LIST_MODE" -eq 1 ]; then
    if [ -n "$NAME_OVERRIDE" ]; then
      die "backup: --list y --name no pueden combinarse"
    fi

    list_snapshots
    return 0
  fi

  create_snapshot
}

main "$@"
