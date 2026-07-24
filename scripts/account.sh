#!/bin/bash
# account.sh - CLI de gestión de cuentas GitHub.

set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=bootstrap/lib/log.sh
. "$REPO_ROOT/bootstrap/lib/log.sh"

# shellcheck source=bootstrap/lib/ssh.sh
. "$REPO_ROOT/bootstrap/lib/ssh.sh"

# shellcheck source=lib/github-accounts.sh
. "$REPO_ROOT/scripts/lib/github-accounts.sh"

readonly ACCOUNT_STATE_DIR="${DEV_ENV_STATE_DIR:-$HOME/.local/state/dev-env-bootstrap}"
readonly ACCOUNT_STAGING_DIR="$ACCOUNT_STATE_DIR/transactions"

ACTIVE_STAGING_PATH=""

cleanup_account_operation() {
    if [ -n "${ACTIVE_STAGING_PATH:-}" ]; then
        rm -rf -- "$ACTIVE_STAGING_PATH" 2>/dev/null || true
    fi

    lock_release 2>/dev/null || true
}

# Restore only the artifacts changed while activating a secondary account.
_rollback_secondary_activation() {
    local live_routing="$1" routing_backup="$2"
    local live_ssh_config="$3" ssh_config_backup="$4"
    local live_fragment="$5" fragment_backup="$6"
    local live_key="$7" key_backup="$8"
    local live_pub_key="$9" pub_key_backup="${10}"
    local key_was_generated="${11}"

    local restore_status=0
    local live_path backup_path
    local -a artifacts=(
        "$live_routing" "$routing_backup"
        "$live_ssh_config" "$ssh_config_backup"
        "$live_fragment" "$fragment_backup"
    )

    if [ "$key_was_generated" -eq 1 ]; then
        artifacts+=(
            "$live_key" "$key_backup"
            "$live_pub_key" "$pub_key_backup"
        )
    fi

    for ((i = 0; i < ${#artifacts[@]}; i += 2)); do
        live_path="${artifacts[i]}"
        backup_path="${artifacts[i + 1]}"
        if [ -e "$backup_path" ]; then
            mv -f -- "$backup_path" "$live_path" || restore_status=1
        else
            rm -f -- "$live_path" || restore_status=1
        fi
    done

    return "$restore_status"
}

usage() {
    cat <<EOF
Uso:
  account.sh setup-primary
  account.sh show-primary-key
  account.sh verify-primary
  account.sh add <id> [opciones]

Comandos:
  setup-primary     Genera o reutiliza la clave SSH primaria, muestra la clave
                    pública y permite verificarla contra GitHub.
  show-primary-key  Muestra la clave pública primaria.
  verify-primary    Verifica la autenticación SSH de la cuenta primaria.
  add               Agrega una cuenta secundaria de GitHub.

Opciones requeridas para add:
  --name         Nombre para commits Git de la cuenta
  --email        Dirección de email de GitHub
  --github-login Login de GitHub que debe autenticar la clave SSH
  --ssh-key      Ruta a la clave SSH privada
  --ssh-alias    Alias SSH para esta cuenta
  --scope        Scope gitdir para enrutamiento (ruta absoluta)

El id 'primary' está reservado y no puede ser usado con add.

Ejemplos:
  account.sh setup-primary

  account.sh add acme1 --name "Jane" --email "jane@acme.test" --github-login jane-acme \\
    --ssh-key ~/.ssh/id_acme --ssh-alias gh-acme1 --scope /srv/repos/acme
EOF
}
# parse_add_options <id> <args...>: salida stdout = 6 lineas (name, email, github_login, ssh_key, ssh_alias, scope).
parse_add_options() {
    local id="$1"
    shift

    local name="" email="" github_login="" ssh_key="" ssh_alias="" scope=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                [ "$#" -ge 2 ] || die "account.sh: --name requiere un valor"
                name="$2"
                shift 2
                ;;
            --email)
                [ "$#" -ge 2 ] || die "account.sh: --email requiere un valor"
                email="$2"
                shift 2
                ;;
            --github-login)
                [ "$#" -ge 2 ] || die "account.sh: --github-login requiere un valor"
                github_login="$2"
                shift 2
                ;;
            --ssh-key)
                [ "$#" -ge 2 ] || die "account.sh: --ssh-key requiere un valor"
                ssh_key="$2"
                shift 2
                ;;
            --ssh-alias)
                [ "$#" -ge 2 ] || die "account.sh: --ssh-alias requiere un valor"
                ssh_alias="$2"
                shift 2
                ;;
            --scope)
                [ "$#" -ge 2 ] || die "account.sh: --scope requiere un valor"
                scope="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Opción desconocida: $1"
                ;;
        esac
    done

    if [ "$id" = "primary" ]; then
        die "primary está reservado"
    fi

    if [ -z "$name" ] || [ -z "$email" ] || [ -z "$github_login" ] || [ -z "$ssh_key" ] || [ -z "$ssh_alias" ] || [ -z "$scope" ]; then
        die "account.sh: opción requerida faltante"
    fi

    printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$name" "$email" "$github_login" "$ssh_key" "$ssh_alias" "$scope"
}

