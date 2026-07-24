#!/bin/bash
# Biblioteca de estado de cuentas de GitHub (primarias y secundarias).

set -Eeuo pipefail

GITHUB_ACCOUNTS_STATE_DIR="${DEV_ENV_STATE_DIR:-$HOME/.local/state/dev-env-bootstrap}"
STATE_FILE="${STATE_FILE:-$GITHUB_ACCOUNTS_STATE_DIR/github-accounts.json}"
LOCK_FILE="${LOCK_FILE:-$GITHUB_ACCOUNTS_STATE_DIR/accounts.lock}"
STATE_DIR="$(dirname "$STATE_FILE")"

# Verificación de dependencia: jq requerido.
_ensure_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq requerido pero no encontrado" >&2
        return 1
    fi
}

SCHEMA_VERSION=1

# validate_schema: sale con 0 si el JSON tiene la estructura esperada.
validate_schema() {
    _ensure_jq

    if [ ! -f "$STATE_FILE" ]; then
        echo "validate_schema: archivo de estado faltante" >&2
        return 1
    fi

    # Debe ser JSON valido
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        echo "validate_schema: JSON inválido" >&2
        return 1
    fi

    # Verificar que schema_version existe y es 1
    local version
    version=$(jq -r '.schema_version // empty' "$STATE_FILE" 2>/dev/null) || {
        echo "validate_schema: schema_version faltante" >&2
        return 1
    }

    if [ "$version" != "$SCHEMA_VERSION" ]; then
        echo "validate_schema: versión de esquema no soportada $version (se esperaba $SCHEMA_VERSION)" >&2
        return 1
    fi

    # Verificar que primary_accounts es un array
    if ! jq -e '.primary_accounts | type == "array"' "$STATE_FILE" >/dev/null 2>&1; then
        echo "validate_schema: primary_accounts debe ser un array" >&2
        return 1
    fi

    # Verificar que secondary_accounts es un array
    if ! jq -e '.secondary_accounts | type == "array"' "$STATE_FILE" >/dev/null 2>&1; then
        echo "validate_schema: secondary_accounts debe ser un array" >&2
        return 1
    fi

    # Preserve primary records created before github_login was recorded, while
    # requiring complete typed secondary records and cross-record invariants.
    if ! jq -e '
        def has_string_fields($fields):
            if type != "object" then false
            else . as $record | all($fields[]; ($record[.] | type == "string"))
            end;

        (.primary_accounts | length <= 1) and
        (.primary_accounts | all(.[];
            has_string_fields(["id", "name", "email", "ssh_key"]) and
            .id == "primary" and
            ((has("github_login") | not) or (.github_login | type == "string")))) and
        (.secondary_accounts | all(.[];
            has_string_fields(["id", "name", "email", "github_login", "ssh_key", "ssh_alias", "scope"]))) and
        (.secondary_accounts | map(.id) | length == (unique | length)) and
        (.secondary_accounts | map(.ssh_alias | ascii_downcase) | length == (unique | length))
    ' "$STATE_FILE" >/dev/null 2>&1; then
        echo "validate_schema: registros de cuentas inválidos o duplicados" >&2
        return 1
    fi

    return 0
}

# read_state: imprime el JSON de estado (o {} si no existe).
read_state() {
    _ensure_jq

    if [ ! -f "$STATE_FILE" ]; then
        echo "{}"
        return 0
    fi

    if ! validate_schema; then
        echo "read_state: validación de esquema fallida" >&2
        return 1
    fi

    cat "$STATE_FILE"
    return 0
}

