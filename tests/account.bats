#!/usr/bin/env bats
# Cobertura de integridad para el alta de cuentas secundarias.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_HOME="$(mktemp -d)"
  TEST_STATE_DIR="$(mktemp -d)"
  TEST_BIN="$(mktemp -d)"

  mkdir -p "$TEST_HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -f "$TEST_HOME/.ssh/id_acme"

  cat > "$TEST_BIN/ssh" <<'EOF'
#!/bin/sh
if [ -n "${SSH_CALLED_MARKER:-}" ]; then
  : > "$SSH_CALLED_MARKER"
fi
printf '%s\n' "${SSH_GREETING:-Hi acme! You've successfully authenticated, but GitHub does not provide shell access.}"
EOF
  chmod +x "$TEST_BIN/ssh"

  cat > "$TEST_BIN/mv" <<'EOF'
#!/bin/bash
destination="${!#}"
if [ "${FAIL_ROUTING_MV_ONCE:-}" = "1" ] && \
   [ "$destination" = "$HOME/.config/git/accounts-routing.gitconfig" ] && \
   [ ! -e "$MV_FAILURE_MARKER" ]; then
  : > "$MV_FAILURE_MARKER"
  /bin/mv "$@"
  exit 1
fi
exec /bin/mv "$@"
EOF
  chmod +x "$TEST_BIN/mv"

  cat > "$TEST_BIN/ssh-keyscan" <<'EOF'
#!/bin/sh
[ -z "${GITHUB_HOST_TRUST_MARKER:-}" ] || : > "$GITHUB_HOST_TRUST_MARKER"
cat <<'KEYS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
KEYS
EOF
  chmod +x "$TEST_BIN/ssh-keyscan"
}

teardown() {
  rm -rf "$TEST_HOME" "$TEST_STATE_DIR" "$TEST_BIN"
}

@test "account add initializes valid state before writing the first secondary account" {
  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" PATH="$TEST_BIN:$PATH" \
    GITHUB_HOST_TRUST_MARKER="$TEST_HOME/github-host-trusted" \
    bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-login acme \
    --ssh-key "$TEST_HOME/.ssh/id_acme" \
    --ssh-alias gh-acme \
    --scope "$TEST_HOME/repos/acme" <<< "y"

  [ "$status" -eq 0 ]
  [ -e "$TEST_HOME/github-host-trusted" ]
  run jq -e '
    .schema_version == 1 and
    (.primary_accounts | type == "array") and
    (.secondary_accounts | length == 1) and
    .secondary_accounts[0].id == "acme" and
    .secondary_accounts[0].github_login == "acme"
  ' "$TEST_STATE_DIR/github-accounts.json"
  [ "$status" -eq 0 ]
}

@test "verify-primary trusts the GitHub host before authenticating" {
  run env HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" \
    GITHUB_PRIMARY_SSH_KEY="$TEST_HOME/.ssh/id_acme" \
    GITHUB_PRIMARY_LOGIN="acme" \
    GITHUB_PRIMARY_NAME="Acme User" \
    GITHUB_PRIMARY_EMAIL="acme@example.test" \
    GITHUB_HOST_TRUST_MARKER="$TEST_HOME/github-host-trusted" \
    bash "$REPO_ROOT/scripts/account.sh" verify-primary

  [ "$status" -eq 0 ]
  [ -e "$TEST_HOME/github-host-trusted" ]
}

@test "verify-primary reads identity values only from the Chezmoi data table" {
  mkdir -p "$TEST_HOME/.config/chezmoi"
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.toml" <<EOF
git_user_name = "Wrong Name"
git_user_email = "wrong@example.test"
primary_ssh_key = "/missing/key"

[data]
git_user_name = "Acme User"
git_user_email = "acme@example.test"
primary_ssh_key = "$TEST_HOME/.ssh/id_acme"
github_login = "acme"
EOF

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" PATH="$TEST_BIN:$PATH" \
    bash "$REPO_ROOT/scripts/account.sh" verify-primary

  [ "$status" -eq 0 ]
  run jq -e --arg key "$TEST_HOME/.ssh/id_acme" \
    '.primary_accounts[0] | .name == "Acme User" and .email == "acme@example.test" and .ssh_key == $key' \
    "$TEST_STATE_DIR/github-accounts.json"
  [ "$status" -eq 0 ]
}

