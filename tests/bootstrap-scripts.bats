#!/usr/bin/env bats
# Smoke tests comunes para todos los scripts en bootstrap/.
# Los instaladores con lógica particular pueden tener tests específicos.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BOOTSTRAP_DIR="$REPO_ROOT/bootstrap"
}

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