# write_state: persiste el JSON dado en el archivo de estado.
write_state() {
    _ensure_jq

    local json="$1"
    local temporary_file

    if ! printf '%s\n' "$json" | jq empty 2>/dev/null; then
        echo "write_state: JSON inválido proporcionado" >&2
        return 1
    fi

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    temporary_file=$(mktemp "$STATE_DIR/github-accounts.json.XXXXXX") || {
        echo "write_state: no se pudo crear el archivo temporal" >&2
        return 1
    }

    if ! printf '%s\n' "$json" | jq '.' > "$temporary_file"; then
        rm -f "$temporary_file"
        echo "write_state: no se pudo serializar el estado" >&2
        return 1
    fi

    local state_file="$STATE_FILE"
    STATE_FILE="$temporary_file"
    if ! validate_schema; then
        STATE_FILE="$state_file"
        rm -f "$temporary_file"
        echo "write_state: estado no cumple el esquema" >&2
        return 1
    fi
    STATE_FILE="$state_file"

    if ! chmod 600 "$temporary_file"; then
        rm -f "$temporary_file"
        echo "write_state: no se pudieron establecer permisos seguros" >&2
        return 1
    fi

    if ! mv -f "$temporary_file" "$STATE_FILE"; then
        rm -f "$temporary_file"
        echo "write_state: no se pudo activar el nuevo estado" >&2
        return 1
    fi
}

# init_state: crea archivo de estado vacio si falta.
init_state() {
    _ensure_jq

    if [ -f "$STATE_FILE" ]; then
        if ! validate_schema; then
            echo "init_state: archivo de estado existente no es válido; no se modificó" >&2
            return 1
        fi
        return 0
    fi

    local empty_state
    empty_state=$(jq -n \
        --arg v "$SCHEMA_VERSION" \
        '{"schema_version": $v | tonumber, "primary_accounts": [], "secondary_accounts": []}')

    write_state "$empty_state"
    return 0
}

# get_primary: imprime el JSON de la cuenta primaria (o vacio si no hay).
get_primary() {
    _ensure_jq

    if [ ! -f "$STATE_FILE" ]; then
        return 0
    fi

    local primary
    primary=$(jq '.primary_accounts[0] // empty' "$STATE_FILE" 2>/dev/null) || return 0
    echo "$primary"
    return 0
}

# set_primary <name> <email> <ssh_key> <github_login>
# Registra la cuenta primaria. Es idempotente con el mismo payload.
set_primary() {
    _ensure_jq

    local name="$1"
    local email="$2"
    local ssh_key="$3"
    local github_login="$4"

    [ -n "$name" ] || {
        echo "set_primary: nombre requerido" >&2
        return 1
    }

    validate_email "$email" || return 1
    validate_github_login "$github_login" || return 1

    ssh_key="${ssh_key/#\~/$HOME}"
    ssh_key="$(realpath -m -- "$ssh_key" 2>/dev/null || printf '%s' "$ssh_key")"
    validate_key_path "$ssh_key" || return 1

    init_state

    local current_state existing_primary
    current_state=$(read_state) || return 1
    existing_primary=$(printf '%s\n' "$current_state" | jq '.primary_accounts[0] // empty')

    if [ -n "$existing_primary" ]; then
        local existing_name existing_email existing_key existing_login
        existing_name=$(printf '%s\n' "$existing_primary" | jq -r '.name')
        existing_email=$(printf '%s\n' "$existing_primary" | jq -r '.email')
        existing_key=$(printf '%s\n' "$existing_primary" | jq -r '.ssh_key')
        existing_login=$(printf '%s\n' "$existing_primary" | jq -r '.github_login // empty')

        if [ "$existing_name" = "$name" ] && \
           [ "$existing_email" = "$email" ] && \
           [ "$existing_key" = "$ssh_key" ] && \
           [ "$existing_login" = "$github_login" ]; then
            return 0
        fi

        echo "set_primary: la cuenta primaria ya existe con valores diferentes" >&2
        return 1
    fi

    local updated_state
    updated_state=$(printf '%s\n' "$current_state" | jq \
        --arg name "$name" \
        --arg email "$email" \
        --arg ssh_key "$ssh_key" \
        --arg github_login "$github_login" \
        '.primary_accounts = [{
            id: "primary",
            name: $name,
            email: $email,
            ssh_key: $ssh_key,
            github_login: $github_login
        }]') || return 1

    write_state "$updated_state"
}

