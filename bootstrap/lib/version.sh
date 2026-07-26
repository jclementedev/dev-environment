#
# version.sh — utilidades puras de normalización y comparación de versiones.
#
# No accede a la red ni a GitHub. No parsea formatos de salida de herramientas
# específicas. Cada bootstrap implementa su propia función de extracción.

normalize_version()
{
  local version="${1-}"

  version="${version#"${version%%[![:space:]]*}"}"
  version="${version%"${version##*[![:space:]]}"}"
  version="${version#v}"

  printf '%s\n' "$version"
}

version_equals()
{
  [ "$(normalize_version "${1-}")" = "$(normalize_version "${2-}")" ]
}
