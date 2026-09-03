#!/bin/bash
# scripts/account.sh — administra cuentas GitHub vía SSH.
#
# El estado vive en archivos del usuario, no en un JSON paralelo:
#   ~/.ssh/id_ed25519                    clave primaria
#   ~/.ssh/id_ed25519_<id>               claves secundarias
#   ~/.config/git/accounts/<id>.gitconfig  fragmentos gitconfig por cuenta
#   ~/.config/git/accounts-routing.gitconfig  includeIf por scope
#
# Cada cuenta fija su identidad SSH mediante core.sshCommand según el scope.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bootstrap/lib/log.sh
. "$SCRIPT_DIR/../bootstrap/lib/log.sh"
# shellcheck source=bootstrap/lib/ssh.sh
. "$SCRIPT_DIR/../bootstrap/lib/ssh.sh"

readonly SSH_DIR="$HOME/.ssh"
readonly GIT_ACCOUNTS_DIR="$HOME/.config/git/accounts"
readonly ROUTING_FILE="$HOME/.config/git/accounts-routing.gitconfig"
PRIMARY_KEY="$SSH_DIR/id_ed25519"

chezmoi_data_value() {
    local key="$1"

    command -v chezmoi >/dev/null 2>&1 || return 0
    chezmoi execute-template --source "$SCRIPT_DIR/../dotfiles" \
        "{{ index . \"$key\" | default \"\" }}" 2>/dev/null || true
}