@test "account add rejects an SSH key authenticated as a different GitHub login" {
  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" PATH="$TEST_BIN:$PATH" \
    SSH_GREETING="Hi other-account! You've successfully authenticated, but GitHub does not provide shell access." \
    bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-login acme \
    --ssh-key "$TEST_HOME/.ssh/id_acme" \
    --ssh-alias gh-acme \
    --scope "$TEST_HOME/repos/acme" <<< "y"

  [ "$status" -ne 0 ]
  [[ "$output" == *"verificación de auth fallida"* ]]
  run jq -e '.secondary_accounts | length == 0' "$TEST_STATE_DIR/github-accounts.json"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/.config/git/accounts/acme.gitconfig" ]
}

@test "account add restores routing and keeps state inactive when routing activation fails" {
  mkdir -p "$TEST_HOME/.config/git/accounts" "$TEST_HOME/.ssh.d/accounts"
  cat > "$TEST_HOME/.config/git/accounts-routing.gitconfig" <<EOF
[includeIf "gitdir:$TEST_HOME/repos/existing/"]
    path = $TEST_HOME/.config/git/accounts/existing.gitconfig
EOF
  cat > "$TEST_HOME/.config/git/accounts/existing.gitconfig" <<'EOF'
[user]
    name = Existing User
EOF
  cat > "$TEST_HOME/.ssh.d/accounts/existing.ssh.config" <<'EOF'
Host gh-existing
    HostName github.com
EOF
  cat > "$TEST_STATE_DIR/github-accounts.json" <<EOF
{"schema_version":1,"primary_accounts":[],"secondary_accounts":[{"id":"existing","name":"Existing User","email":"existing@example.test","github_login":"existing","ssh_key":"$TEST_HOME/.ssh/id_acme","ssh_alias":"gh-existing","scope":"$TEST_HOME/repos/existing"}]}
EOF
  local routing_before fragment_before ssh_config_before key_before pub_key_before
  routing_before="$(<"$TEST_HOME/.config/git/accounts-routing.gitconfig")"
  fragment_before="$(<"$TEST_HOME/.config/git/accounts/existing.gitconfig")"
  ssh_config_before="$(<"$TEST_HOME/.ssh.d/accounts/existing.ssh.config")"
  key_before="$(<"$TEST_HOME/.ssh/id_acme")"
  pub_key_before="$(<"$TEST_HOME/.ssh/id_acme.pub")"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" PATH="$TEST_BIN:$PATH" \
    FAIL_ROUTING_MV_ONCE=1 MV_FAILURE_MARKER="$TEST_HOME/routing-mv-failed" \
    bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-login acme \
    --ssh-key "$TEST_HOME/.ssh/id_acme" \
    --ssh-alias gh-acme \
    --scope "$TEST_HOME/repos/acme" <<< "y"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no se pudo activar el enrutamiento Git"* ]]
  run jq -e '.secondary_accounts | length == 1 and .[0].id == "existing"' "$TEST_STATE_DIR/github-accounts.json"
  [ "$status" -eq 0 ]
  [ "$(<"$TEST_HOME/.config/git/accounts-routing.gitconfig")" = "$routing_before" ]
  [ "$(<"$TEST_HOME/.config/git/accounts/existing.gitconfig")" = "$fragment_before" ]
  [ "$(<"$TEST_HOME/.ssh.d/accounts/existing.ssh.config")" = "$ssh_config_before" ]
  [ "$(<"$TEST_HOME/.ssh/id_acme")" = "$key_before" ]
  [ "$(<"$TEST_HOME/.ssh/id_acme.pub")" = "$pub_key_before" ]
  [ ! -e "$TEST_HOME/.config/git/accounts/acme.gitconfig" ]
  [ ! -e "$TEST_HOME/.ssh.d/accounts/acme.ssh.config" ]
}