# _reject_alias_conflict <state-json> <alias> <account-id>
# State must already have passed validate_schema.
_reject_alias_conflict() {
    local current_state="$1"
    local ssh_alias="$2"
    local account_id="$3"
    local new_alias_lower existing

    new_alias_lower=$(printf '%s\n' "$ssh_alias" | tr '[:upper:]' '[:lower:]')
    existing=$(printf '%s\n' "$current_state" | jq -r --arg alias "$new_alias_lower" --arg id "$account_id" \
        '.secondary_accounts[] | select((.ssh_alias | ascii_downcase) == $alias and .id != $id) | .id' \
        2>/dev/null || true)
    if [ -n "$existing" ]; then
        die "account.sh: alias '$ssh_alias' ya está en uso por cuenta '$existing'"
    fi
}

# _normalize_key_path <key>: resolve '..', symlinks y ~ expansion.
_normalize_key_path() {
    local key="$1"

    case "$key" in
        "~")
            key="$HOME"
            ;;
        "~/"*)
            key="$HOME/${key#~/}"
            ;;
    esac

    realpath -m -- "$key"
}

# _get_key_fingerprint <key>: huella (vacío si no se encuentra key.pub).
_get_key_fingerprint() {
    local key="$1"
    local pub_key="${key}.pub"
    if [ ! -f "$pub_key" ]; then
        echo ""
        return
    fi
    ssh-keygen -lf "$pub_key" 2>/dev/null | awk '{print $2}' || echo ""
}

