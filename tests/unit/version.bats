#!/usr/bin/env bats
#
# Tests unitarios para bootstrap/lib/version.sh.

setup()
{
  load "../../bootstrap/lib/version.sh"
}

@test "normalize_version quita espacios y prefijo v" {
  run normalize_version "  v1.2.3  "
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
}

@test "normalize_version conserva una versión sin cambios" {
  run normalize_version "1.2.3"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
}

@test "version_equals retorna éxito con versiones iguales" {
  run version_equals "v1.2.3" "1.2.3"
  [ "$status" -eq 0 ]
}

@test "version_equals normaliza espacios en ambos valores" {
  run version_equals "  v1.2.3 " "1.2.3  "
  [ "$status" -eq 0 ]
}

@test "version_equals retorna fallo con versiones distintas" {
  run version_equals "v1.2.3" "v1.2.4"
  [ "$status" -ne 0 ]
}
