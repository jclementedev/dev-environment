#!/usr/bin/env bats
#
# Tests para scripts/update-tools.sh (orquestador de actualización).
#
# Los stubs en tests/fixtures/bin/ simulan sudo, apt-get, pipx, npm,
# curl y jq. Cada stub registra sus argumentos y retorna el código
# configurado mediante STUB_EXIT_CODE.

setup()
{
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  export PATH="$BATS_TEST_DIRNAME/fixtures/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  export STUB_EXIT_CODE=0

  : >"$STUB_LOG"
}

teardown()
{
  rm -f "$STUB_LOG"
}

@test "retorna 1 cuando una o más actualizaciones fallan" {
  export STUB_EXIT_CODE=1

  run "$REPO_ROOT/scripts/update-tools.sh"

  if [ "$status" -ne 1 ]; then
    echo "Se esperaba exit 1, se obtuvo exit $status"
    echo "$output"
    return 1
  fi
}

@test "continúa hasta el último componente cuando ocurren errores" {
  export STUB_EXIT_CODE=1

  run "$REPO_ROOT/scripts/update-tools.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"chezmoi"* ]]
}

@test "imprime el resumen de ejecución" {
  export STUB_EXIT_CODE=1

  run "$REPO_ROOT/scripts/update-tools.sh"

  [ "$status" -eq 1 ]

  [[ "$output" == *"--- resumen ---"* ]]
  [[ "$output" == *"apt"* ]]
  [[ "$output" == *"actionlint"* ]]
  [[ "$output" == *"hadolint"* ]]
  [[ "$output" == *"checkov"* ]]
  [[ "$output" == *"semgrep"* ]]
  [[ "$output" == *"markdownlint"* ]]
  [[ "$output" == *"pi"* ]]
  [[ "$output" == *"chezmoi"* ]]
}

@test "el resumen marca componentes fallidos" {
  export STUB_EXIT_CODE=1

  run "$REPO_ROOT/scripts/update-tools.sh"

  [ "$status" -eq 1 ]

  [[ "$output" == *"✗ apt"* ]]
  [[ "$output" == *"✗ actionlint"* ]]
  [[ "$output" == *"✗ chezmoi"* ]]
}

@test "limpia los archivos temporales al finalizar" {
  export STUB_EXIT_CODE=1

  local count

  run "$REPO_ROOT/scripts/update-tools.sh"

  [ "$status" -eq 1 ]

  count="$(
    find "$BATS_TEST_TMPDIR" \
      -maxdepth 1 \
      -type f \
      ! -name 'stub.log' \
      2>/dev/null |
      wc -l
  )"

  if [ "$count" -ne 0 ]; then
    echo "Se encontraron archivos temporales sin limpiar:"
    find "$BATS_TEST_TMPDIR" \
      -maxdepth 1 \
      -type f \
      ! -name 'stub.log'
    return 1
  fi
}
