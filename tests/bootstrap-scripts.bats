#!/usr/bin/env bats
# Smoke tests para los scripts ubicados en bootstrap/.
# Verifica estructura, permisos, sintaxis y contrato de argumentos.
# No ejecuta instalaciones ni actualizaciones reales.

setup()
{
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BOOTSTRAP_DIR="$REPO_ROOT/bootstrap"
}

UPDATABLE_COMPONENTS=(
  actionlint
  hadolint
  checkov
  semgrep
  markdownlint
  pi
  chezmoi
  aws
)

@test "bootstrap/ contiene scripts de instalación" {
  compgen -G "$BOOTSTRAP_DIR/*.sh" >/dev/null
}

@test "cada script en bootstrap/ es un archivo regular" {
  for script in "$BOOTSTRAP_DIR"/*.sh; do
    if [ ! -f "$script" ]; then
      echo "No es un archivo regular: $script"
      return 1
    fi
  done
}

@test "cada script en bootstrap/ es ejecutable" {
  for script in "$BOOTSTRAP_DIR"/*.sh; do
    if [ ! -x "$script" ]; then
      echo "No es ejecutable: $script"
      return 1
    fi
  done
}

@test "cada script en bootstrap/ pasa bash -n" {
  for script in "$BOOTSTRAP_DIR"/*.sh; do
    run bash -n "$script"

    if [ "$status" -ne 0 ]; then
      echo "Error de sintaxis en: $script"
      echo "$output"
      return 1
    fi
  done
}

@test "cada bootstrap actualizable rechaza una acción inválida con código 2" {
  for component in "${UPDATABLE_COMPONENTS[@]}"; do
    script="$BOOTSTRAP_DIR/$component.sh"

    run bash "$script" invalid-action

    if [ "$status" -ne 2 ]; then
      echo "$component: la acción inválida debería retornar 2, retornó $status"
      echo "$output"
      return 1
    fi
  done
}
