#!/bin/bash
# Verificación y registro de las claves SSH de host de github.com.
#
# Las claves obtenidas mediante ssh-keyscan se validan contra fingerprints
# SHA-256 publicados oficialmente por GitHub antes de escribir known_hosts.
#
# Este módulo no termina el proceso por sí mismo:
#   - registra el error;
#   - retorna un código distinto de cero;
#   - el script llamador decide si debe usar die().
#
# Referencia oficial:
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints

if [ -n "${_BOOTSTRAP_LIB_SSH_LOADED:-}" ]; then
  return 0
fi
_BOOTSTRAP_LIB_SSH_LOADED=1

# shellcheck source=log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log.sh"

readonly _GITHUB_HOST="github.com"
readonly _GITHUB_FINGERPRINTS_URL="https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints"
readonly _GITHUB_MARKER_PREFIX="# added by dev-environment bootstrap"

declare -Ar GITHUB_HOST_FINGERPRINTS=(
  [ssh-ed25519]="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
  [ecdsa-sha2-nistp256]="SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM"
  [ssh-rsa]="SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s"
)

# _ssh_require_command <command>
_ssh_require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "ssh-host-keys: comando requerido no disponible: $command_name"
    return 1
  fi
}

# _github_host_key_fingerprint <key-type> <base64-key-data>
#
# Imprime el fingerprint SHA-256 calculado mediante ssh-keygen.
_github_host_key_fingerprint() {
  local key_type="$1"
  local key_data="$2"
  local fingerprint

  if [ -z "$key_type" ] || [ -z "$key_data" ]; then
    return 1
  fi

  fingerprint=$(
    printf '%s %s\n' "$key_type" "$key_data" |
      ssh-keygen -E sha256 -lf - 2>/dev/null |
      awk 'NR == 1 { print $2 }'
  )

  if [ -z "$fingerprint" ]; then
    return 1
  fi

  printf '%s\n' "$fingerprint"
}

# _github_host_key_valid <key-type> <base64-key-data>
_github_host_key_valid() {
  local key_type="$1"
  local key_data="$2"
  local expected_fingerprint
  local computed_fingerprint

  expected_fingerprint="${GITHUB_HOST_FINGERPRINTS[$key_type]:-}"

  if [ -z "$expected_fingerprint" ]; then
    return 1
  fi

  computed_fingerprint=$(
    _github_host_key_fingerprint "$key_type" "$key_data"
  ) || return 1

  [ "$computed_fingerprint" = "$expected_fingerprint" ]
}

# gh_fetch_github_host_keys
#
# Obtiene las claves públicas de host de github.com, verifica todos sus
# fingerprints y escribe únicamente las claves verificadas en stdout.
#
# Retorna:
#   0 si se verificaron todas las claves esperadas.
#   1 si ssh-keyscan falla, la salida es inválida o un fingerprint no coincide.
gh_fetch_github_host_keys() {
  local scan_output
  local line
  local host
  local key_type
  local key_data
  local expected_key_type

  local -a verified_lines=()
  local -A seen_key_types=()

  _ssh_require_command ssh-keyscan || return 1
  _ssh_require_command ssh-keygen || return 1
  _ssh_require_command awk || return 1

  if ! scan_output=$(
    ssh-keyscan \
      -T 10 \
      -t ed25519,ecdsa,rsa \
      "$_GITHUB_HOST" 2>/dev/null
  ); then
    log_error "ssh-host-keys: ssh-keyscan falló para $_GITHUB_HOST"
    return 1
  fi

  if [ -z "$scan_output" ]; then
    log_error "ssh-host-keys: ssh-keyscan no retornó claves para $_GITHUB_HOST"
    return 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue

    read -r host key_type key_data _ <<< "$line"

    if [ -z "$host" ] || [ -z "$key_type" ] || [ -z "$key_data" ]; then
      log_error "ssh-host-keys: línea malformada recibida desde ssh-keyscan"
      return 1
    fi

    if [ "$host" != "$_GITHUB_HOST" ]; then
      log_error "ssh-host-keys: host inesperado recibido: $host"
      return 1
    fi

    if [ -z "${GITHUB_HOST_FINGERPRINTS[$key_type]:-}" ]; then
      log_error "ssh-host-keys: tipo de clave no soportado: $key_type"
      return 1
    fi

    if ! _github_host_key_valid "$key_type" "$key_data"; then
      log_error "ssh-host-keys: fingerprint no válido para $key_type"
      log_error "ssh-host-keys: verifica si GitHub rotó sus claves: $_GITHUB_FINGERPRINTS_URL"
      return 1
    fi

    seen_key_types["$key_type"]=1
    verified_lines+=("$host $key_type $key_data")
  done <<< "$scan_output"

  for expected_key_type in "${!GITHUB_HOST_FINGERPRINTS[@]}"; do
    if [ -z "${seen_key_types[$expected_key_type]:-}" ]; then
      log_error "ssh-host-keys: GitHub no proporcionó la clave esperada: $expected_key_type"
      return 1
    fi
  done

  if [ "${#verified_lines[@]}" -eq 0 ]; then
    log_error "ssh-host-keys: no se obtuvo ninguna clave verificada"
    return 1
  fi

  printf '%s\n' "${verified_lines[@]}"
}

