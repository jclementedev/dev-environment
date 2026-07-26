#!/bin/bash
#
# update-tools.sh — actualiza las herramientas del entorno de desarrollo.
#
# Flujo:
#   1. Valida prerrequisitos del orquestador.
#   2. Ejecuta APT.
#   3. Itera sobre UPDATABLE_COMPONENTS.
#   4. Para cada componente, captura stdout+stderr a un archivo temporal.
#   5. Al final, imprime el resumen y retorna el código apropiado.

set -Eeuo pipefail

readonly -a UPDATABLE_COMPONENTS=(
  actionlint
  hadolint
  checkov
  semgrep
  markdownlint
  pi
  chezmoi
  aws
)

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BOOTSTRAP_DIR="$REPO_ROOT/bootstrap"

# shellcheck source=bootstrap/lib/log.sh
. "$BOOTSTRAP_DIR/lib/log.sh"

TEMP_FILES=()

cleanup()
{
  rm -f "${TEMP_FILES[@]}"
}

trap cleanup EXIT INT TERM

declare -A result_status=()
declare -A result_detail=()

update_apt_packages()
{
  if ! command -v sudo >/dev/null 2>&1; then
    log_error "apt: sudo no está disponible"
    return 1
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    log_error "apt: apt-get no está disponible"
    return 1
  fi

  if ! sudo -v </dev/tty; then
    log_error "apt: sudo -v falló"
    return 1
  fi

  log_info "apt: actualizando índices"
  sudo apt-get update

  log_info "apt: actualizando paquetes"
  sudo apt-get upgrade
}

run_bootstrap_update()
{
  local component="$1"
  local output_file="$2"
  local bootstrap_script="$BOOTSTRAP_DIR/$component.sh"

  if [ ! -f "$bootstrap_script" ]; then
    printf '%s\n' "$component: bootstrap no encontrado" >"$output_file"
    return 1
  fi

  bash "$bootstrap_script" update >"$output_file" 2>&1
}

print_summary()
{
  local component
  local status
  local detail

  log_info "--- resumen ---"

  for component in apt "${UPDATABLE_COMPONENTS[@]}"; do
    status="${result_status[$component]:-failed}"
    detail="${result_detail[$component]:-}"

    case "$status" in
      success)
        printf '✓ %s\n' "$component"
        ;;
      failed)
        printf '✗ %s\n' "$component"

        if [ -n "$detail" ]; then
          printf '%s\n' "$detail"
        fi
        ;;
    esac
  done
}

main()
{
  local component
  local output_file
  local status
  local any_failed=0

  if ! output_file="$(mktemp)"; then
    die "no se pudo crear un archivo temporal"
  fi
  TEMP_FILES+=("$output_file")

  if update_apt_packages >"$output_file" 2>&1; then
    result_status["apt"]="success"
    result_detail["apt"]=""
  else
    result_status["apt"]="failed"
    result_detail["apt"]="$(tail -n 5 "$output_file")"
    any_failed=1
  fi

  for component in "${UPDATABLE_COMPONENTS[@]}"; do
    if ! output_file="$(mktemp)"; then
      log_error "$component: no se pudo crear un archivo temporal"
      result_status["$component"]="failed"
      result_detail["$component"]="no se pudo crear un archivo temporal"
      any_failed=1
      continue
    fi
    TEMP_FILES+=("$output_file")

    log_info "actualizando $component"

    if run_bootstrap_update "$component" "$output_file"; then
      result_status["$component"]="success"
      result_detail["$component"]=""
    else
      status=$?

      result_status["$component"]="failed"
      result_detail["$component"]="exit $status
$(tail -n 5 "$output_file")"

      any_failed=1
    fi
  done

  print_summary

  if [ "$any_failed" -eq 1 ]; then
    exit 1
  fi
}

main "$@"