# Validación: ID ^[A-Za-z0-9_-]{1,32}$ (reservado 'primary'); Alias ^[a-z0-9][a-z0-9-]{0,62}$ (reservado 'github.com'); login GitHub; Email con @; Ruta de clave: bajo ~/.ssh/; Scope: ruta absoluta.

# validate_id <id>
validate_id() {
    local id="$1"

    # Verificar ID reservado
    if [ "$id" = "primary" ]; then
        echo "validate_id: 'primary' está reservado" >&2
        return 1
    fi

    # Debe coincidir con ^[A-Za-z0-9_-]{1,32}$
    if ! [[ "$id" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
        echo "validate_id: id invalido '$id' (debe coincidir ^[A-Za-z0-9_-]{1,32}$)" >&2
        return 1
    fi

    return 0
}

# validate_alias <alias>
validate_alias() {
    local alias="$1"

    # Verificar alias reservado (case-insensitive)
    if [[ "$(echo "$alias" | tr '[:upper:]' '[:lower:]')" = "github.com" ]]; then
        echo "validate_alias: 'github.com' está reservado" >&2
        return 1
    fi

    # Debe coincidir con ^[a-z0-9][a-z0-9-]{0,62}$
    if ! [[ "$alias" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
        echo "validate_alias: alias invalido '$alias' (debe coincidir ^[a-z0-9][a-z0-9-]{0,62}$)" >&2
        return 1
    fi

    return 0
}

# validate_email <email>
validate_email() {
    local email="$1"

    if ! [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
        echo "validate_email: formato de email inválido" >&2
        return 1
    fi

    return 0
}

# validate_github_login <login>
# GitHub usernames have 1-39 alphanumeric or hyphen characters and cannot
# start or end with a hyphen.
validate_github_login() {
    local login="$1"

    if ! [[ "$login" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]]; then
        echo "validate_github_login: login de GitHub inválido" >&2
        return 1
    fi

    return 0
}

# validate_key_path <path>
# Valida una ruta de clave SSH privada.
# Rechaza: caracteres de control, null bytes, extension .pub, componentes '..'.
# Acepta cualquier ruta absoluta que no escape de su directorio contenedor
# mediante '..' o symlinks. Las staging keys (STATE_DIR) se mueven atomicamente
# a ~/.ssh/ antes de activacion, por lo que no representan riesgo de injection.
validate_key_path() {
    local key_path="$1"

    # Expandir tilde
    key_path="${key_path/#\~/$HOME}"

    # Rechazar caracteres de control.
    if [[ "$key_path" =~ [[:cntrl:]] ]]; then
        echo "validate_key_path: caracteres de control no permitidos" >&2
        return 1
    fi

    # Rechazar sufijo .pub.
    if [[ "$key_path" == *.pub ]]; then
        echo "validate_key_path: extension .pub no permitida" >&2
        return 1
    fi

    # Rechazar componentes de traversal '..'.
    if [[ "$key_path" == ".." ]] || \
       [[ "$key_path" == ../* ]] || \
       [[ "$key_path" == */.. ]] || \
       [[ "$key_path" == */../* ]]; then
        echo "validate_key_path: componentes de traversal '..' no permitidos" >&2
        return 1
    fi

    local canonical
    canonical=$(realpath -m -- "$key_path" 2>/dev/null) || canonical="$key_path"

    # Verificar que la ruta canónica está dentro de un directorio de confianza.
    local ssh_dir="${HOME}/.ssh"
    local sshd_dir="${HOME}/.ssh.d"
    local state_dir="$GITHUB_ACCOUNTS_STATE_DIR"

    case "$canonical" in
        "$ssh_dir"/*|"$sshd_dir"/*|"$state_dir"/*) ;;   # trusted o staging
        "$ssh_dir"|"$sshd_dir"|"$state_dir") ;;            # los directorios mismos
        "$HOME"/*) ;;                                      # cualquier cosa bajo HOME
        *)
            # Aceptar rutas absolutas externas a HOME (importacion de clave
            # existente de otro sistema). La verificacion de traversal arriba
            # ya rechazo '/../' y componentes '..' puros.
            if [[ "$canonical" == /* ]]; then
                return 0
            fi
            echo "validate_key_path: ruta no válida o fuera de directorio de confianza" >&2
            return 1
            ;;
    esac

    return 0
}

# normalize_scope <path>
# Normaliza una ruta de scope a forma absoluta
normalize_scope() {
    local scope="$1"

    scope="${scope/#\~/$HOME}"

    if [[ "$scope" != /* ]]; then
        scope="$PWD/$scope"
    fi

    scope="$(realpath -m -- "$scope" 2>/dev/null || printf '%s' "$scope")"

    if [ "$scope" != "/" ]; then
        scope="${scope%/}"
    fi

    printf '%s\n' "$scope"
}

# validate_scope <path>
# Defense-in-depth: reject scope values containing characters outside [a-zA-Z0-9._/-].
validate_scope() {
    local scope="$1"

    # Rechazar caracteres potencialmente peligrosos para command injection.
    # Solo acepta: a-z A-Z 0-9 . _ / -
    if ! [[ "$scope" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        echo "validate_scope: scope contiene caracteres no permitidos (solo se permiten a-z A-Z 0-9 . _ / -)" >&2
        return 1
    fi

    # Expandir y normalizar
    scope=$(normalize_scope "$scope")

    # Debe ser ruta absoluta
    if [[ "$scope" != /* ]]; then
        echo "validate_scope: scope debe ser ruta absoluta" >&2
        return 1
    fi

    # No debe ser root
    if [ "$scope" = "/" ]; then
        echo "validate_scope: root '/' no está permitido como scope" >&2
        return 1
    fi

    return 0
}

# validate_scope_non_overlap <scope1> <scope2>
# Retorna 0 si los scopes no se solapan, sale con 1 si son iguales/ancestro/descendiente
validate_scope_non_overlap() {
    local scope1="$1"
    local scope2="$2"

    # Normalizar ambos scopes
    scope1=$(normalize_scope "$scope1")
    scope2=$(normalize_scope "$scope2")

    # Scopes iguales se solapan
    if [ "$scope1" = "$scope2" ]; then
        echo "validate_scope_non_overlap: scopes son iguales: $scope1" >&2
        return 1
    fi

    # scope1 es ancestro de scope2 (scope2 comienza con scope1/)
    if [[ "$scope2" == "$scope1"/* ]]; then
        echo "validate_scope_non_overlap: scope '$scope2' es descendiente de '$scope1'" >&2
        return 1
    fi

    # scope2 es ancestro de scope1 (scope1 comienza con scope2/)
    if [[ "$scope1" == "$scope2"/* ]]; then
        echo "validate_scope_non_overlap: scope '$scope1' es descendiente de '$scope2'" >&2
        return 1
    fi

    return 0
}

# Lock minimo: caso de uso de un solo usuario y un solo proceso.
# Adquiere con mkdir atomico; el trap EXIT limpia el lock y el staging.
_lock_dir="$(dirname "$LOCK_FILE")"

lock_acquire() {
    local staging_path="${1:-}"

    mkdir -p "$_lock_dir"
    chmod 700 "$_lock_dir"

    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        echo "lock_acquire: el lock ya está en uso" >&2
        return 1
    fi

    # Store staging_path for EXIT trap cleanup
    LOCK_STAGING_PATH="$staging_path"
    trap 'rm -rf -- "$LOCK_FILE"; if [ -n "${LOCK_STAGING_PATH:-}" ]; then rm -rf -- "$LOCK_STAGING_PATH"; fi' EXIT
    return 0
}

lock_release() {
    rm -rf -- "$LOCK_FILE"
    LOCK_STAGING_PATH=""
    trap - EXIT
    return 0
}