load_primary_config() {
    local configured_key

    GITHUB_PRIMARY_EMAIL="${GITHUB_PRIMARY_EMAIL:-$(chezmoi_data_value git_user_email)}"
    configured_key="$(chezmoi_data_value primary_ssh_key)"

    if [ -n "$configured_key" ]; then
        if [[ "$configured_key" = /* ]]; then
            PRIMARY_KEY="$configured_key"
        else
            PRIMARY_KEY="$SSH_DIR/$configured_key"
        fi
    fi
}

# === CLI ===

usage() {
    cat <<EOF
Uso:
  account.sh setup-primary
  account.sh show-primary-key
  account.sh verify <primary|id>
  account.sh add <id> --name "..." --email "..." --github-username "..." --scope <path>
  account.sh list

Comandos:
  setup-primary    Genera o reutiliza la clave primaria y muestra la pública.
  show-primary-key Muestra la clave pública primaria.
  verify           Verifica la autenticación SSH de una cuenta.
  add              Agrega una cuenta secundaria.
  list             Lista cuentas configuradas.

Opciones requeridas para add:
  --name            Nombre para commits Git
  --email           Email de la cuenta
  --github-username Usuario de GitHub
  --scope           Directorio base para routing (ruta absoluta)

Defaults para add:
  clave SSH:  ~/.ssh/id_ed25519_<id>

El id 'primary' está reservado.

Ejemplos:
  account.sh setup-primary
  account.sh add work --name "José" --email "jose@work.com" --github-username jose-work --scope "\$HOME/work"
EOF
}

die() {
    log_error "$@"
    exit 1
}

require_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd es requerido"
}

check_routing_include() {
    local gitconfig="$HOME/.gitconfig"

    [ -f "$gitconfig" ] \
        || die "no existe $gitconfig; debe incluir el routing de cuentas"

    grep -qF 'accounts-routing.gitconfig' "$gitconfig" \
        || die "$gitconfig no incluye el routing de cuentas"
}

# === Validación ===

validate_id() {
    local id="$1"
    [[ "$id" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]] || die "id inválido '$id'"
    [ "$id" != "primary" ] || die "id 'primary' está reservado"
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] \
        || die "email inválido '$email'"
}

validate_github_username() {
    local username="$1"
    [[ "$username" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]] \
        || die "usuario de GitHub inválido '$username'"
}

normalize_scope() {
    local scope="$1"

    [[ "$scope" == /* ]] || scope="$PWD/$scope"
    scope="$(realpath -m -- "$scope" 2>/dev/null)" \
        || die "no se pudo normalizar el scope '$scope'"
    [ "$scope" != "/" ] \
        || die "el scope no puede ser el directorio raíz"

    printf '%s\n' "${scope%/}"
}

# === SSH ===

get_key_fingerprint() {
    local key="$1"
    ssh-keygen -lf "$key" 2>/dev/null | awk '{print $2}'
}

ensure_ssh_key() {
    local key_path="$1"
    local comment="$2"

    if [ -f "$key_path" ] && [ -f "${key_path}.pub" ]; then
        local fp
        fp=$(get_key_fingerprint "$key_path")
        [ -n "$fp" ] || die "clave existente en '$key_path' no es válida"
        log_info "account.sh: reutilizando clave (huella: ${fp:0:16}...)"
        return 0
    fi

    if [ -f "$key_path" ] || [ -f "${key_path}.pub" ]; then
        die "par de claves incompleto en '$key_path'"
    fi

    [ -t 1 ] || die "se requiere terminal interactiva para ssh-keygen"
    mkdir -p "$(dirname "$key_path")"
    chmod 700 "$(dirname "$key_path")"
    log_info "account.sh: generando clave SSH en '$key_path'"
    ssh-keygen -t ed25519 -f "$key_path" -C "$comment" </dev/tty \
        || die "falló la generación de clave SSH"
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
}

# === Generación ===

write_git_account_fragment() {
    local fragment_path="$1"
    local name="$2"
    local email="$3"
    local github_username="$4"
    local key_path="$5"

    git config --file "$fragment_path" user.name "$name"
    git config --file "$fragment_path" user.email "$email"
    git config --file "$fragment_path" github.username "$github_username"
    git config --file "$fragment_path" core.sshCommand \
        "ssh -i $key_path -o IdentitiesOnly=yes"
}

update_routing_file() {
    local account_id="$1"
    local scope="$2"

    local account_file="$GIT_ACCOUNTS_DIR/${account_id}.gitconfig"
    local routing_entry="    path = $account_file"
    local include_line="[includeIf \"gitdir:${scope}/\"]"

    if [ -f "$ROUTING_FILE" ] && grep -qxF "$include_line" "$ROUTING_FILE"; then
        die "el scope '$scope' ya está asociado a otra cuenta"
    fi

    if [ -f "$ROUTING_FILE" ] && grep -qxF "$routing_entry" "$ROUTING_FILE"; then
        return 0
    fi

    mkdir -p "$(dirname "$ROUTING_FILE")"
    local tmp
    tmp=$(mktemp "${ROUTING_FILE}.XXXXXX") || die "no se pudo crear temporal"
    {
        [ -f "$ROUTING_FILE" ] && cat "$ROUTING_FILE"
        printf '\n[includeIf "gitdir:%s/"]\n%s\n' \
            "$scope" "$routing_entry"
    } > "$tmp"
    chmod 600 "$tmp"
    mv -- "$tmp" "$ROUTING_FILE"
}

# === Verificación ===

verify_account() {
    local label="$1"
    local expected_username="$2"
    local key_path="$3"

    [ -f "$key_path" ] || die "no se encontró clave: $key_path"
    trust_github_host || die "no se pudieron verificar claves de host de GitHub"

    log_info "account.sh: verificando '$label' via ssh -T git@github.com"

    local ssh_output
    ssh_output=$(ssh \
        -i "$key_path" \
        -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=yes \
        -o ConnectTimeout=15 \
        -T git@github.com 2>&1) || true

    local pattern
    if [ -n "$expected_username" ]; then
        pattern="Hi[[:space:]]+${expected_username}![[:space:]]+You've[[:space:]]+successfully"
    else
        pattern="Hi[[:space:]]+[^!]+![[:space:]]+You've[[:space:]]+successfully"
    fi
    if [[ "$ssh_output" =~ $pattern ]]; then
        log_info "account.sh: '$label' verificada correctamente"
        printf '%s\n' "$ssh_output"
        return 0
    fi

    local sanitized
    sanitized=$(printf '%s' "$ssh_output" | grep -vE '(password|passphrase|secret)' | tr -d '\n' | cut -c1-200)
    die "verificación de '$label' fallida: ${sanitized:-sin respuesta}"
}

# === Comandos ===

show_primary_key() {
    [ -f "${PRIMARY_KEY}.pub" ] || die "no se encontró ${PRIMARY_KEY}.pub"
    printf '\nAgrega esta clave en GitHub → Settings → SSH and GPG keys:\n\n'
    cat "${PRIMARY_KEY}.pub"
    printf '\n\n'
}

cmd_setup_primary() {
    local email="${GITHUB_PRIMARY_EMAIL:-}"
    [ -n "$email" ] \
        || die "falta el correo de Git; vuelve a ejecutar install.sh para guardarlo"
    validate_email "$email"

    ensure_ssh_key "$PRIMARY_KEY" "$email"
    show_primary_key

    if [ ! -r /dev/tty ] || [ ! -t 0 ]; then
        log_info "account.sh: verifica después con: $0 verify primary"
        return 0
    fi

    local response
    read -r -p "¿Ya agregaste la clave a GitHub y deseas verificarla? [s/N]: " response </dev/tty
    case "$response" in
        s|S|si|SI|sí|Sí|y|Y|yes|YES)
            verify_account "primary" "" "$PRIMARY_KEY"
            ;;
        *)
            log_info "account.sh: verificación omitida"
            log_info "account.sh: ejecuta después: $0 verify primary"
            ;;
    esac
}

cmd_verify() {
    local id="${1:-}"
    [ -n "$id" ] || die "verify requiere un id"

    if [ "$id" = "primary" ]; then
        verify_account "primary" "" "$PRIMARY_KEY"
        return 0
    fi

    validate_id "$id"

    local fragment="$GIT_ACCOUNTS_DIR/$id.gitconfig"
    local key_path="$SSH_DIR/id_ed25519_${id}"

    [ -f "$fragment" ] || die "cuenta '$id' no encontrada: $fragment"
    [ -f "$key_path" ] || die "no se encontró clave SSH: $key_path"

    local username
    username=$(git config --file "$fragment" --get github.username 2>/dev/null) \
        || die "fragmento sin github.username"

    validate_github_username "$username"
    verify_account "$id" "$username" "$key_path"
}

cmd_list() {
    local found=0
    if [ -d "$GIT_ACCOUNTS_DIR" ]; then
        local f
        for f in "$GIT_ACCOUNTS_DIR"/*.gitconfig; do
            [ -f "$f" ] || continue
            local id email name
            id=$(basename "$f" .gitconfig)
            email=$(git config --file "$f" --get user.email 2>/dev/null || echo "?")
            name=$(git config --file "$f" --get user.name 2>/dev/null || echo "?")
            printf '%-20s %s  (%s)\n' "$id" "$email" "$name"
            found=1
        done
    fi
    if [ "$found" -eq 0 ]; then
        log_info "account.sh: no hay cuentas configuradas"
    fi
}

cmd_add() {
    local account_id="${1:-}"
    [ -n "$account_id" ] || die "add requiere un id"
    shift

    local name="" email="" username="" scope=""
    local ssh_key="$SSH_DIR/id_ed25519_${account_id}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                [ "$#" -ge 2 ] || die "--name requiere un valor"
                name="$2"
                shift 2
                ;;
            --email)
                [ "$#" -ge 2 ] || die "--email requiere un valor"
                email="$2"
                shift 2
                ;;
            --github-username)
                [ "$#" -ge 2 ] || die "--github-username requiere un valor"
                username="$2"
                shift 2
                ;;
            --scope)
                [ "$#" -ge 2 ] || die "--scope requiere un valor"
                scope="$2"
                shift 2
                ;;
            --help|-h) usage; exit 0 ;;
            *) die "opción desconocida: $1" ;;
        esac
    done

    [ -n "$name" ] || die "--name requerido"
    [ -n "$email" ] || die "--email requerido"
    [ -n "$username" ] || die "--github-username requerido"
    [ -n "$scope" ] || die "--scope requerido"

    validate_id "$account_id"
    validate_email "$email"
    validate_github_username "$username"
    scope=$(normalize_scope "$scope")
    mkdir -p "$scope" || die "no se pudo crear el scope '$scope'"

    local fragment="$GIT_ACCOUNTS_DIR/$account_id.gitconfig"

    if [ -e "$fragment" ]; then
        die "la cuenta '$account_id' ya existe"
    fi

    ensure_ssh_key "$ssh_key" "$email"

    mkdir -p "$GIT_ACCOUNTS_DIR"
    write_git_account_fragment "$fragment" "$name" "$email" "$username" "$ssh_key"
    chmod 600 "$fragment"
    update_routing_file "$account_id" "$scope"

    log_info "account.sh: cuenta '$account_id' configurada localmente"
    printf '\nAgrega esta clave pública a GitHub y luego ejecuta:\n'
    printf '    %s verify %s\n\n' "$0" "$account_id"
    cat "${ssh_key}.pub"
    printf '\n'
}

main() {
    load_primary_config

    if [ $# -lt 1 ]; then
        usage >&2
        exit 2
    fi

    local command="$1"
    shift

    case "$command" in
        setup-primary)
            [ $# -eq 0 ] || die "setup-primary no acepta argumentos"
            require_command ssh
            require_command ssh-keygen
            cmd_setup_primary
            ;;
        show-primary-key)
            [ $# -eq 0 ] || die "show-primary-key no acepta argumentos"
            show_primary_key
            ;;
        verify)
            [ $# -eq 1 ] || die "verify requiere exactamente un id"
            require_command ssh
            if [ "$1" != "primary" ]; then
                require_command git
                check_routing_include
            fi
            cmd_verify "$1"
            ;;
        add)
            require_command git
            require_command realpath
            require_command ssh
            require_command ssh-keygen
            check_routing_include
            cmd_add "$@"
            ;;
        list)
            [ $# -eq 0 ] || die "list no acepta argumentos"
            require_command git
            cmd_list
            ;;
        --help|-h|help)
            usage
            ;;
        *)
            die "comando desconocido '$command'"
            ;;
    esac
}

main "$@"