# _do_add_secondary: lock ya adquirido, validación completa.
_do_add_secondary() {
    local account_id="$1"
    local name="$2"
    local email="$3"
    local github_login="$4"
    local ssh_key="$5"
    local ssh_alias="$6"
    local scope="$7"

    ssh_key=$(_normalize_key_path "$ssh_key")

    local txn_id
    txn_id=$(cat /proc/sys/kernel/random/uuid) \
      || die "no se pudo generar un identificador único"
    local staging_path="${ACCOUNT_STAGING_DIR}/${txn_id}"
    ACTIVE_STAGING_PATH="$staging_path"

    _ensure_jq
    init_state
    local current_state
    current_state=$(read_state)
    _reject_alias_conflict "$current_state" "$ssh_alias" "$account_id"

    local existing_account
    existing_account=$(echo "$current_state" | jq -r --arg id "$account_id" \
        '.secondary_accounts[] | select(.id == $id)' 2>/dev/null || echo "")

    if [ -n "$existing_account" ] && [ "$existing_account" != "null" ]; then
        local existing_name existing_email existing_login existing_key existing_alias existing_scope
        existing_name=$(echo "$existing_account" | jq -r '.name')
        existing_email=$(echo "$existing_account" | jq -r '.email')
        existing_login=$(echo "$existing_account" | jq -r '.github_login // empty')
        existing_key=$(echo "$existing_account" | jq -r '.ssh_key')
        existing_alias=$(echo "$existing_account" | jq -r '.ssh_alias')
        existing_scope=$(echo "$existing_account" | jq -r '.scope')

        existing_key=$(_normalize_key_path "$existing_key")
        existing_scope=$(normalize_scope "$existing_scope")
        local normalized_scope
        normalized_scope=$(normalize_scope "$scope")

        if [ "$existing_name" = "$name" ] && \
           [ "$existing_email" = "$email" ] && \
           [ "$existing_login" = "$github_login" ] && \
           [ "$existing_key" = "$ssh_key" ] && \
           [ "$existing_alias" = "$ssh_alias" ] && \
           [ "$existing_scope" = "$normalized_scope" ]; then
            log_info "account.sh: cuenta '$account_id' ya existe con payload idéntico (no-op)"
            lock_release
            exit 0
        else
            die "account.sh: cuenta '$account_id' existe con payload diferente"
        fi
    fi

    local secondaries_json
    secondaries_json=$(echo "$current_state" | jq '.secondary_accounts' 2>/dev/null || echo "[]")
    local sec_count
    sec_count=$(echo "$secondaries_json" | jq 'length' 2>/dev/null || echo "0")

    if [ "$sec_count" -gt 0 ]; then
        local normalized_scope
        normalized_scope=$(normalize_scope "$scope")
        local i=0
        while [ "$i" -lt "$sec_count" ]; do
            local existing_scope
            existing_scope=$(echo "$secondaries_json" | jq -r ".[$i].scope")
            existing_scope=$(normalize_scope "$existing_scope")
            if ! validate_scope_non_overlap "$normalized_scope" "$existing_scope" 2>/dev/null; then
                die "account.sh: solapamiento de scope rechazado: '$scope' vs '$existing_scope'"
            fi
            i=$((i + 1))
        done
    fi

    mkdir -p "$staging_path"
    chmod 700 "$staging_path"

    local key_was_generated=0
    local live_key_path=""

    if [ -f "$ssh_key" ]; then
        if [ ! -f "${ssh_key}.pub" ]; then
            die "account.sh: clave en '$ssh_key' existe pero falta .pub (par incompleto)"
        fi

        local existing_fp
        existing_fp=$(_get_key_fingerprint "$ssh_key")
        if [ -z "$existing_fp" ]; then
            die "account.sh: clave en '$ssh_key' existe pero no es una clave SSH válida"
        fi

        log_info "account.sh: reutilizando clave existente en '$ssh_key' (huella: ${existing_fp:0:16}...)"
        cp "$ssh_key" "${staging_path}/id_${account_id}"
        cp "${ssh_key}.pub" "${staging_path}/id_${account_id}.pub"
        live_key_path="$ssh_key"
    else
        key_was_generated=1
        local staging_key="${staging_path}/id_${account_id}"

        # Modo interactivo: abrir /dev/tty para ssh-keygen. Subshell aísla fd 3.
        if ! (
            if ! exec 3</dev/tty 2>/dev/null; then
                die "account.sh: /dev/tty no disponible; ejecute desde una terminal interactiva"
            fi
            if ! ssh-keygen -t ed25519 -f "$staging_key" -C "$account_id" <&3 2>/dev/null; then
                die "account.sh: falló al generar clave SSH"
            fi
        ); then
            rm -rf "$staging_path"
            lock_release
            exit 1
        fi
        exec 3<&- 2>/dev/null || true

        live_key_path="$staging_key"
        log_info "account.sh: generada nueva clave SSH en '$staging_key'"
    fi

    chmod 600 "${staging_path}/id_${account_id}" 2>/dev/null || true

    # Si la clave es existente, live_key_path ya contiene la ruta final.
    # Si fue generada, la ruta final es ~/.ssh/id_<account_id>.
    if [ "$key_was_generated" -eq 1 ]; then
        live_key_path="${HOME}/.ssh/id_${account_id}"
    fi

    local staging_fragment="${staging_path}/${account_id}.gitconfig"
    git config --file "$staging_fragment" user.name "$name"
    git config --file "$staging_fragment" user.email "$email"
    git config --file "$staging_fragment" core.sshCommand "ssh -o IdentitiesOnly=yes"
    git config --file "$staging_fragment" "url.git@${ssh_alias}:.insteadOf" "git@github.com:"
    log_info "account.sh: fragmento gitconfig preparado en '$staging_fragment'"

    local staging_ssh_dir="${staging_path}/.ssh.d"
    local staging_ssh_config="${staging_ssh_dir}/${account_id}.ssh.config"
    mkdir -p "$staging_ssh_dir"
    cat > "$staging_ssh_config" << EOF
Host ${ssh_alias}
    HostName github.com
    User git
    IdentityFile ${live_key_path}
    IdentitiesOnly yes
EOF
    log_info "account.sh: configuración SSH preparada en '$staging_ssh_config'"

    local staging_routing="${staging_path}/accounts-routing.gitconfig"
    local live_routing="${HOME}/.config/git/accounts-routing.gitconfig"
    if [ -f "$live_routing" ]; then
        cp "$live_routing" "$staging_routing"
    else
        : > "$staging_routing"
    fi

    local normalized_scope
    normalized_scope=$(normalize_scope "$scope")
    echo "" >> "$staging_routing"
    echo "[includeIf \"gitdir:${normalized_scope}/\"]" >> "$staging_routing"
    echo "    path = ${HOME}/.config/git/accounts/${account_id}.gitconfig" >> "$staging_routing"
    log_info "account.sh: includeIf de enrutamiento preparado para scope '$normalized_scope'"

    local pub_key="${staging_path}/id_${account_id}.pub"
    echo ""
    echo "========================================"
    echo "Agregar esta clave en Configuración de GitHub → SSH and GPG keys → Nueva clave SSH"
    echo ""

    cat "$pub_key"

    echo ""
    echo "Esperando confirmación..."

    while true; do
        printf '¿Proceder con agregar esta clave a GitHub? (y/Y/yes/YES): '
        read -r response || {
            die "account.sh: falló en read"
        }
        case "$response" in
            y|Y|yes|YES)
                break
                ;;
            *)
                die "account.sh: confirmación rechazada"
                ;;
        esac
    done

    log_info "account.sh: verificando auth para alias '$ssh_alias'"
    trust_github_host || \
        die "account.sh: no se pudieron verificar las claves de host de GitHub"

    local ssh_output
    ssh_output=$(ssh -F "$staging_ssh_config" \
        -o UserKnownHostsFile="${HOME}/.ssh/known_hosts" \
        -o StrictHostKeyChecking=yes \
        -T "git@${ssh_alias}" 2>&1) || true

    if _matches_github_ssh_greeting "$github_login" "$ssh_output"; then
        log_info "account.sh: verificación de auth exitosa para alias '$ssh_alias'"
    else
        ssh_output=$(echo "$ssh_output" | grep -vE '(password|passphrase|key|secret)' | tr -d '\n' | cut -c1-200)
        die "account.sh: verificación de auth fallida para alias '$ssh_alias': ${ssh_output:-connection refused}"
    fi

    # Activate every Git artifact before making the account visible in state.
    mkdir -p "${HOME}/.ssh"
    mkdir -p "${HOME}/.ssh.d/accounts"
    mkdir -p "${HOME}/.config/git/accounts"
    mkdir -p "$(dirname "$STATE_FILE")"

    local live_ssh_config="${HOME}/.ssh.d/accounts/${account_id}.ssh.config"
    local live_fragment="${HOME}/.config/git/accounts/${account_id}.gitconfig"
    local rollback_path="${staging_path}/rollback"
    local routing_backup="${rollback_path}/accounts-routing.gitconfig"
    local ssh_config_backup="${rollback_path}/${account_id}.ssh.config"
    local fragment_backup="${rollback_path}/${account_id}.gitconfig"
    local key_backup="${rollback_path}/id_${account_id}"
    local pub_key_backup="${rollback_path}/id_${account_id}.pub"

    mkdir -p "$rollback_path"
    [ ! -e "$live_routing" ] || cp -p -- "$live_routing" "$routing_backup"
    [ ! -e "$live_ssh_config" ] || cp -p -- "$live_ssh_config" "$ssh_config_backup"
    [ ! -e "$live_fragment" ] || cp -p -- "$live_fragment" "$fragment_backup"

    if [ "$key_was_generated" -eq 1 ]; then
        mkdir -p "$(dirname "$live_key_path")"
        [ ! -e "$live_key_path" ] || cp -p -- "$live_key_path" "$key_backup"
        [ ! -e "${live_key_path}.pub" ] || cp -p -- "${live_key_path}.pub" "$pub_key_backup"
    fi

    # Each failure restores only artifacts this activation may have replaced.
    if ! mv -- "$staging_routing" "$live_routing"; then
        _rollback_secondary_activation "$live_routing" "$routing_backup" \
            "$live_ssh_config" "$ssh_config_backup" "$live_fragment" "$fragment_backup" \
            "$live_key_path" "$key_backup" "${live_key_path}.pub" "$pub_key_backup" "$key_was_generated" || \
            log_error "account.sh: no se pudo restaurar la activación fallida"
        die "account.sh: no se pudo activar el enrutamiento Git"
    fi
    log_info "account.sh: enrutamiento activado (includeIf)"

    if [ "$key_was_generated" -eq 1 ]; then
        if ! mv -- "${staging_path}/id_${account_id}" "$live_key_path" || \
           ! mv -- "${staging_path}/id_${account_id}.pub" "${live_key_path}.pub"; then
            _rollback_secondary_activation "$live_routing" "$routing_backup" \
                "$live_ssh_config" "$ssh_config_backup" "$live_fragment" "$fragment_backup" \
                "$live_key_path" "$key_backup" "${live_key_path}.pub" "$pub_key_backup" "$key_was_generated" || \
                log_error "account.sh: no se pudo restaurar la activación fallida"
            die "account.sh: no se pudo activar la clave SSH"
        fi
        chmod 600 "$live_key_path" 2>/dev/null || true
        log_info "account.sh: clave activada en '$live_key_path'"
    fi

    if ! mv -- "$staging_ssh_config" "$live_ssh_config"; then
        _rollback_secondary_activation "$live_routing" "$routing_backup" \
            "$live_ssh_config" "$ssh_config_backup" "$live_fragment" "$fragment_backup" \
            "$live_key_path" "$key_backup" "${live_key_path}.pub" "$pub_key_backup" "$key_was_generated" || \
            log_error "account.sh: no se pudo restaurar la activación fallida"
        die "account.sh: no se pudo activar la configuración SSH"
    fi
    log_info "account.sh: configuración SSH activada"

    if ! mv -- "$staging_fragment" "$live_fragment"; then
        _rollback_secondary_activation "$live_routing" "$routing_backup" \
            "$live_ssh_config" "$ssh_config_backup" "$live_fragment" "$fragment_backup" \
            "$live_key_path" "$key_backup" "${live_key_path}.pub" "$pub_key_backup" "$key_was_generated" || \
            log_error "account.sh: no se pudo restaurar la activación fallida"
        die "account.sh: no se pudo activar el fragmento gitconfig"
    fi
    log_info "account.sh: fragmento gitconfig activado"

    local new_secondary_entry
    new_secondary_entry=$(jq -n \
        --arg id "$account_id" \
        --arg name "$name" \
        --arg email "$email" \
        --arg login "$github_login" \
        --arg key "$live_key_path" \
        --arg alias "$ssh_alias" \
        --arg sc "$normalized_scope" \
        '{
            id: $id,
            name: $name,
            email: $email,
            github_login: $login,
            ssh_key: $key,
            ssh_alias: $alias,
            scope: $sc
        }')

    local updated_state
    updated_state=$(echo "$current_state" | jq --argjson entry "$new_secondary_entry" \
        '.secondary_accounts += [$entry]')
    if ! write_state "$updated_state"; then
        _rollback_secondary_activation "$live_routing" "$routing_backup" \
            "$live_ssh_config" "$ssh_config_backup" "$live_fragment" "$fragment_backup" \
            "$live_key_path" "$key_backup" "${live_key_path}.pub" "$pub_key_backup" "$key_was_generated" || \
            log_error "account.sh: no se pudo restaurar la activación fallida"
        die "account.sh: no se pudo activar el estado de la cuenta"
    fi
    log_info "account.sh: estado actualizado con nueva cuenta secundaria"

    rm -rf -- "$staging_path" 2>/dev/null || true
    ACTIVE_STAGING_PATH=""

    lock_release

    log_info "account.sh: cuenta secundaria '$account_id' agregada exitosamente"
    exit 0
}