@test "account add writes quoted Git identity values without config injection" {
  local git_name='Acme "Builder"'
  local git_email='acme"quoted"@example.test'

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" PATH="$TEST_BIN:$PATH" \
    bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "$git_name" \
    --email "$git_email" \
    --github-login acme \
    --ssh-key "$TEST_HOME/.ssh/id_acme" \
    --ssh-alias gh-acme \
    --scope "$TEST_HOME/repos/acme" <<< "y"

  [ "$status" -eq 0 ]
  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get user.name
  [ "$status" -eq 0 ]
  [ "$output" = "$git_name" ]
  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get user.email
  [ "$status" -eq 0 ]
  [ "$output" = "$git_email" ]
  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get include.path
  [ "$status" -ne 0 ]
}

@test "write_state rejects JSON that does not satisfy the account schema" {
  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash -c '. "$1/scripts/lib/github-accounts.sh"; write_state "{\"secondary_accounts\": []}"' \
    bash "$REPO_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"estado no cumple el esquema"* ]]
  [ ! -e "$TEST_STATE_DIR/github-accounts.json" ]
}

@test "account add preserves invalid existing state without activation or persistence" {
  local malformed_state duplicate_state
  malformed_state='{"schema_version":1,"primary_accounts":[],"secondary_accounts":['
  duplicate_state='{"schema_version":1,"primary_accounts":[],"secondary_accounts":[{"id":"acme","name":"Acme","email":"acme@example.test","github_login":"acme","ssh_key":"/tmp/acme","ssh_alias":"gh-acme","scope":"/tmp/acme"},{"id":"acme","name":"Other","email":"other@example.test","github_login":"other","ssh_key":"/tmp/other","ssh_alias":"gh-other","scope":"/tmp/other"}]}'

  for state in "$malformed_state" "$duplicate_state"; do
    printf '%s\n' "$state" > "$TEST_STATE_DIR/github-accounts.json"
    local state_before
    state_before="$(<"$TEST_STATE_DIR/github-accounts.json")"

    run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" PATH="$TEST_BIN:$PATH" \
      SSH_CALLED_MARKER="$TEST_HOME/ssh-called" \
      bash "$REPO_ROOT/scripts/account.sh" add acme \
      --name "Acme User" \
      --email "acme@example.test" \
      --github-login acme \
      --ssh-key "$TEST_HOME/.ssh/id_acme" \
      --ssh-alias gh-acme \
      --scope "$TEST_HOME/repos/acme" <<< "y"

    [ "$status" -ne 0 ]
    [[ "$output" == *"archivo de estado existente no es válido; no se modificó"* ]]
    [ "$(<"$TEST_STATE_DIR/github-accounts.json")" = "$state_before" ]
    [ ! -e "$TEST_HOME/ssh-called" ]
    [ ! -e "$TEST_HOME/.config/git/accounts/acme.gitconfig" ]
    [ ! -e "$TEST_HOME/.ssh.d/accounts/acme.ssh.config" ]
  done
}