# trust_github_host
#
# Actualiza ~/.ssh/known_hosts de forma atómica:
#   1. rechaza symlinks;
#   2. conserva las entradas existentes de otros hosts;
#   3. elimina las entradas anteriores de github.com, incluso las hasheadas;
#   4. agrega únicamente claves verificadas;
#   5. reemplaza known_hosts mediante un mv dentro del mismo filesystem.
trust_github_host() {
  local ssh_dir="${HOME}/.ssh"
  local known_hosts="${HOME}/.ssh/known_hosts"
  local existing_tmp
  local verified_tmp
  local marker

  _ssh_require_command mktemp || return 1
  _ssh_require_command ssh-keygen || return 1

  if [ -L "$ssh_dir" ]; then
    log_error "ssh-host-keys: $ssh_dir es un symlink; se rechazó la operación"
    return 1
  fi

  if ! mkdir -p "$ssh_dir"; then
    log_error "ssh-host-keys: no se pudo crear $ssh_dir"
    return 1
  fi

  if ! chmod 0700 "$ssh_dir"; then
    log_error "ssh-host-keys: no se pudieron establecer permisos en $ssh_dir"
    return 1
  fi

  if [ -L "$known_hosts" ]; then
    log_error "ssh-host-keys: $known_hosts es un symlink; se rechazó la operación"
    return 1
  fi

  if [ -e "$known_hosts" ] && [ ! -f "$known_hosts" ]; then
    log_error "ssh-host-keys: $known_hosts existe pero no es un archivo regular"
    return 1
  fi

  existing_tmp=$(mktemp -p "$ssh_dir" "known_hosts.existing.XXXXXX") || {
    log_error "ssh-host-keys: no se pudo crear el archivo temporal"
    return 1
  }

  verified_tmp=$(mktemp -p "$ssh_dir" "known_hosts.verified.XXXXXX") || {
    rm -f -- "$existing_tmp"
    log_error "ssh-host-keys: no se pudo crear el archivo temporal de claves"
    return 1
  }

  if ! chmod 0600 "$existing_tmp" "$verified_tmp"; then
    rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp"
    log_error "ssh-host-keys: no se pudieron establecer permisos temporales"
    return 1
  fi

  log_info "verificando claves SSH de host de $_GITHUB_HOST..."

  if ! gh_fetch_github_host_keys > "$verified_tmp"; then
    rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp"
    log_error "ssh-host-keys: no se pudieron verificar las claves de $_GITHUB_HOST"
    return 1
  fi

  if [ ! -s "$verified_tmp" ]; then
    rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp"
    log_error "ssh-host-keys: el bloque de claves verificadas está vacío"
    return 1
  fi

  if [ -f "$known_hosts" ]; then
    if ! awk \
      -v marker="$_GITHUB_MARKER_PREFIX" \
      'index($0, marker) != 1 { print }' \
      "$known_hosts" > "$existing_tmp"; then
      rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp"
      log_error "ssh-host-keys: no se pudo leer el known_hosts existente"
      return 1
    fi

    # Elimina entradas visibles o hasheadas asociadas con github.com.
    ssh-keygen \
      -q \
      -f "$existing_tmp" \
      -R "$_GITHUB_HOST" >/dev/null 2>&1 || true

    ssh-keygen \
      -q \
      -f "$existing_tmp" \
      -R "[$_GITHUB_HOST]:22" >/dev/null 2>&1 || true
  fi

  marker="$_GITHUB_MARKER_PREFIX -- verified $(date +%Y-%m-%d)"

  {
    if [ -s "$existing_tmp" ]; then
      cat "$existing_tmp"
    fi

    printf '%s\n' "$marker"
    cat "$verified_tmp"
  } > "${verified_tmp}.new" || {
    rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp" "${verified_tmp}.new"
    log_error "ssh-host-keys: no se pudo construir el nuevo known_hosts"
    return 1
  }

  if ! chmod 0600 "${verified_tmp}.new"; then
    rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp" "${verified_tmp}.new"
    log_error "ssh-host-keys: no se pudieron establecer los permisos finales"
    return 1
  fi

  if [ ! -s "${verified_tmp}.new" ]; then
    rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp" "${verified_tmp}.new"
    log_error "ssh-host-keys: el nuevo known_hosts está vacío"
    return 1
  fi

  if ! mv -f -- "${verified_tmp}.new" "$known_hosts"; then
    rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp" "${verified_tmp}.new"
    log_error "ssh-host-keys: no se pudo reemplazar $known_hosts"
    return 1
  fi

  rm -f -- "$existing_tmp" "${existing_tmp}.old" "$verified_tmp"

  if ! chmod 0600 "$known_hosts"; then
    log_error "ssh-host-keys: no se pudieron establecer permisos en $known_hosts"
    return 1
  fi

  log_info "claves SSH de host de $_GITHUB_HOST verificadas y actualizadas"
}