_read_chezmoi_data_value() {
    local key="$1"
    local config_file="${HOME}/.config/chezmoi/chezmoi.toml"

    [ -f "$config_file" ] || return 1

    awk -v requested_key="$key" '
        /^[[:space:]]*\[[[:space:]]*data[[:space:]]*\][[:space:]]*(#.*)?$/ {
            in_data = 1
            next
        }
        /^[[:space:]]*\[/ {
            in_data = 0
        }
        in_data && $0 ~ "^[[:space:]]*" requested_key "[[:space:]]*=" {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*#.*$/, "", value)
            sub(/^"/, "", value)
            sub(/"$/, "", value)
            print value
            exit
        }
    ' "$config_file"
}

_primary_key_path() {
    local key_path="${GITHUB_PRIMARY_SSH_KEY:-}"

    if [ -z "$key_path" ]; then
        key_path="$(_read_chezmoi_data_value primary_ssh_key 2>/dev/null || true)"
    fi

    if [ -z "$key_path" ]; then
        key_path="${HOME}/.ssh/id_ed25519"
    fi

    key_path="${key_path/#\~/$HOME}"
    printf '%s\n' "$key_path"
}

_primary_email() {
    local email="${GITHUB_PRIMARY_EMAIL:-}"

    if [ -z "$email" ]; then
        email="$(_read_chezmoi_data_value git_user_email 2>/dev/null || true)"
    fi

    if [ -z "$email" ]; then
        die "account.sh: no se encontró git_user_email en chezmoi.toml"
    fi

    printf '%s\n' "$email"
}

_primary_name() {
    local name="${GITHUB_PRIMARY_NAME:-}"

    if [ -z "$name" ]; then
        name="$(_read_chezmoi_data_value git_user_name 2>/dev/null || true)"
    fi

    if [ -z "$name" ]; then
        die "account.sh: no se encontró git_user_name en chezmoi.toml"
    fi

    printf '%s\n' "$name"
}

_primary_github_login() {
    local login="${GITHUB_PRIMARY_LOGIN:-}"

    if [ -z "$login" ]; then
        login="$(_read_chezmoi_data_value github_login 2>/dev/null || true)"
    fi

    if [ -z "$login" ]; then
        die "account.sh: defina GITHUB_PRIMARY_LOGIN o data.github_login en chezmoi.toml"
    fi

    validate_github_login "$login" || die "account.sh: login primario de GitHub inválido"
    printf '%s\n' "$login"
}

# _matches_github_ssh_greeting <login> <ssh_output>
# GitHub's SSH endpoint identifies the authenticated login in its greeting.
_matches_github_ssh_greeting() {
    local login="$1"
    local ssh_output="$2"

    [[ "$ssh_output" =~ Hi[[:space:]]+${login}\![[:space:]]+You\'ve[[:space:]]+successfully[[:space:]]+authenticated ]]
}

_ensure_primary_key() {
    local key_path email fingerprint
    key_path="$(_primary_key_path)"
    email="$(_primary_email)"

    mkdir -p "$(dirname "$key_path")"
    chmod 700 "$(dirname "$key_path")"

    if [ -f "$key_path" ]; then
        [ -f "${key_path}.pub" ] || \
            die "account.sh: existe $key_path pero falta ${key_path}.pub"

        fingerprint="$(_get_key_fingerprint "$key_path")"
        [ -n "$fingerprint" ] || \
            die "account.sh: $key_path no es una clave SSH válida"

        log_info "account.sh: reutilizando clave primaria (huella: ${fingerprint:0:16}...)"
        return 0
    fi

    [ ! -e "${key_path}.pub" ] || \
        die "account.sh: existe ${key_path}.pub sin su clave privada"
    [ -r /dev/tty ] || \
        die "account.sh: se requiere una terminal interactiva para ssh-keygen"

    log_info "account.sh: generando clave primaria en '$key_path'"
    ssh-keygen -t ed25519 -f "$key_path" -C "$email" </dev/tty || \
        die "account.sh: falló al generar la clave primaria"

    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
}

show_primary_key() {
    local key_path
    key_path="$(_primary_key_path)"

    [ -f "${key_path}.pub" ] || \
        die "account.sh: no se encontró ${key_path}.pub"

    printf '\nAgrega esta clave en GitHub → Settings → SSH and GPG keys:\n\n'
    cat "${key_path}.pub"
    printf '\n\n'
}

verify_primary() {
    local key_path github_login ssh_output
    key_path="$(_primary_key_path)"
    github_login="$(_primary_github_login)"

    [ -f "$key_path" ] || \
        die "account.sh: no se encontró la clave primaria: $key_path"

    log_info "account.sh: verificando autenticación de la cuenta primaria"
    trust_github_host || \
        die "account.sh: no se pudieron verificar las claves de host de GitHub"

    ssh_output=$(ssh \
        -i "$key_path" \
        -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=yes \
        -o ConnectTimeout=15 \
        -T git@github.com 2>&1) || true

    if _matches_github_ssh_greeting "$github_login" "$ssh_output"; then
        log_info "account.sh: autenticación primaria verificada"
        printf '%s\n' "$ssh_output"
        return 0
    fi

    ssh_output=$(echo "$ssh_output" | \
        grep -vE '(password|passphrase|secret)' | tr -d '\n' | cut -c1-200)
    die "account.sh: autenticación primaria fallida: ${ssh_output:-sin respuesta}"
}

register_primary() {
    local name email github_login key_path staging_path

    name="$(_primary_name)"
    email="$(_primary_email)"
    github_login="$(_primary_github_login)"
    key_path="$(_primary_key_path)"
    staging_path="${ACCOUNT_STAGING_DIR}/primary-$$"

    lock_acquire "$staging_path" || \
        die "account.sh: otra operación de cuentas está en progreso"

    if ! set_primary "$name" "$email" "$key_path" "$github_login"; then
        lock_release
        die "account.sh: no se pudo registrar la cuenta primaria"
    fi

    lock_release
    log_info "account.sh: cuenta primaria registrada"
}

setup_primary() {
    local response=""

    command -v ssh >/dev/null 2>&1 || die "ssh es requerido"
    command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen es requerido"

    init_state
    _ensure_primary_key
    show_primary_key

    if [ ! -r /dev/tty ]; then
        log_info "account.sh: verifica después con: $0 verify-primary"
        return 0
    fi

    read -r -p "¿Ya agregaste la clave a GitHub y deseas verificarla? [s/N]: " \
        response </dev/tty

    case "$response" in
        s|S|si|SI|sí|Sí)
            verify_primary
            register_primary
            ;;
        *)
            log_info "account.sh: verificación omitida"
            log_info "account.sh: ejecuta después: $0 verify-primary"
            ;;
    esac
}

main() {
    if [ $# -lt 1 ]; then
        usage >&2
        exit 2
    fi

    local command="$1"
    shift

    case "$command" in
        setup-primary)
            [ $# -eq 0 ] || die "account.sh: setup-primary no acepta argumentos"
            setup_primary
            ;;
        show-primary-key)
            [ $# -eq 0 ] || die "account.sh: show-primary-key no acepta argumentos"
            show_primary_key
            ;;
        verify-primary)
            [ $# -eq 0 ] || die "account.sh: verify-primary no acepta argumentos"
            verify_primary
            register_primary
            ;;
        add)
            if [ $# -ge 1 ] && { [ "$1" = "--help" ] || [ "$1" = "-h" ]; }; then
                usage
                exit 0
            fi
            if [ $# -lt 1 ]; then
                die "account.sh: id de cuenta faltante"
            fi

            local account_id="$1"
            shift

            local parsed
            parsed=$(parse_add_options "$account_id" "$@")
            local name email github_login ssh_key ssh_alias scope
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$parsed"
            name="${lines[0]:-}"
            email="${lines[1]:-}"
            github_login="${lines[2]:-}"
            ssh_key="${lines[3]:-}"
            ssh_alias="${lines[4]:-}"
            scope="${lines[5]:-}"

            validate_id "$account_id" || exit 1
            validate_email "$email" || exit 1
            validate_github_login "$github_login" || exit 1
            validate_key_path "$ssh_key" || exit 1
            validate_alias "$ssh_alias" || exit 1
            validate_scope "$scope" || exit 1

            if [ -f "$STATE_FILE" ]; then
                _ensure_jq
                _reject_alias_conflict "$(cat "$STATE_FILE")" "$ssh_alias" "$account_id"
            fi

            if [ -d "$LOCK_FILE" ]; then
                die "account.sh: el lock ya está en uso"
            fi

            local staging_path="${ACCOUNT_STAGING_DIR}/$$"
            lock_acquire "$staging_path" || \
                die "account.sh: no se pudo adquirir bloqueo (otra operación en progreso)"

            trap cleanup_account_operation EXIT

            _do_add_secondary \
                "$account_id" "$name" "$email" "$github_login" "$ssh_key" "$ssh_alias" "$scope"
            ;;
        --help|-h|help)
            usage
            ;;
        *)
            die "account.sh: comando desconocido '$command'"
            ;;
    esac
}

main "$@"