@test "account add rejects an alias introduced after it acquires the lock" {
  cat > "$TEST_STATE_DIR/github-accounts.json" <<EOF
{"schema_version":1,"primary_accounts":[],"secondary_accounts":[]}
EOF
  cat > "$TEST_BIN/jq" <<'EOF'
#!/bin/bash
if [ -d "$DEV_ENV_STATE_DIR/accounts.lock" ] && [ ! -e "$DEV_ENV_STATE_DIR/alias-injected" ]; then
  : > "$DEV_ENV_STATE_DIR/alias-injected"
  printf '%s\n' "{\"schema_version\":1,\"primary_accounts\":[],\"secondary_accounts\":[{\"id\":\"racer\",\"name\":\"Race User\",\"email\":\"race@example.test\",\"github_login\":\"racer\",\"ssh_key\":\"$HOME/.ssh/id_acme\",\"ssh_alias\":\"GH-RACE\",\"scope\":\"$HOME/repos/racer\"}]}" > "$DEV_ENV_STATE_DIR/github-accounts.json"
fi
exec /usr/bin/jq "$@"
EOF
  chmod +x "$TEST_BIN/jq"

  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" PATH="$TEST_BIN:$PATH" \
    bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-login acme \
    --ssh-key "$TEST_HOME/.ssh/id_acme" \
    --ssh-alias gh-race \
    --scope "$TEST_HOME/repos/acme" <<< "y"

  [ "$status" -ne 0 ]
  [[ "$output" == *"alias 'gh-race' ya está en uso por cuenta 'racer'"* ]]
  [ ! -e "$TEST_HOME/.config/git/accounts/acme.gitconfig" ]
  [ ! -e "$TEST_HOME/.ssh.d/accounts/acme.ssh.config" ]
}

@test "validate_schema rejects malformed account records and duplicate account state" {
  local legacy_primary malformed_primary duplicate_primary duplicate_id duplicate_alias
  legacy_primary='{"schema_version":1,"primary_accounts":[{"id":"primary","name":"Primary","email":"primary@example.test","ssh_key":"/tmp/primary"}],"secondary_accounts":[]}'
  malformed_primary='{"schema_version":1,"primary_accounts":[{"id":"primary","name":"Primary","email":"primary@example.test","ssh_key":false}],"secondary_accounts":[]}'
  duplicate_primary='{"schema_version":1,"primary_accounts":[{"id":"primary","name":"Primary","email":"primary@example.test","ssh_key":"/tmp/primary"},{"id":"primary","name":"Other","email":"other@example.test","ssh_key":"/tmp/other"}],"secondary_accounts":[]}'
  duplicate_id='{"schema_version":1,"primary_accounts":[],"secondary_accounts":[{"id":"acme","name":"Acme","email":"acme@example.test","github_login":"acme","ssh_key":"/tmp/acme","ssh_alias":"gh-acme","scope":"/tmp/acme"},{"id":"acme","name":"Other","email":"other@example.test","github_login":"other","ssh_key":"/tmp/other","ssh_alias":"gh-other","scope":"/tmp/other"}]}'
  duplicate_alias='{"schema_version":1,"primary_accounts":[],"secondary_accounts":[{"id":"acme","name":"Acme","email":"acme@example.test","github_login":"acme","ssh_key":"/tmp/acme","ssh_alias":"gh-acme","scope":"/tmp/acme"},{"id":"other","name":"Other","email":"other@example.test","github_login":"other","ssh_key":"/tmp/other","ssh_alias":"GH-ACME","scope":"/tmp/other"}]}'

  printf '%s\n' "$legacy_primary" > "$TEST_STATE_DIR/github-accounts.json"
  run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
    bash -c '. "$1/scripts/lib/github-accounts.sh"; validate_schema' \
    bash "$REPO_ROOT"
  [ "$status" -eq 0 ]

  for state in "$malformed_primary" "$duplicate_primary" "$duplicate_id" "$duplicate_alias"; do
    printf '%s\n' "$state" > "$TEST_STATE_DIR/github-accounts.json"
    run env HOME="$TEST_HOME" DEV_ENV_STATE_DIR="$TEST_STATE_DIR" \
      bash -c '. "$1/scripts/lib/github-accounts.sh"; validate_schema' \
      bash "$REPO_ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"registros de cuentas inválidos o duplicados"* ]]
  done
}
