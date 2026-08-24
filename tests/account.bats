#!/usr/bin/env bats
# Cobertura del alta y verificación de cuentas GitHub.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_HOME="$(mktemp -d)"
  TEST_BIN="$(mktemp -d)"

  mkdir -p "$TEST_HOME/.ssh"

  # Claves pre-existentes para que add no necesite /dev/tty.
  ssh-keygen -q -t ed25519 -N "" -f "$TEST_HOME/.ssh/id_ed25519"
  ssh-keygen -q -t ed25519 -N "" -f "$TEST_HOME/.ssh/id_ed25519_acme"
  ssh-keygen -q -t ed25519 -N "" -f "$TEST_HOME/.ssh/id_ed25519_work"
  ssh-keygen -q -t ed25519 -N "" -f "$TEST_HOME/.ssh/id_ed25519_work2"

  # Routing de cuentas debe estar incluido en ~/.gitconfig.
  printf '[include]\n    path = ~/.config/git/accounts-routing.gitconfig\n' \
      > "$TEST_HOME/.gitconfig"

  # Stub ssh: valida la clave (-i) contra SSH_EXPECTED_KEY y emite saludo.
  cat > "$TEST_BIN/ssh" <<'EOF'
#!/bin/sh
key=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -i) [ "$#" -ge 2 ] || exit 2; key="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [ -n "${SSH_EXPECTED_KEY:-}" ] && [ "$key" != "$SSH_EXPECTED_KEY" ]; then
    printf 'unexpected SSH key: %s\n' "$key" >&2
    exit 1
fi
printf '%s\n' \
    "${SSH_GREETING:-Hi acme! You've successfully authenticated, but GitHub does not provide shell access.}"
EOF
  chmod +x "$TEST_BIN/ssh"

  # Stub ssh-keyscan: emite host keys.
  cat > "$TEST_BIN/ssh-keyscan" <<'EOF'
#!/bin/sh
cat <<'KEYS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
KEYS
EOF
  chmod +x "$TEST_BIN/ssh-keyscan"
}

teardown() {
  rm -rf "$TEST_HOME" "$TEST_BIN"
}

run_account() {
  env HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" "$@"
}

@test "setup-primary reutiliza clave existente y muestra pública" {
  run run_account GITHUB_PRIMARY_EMAIL="user@example.test" \
    GITHUB_PRIMARY_USERNAME="user" \
    bash "$REPO_ROOT/scripts/account.sh" setup-primary

  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.ssh/id_ed25519" ]
  [ -f "$TEST_HOME/.ssh/id_ed25519.pub" ]
  [[ "$output" == *"ssh-ed25519"* ]]
}

@test "setup-primary usa los datos de Chezmoi sin variables de entorno" {
  cat > "$TEST_BIN/chezmoi" <<'EOF'
#!/bin/sh
case "$*" in
  *git_user_email*) printf '%s' 'chezmoi@example.test' ;;
  *github_login*) printf '%s' 'chezmoi-user' ;;
  *primary_ssh_key*) printf '%s' "$HOME/.ssh/id_ed25519" ;;
esac
EOF
  chmod +x "$TEST_BIN/chezmoi"

  run run_account bash "$REPO_ROOT/scripts/account.sh" setup-primary

  [ "$status" -eq 0 ]
  [[ "$output" == *"ssh-ed25519"* ]]
  [[ "$output" != *"GITHUB_PRIMARY_EMAIL no definido"* ]]
}

@test "setup-primary sin clave requiere terminal interactiva" {
  rm -f "$TEST_HOME/.ssh/id_ed25519" "$TEST_HOME/.ssh/id_ed25519.pub"

  run run_account GITHUB_PRIMARY_EMAIL="user@example.test" \
    GITHUB_PRIMARY_USERNAME="user" \
    bash "$REPO_ROOT/scripts/account.sh" setup-primary </dev/null

  [ "$status" -ne 0 ]
  [[ "$output" == *"terminal interactiva"* ]]
}

@test "verify primary autentica con la clave primaria" {
  run run_account GITHUB_PRIMARY_USERNAME="acme" \
    SSH_EXPECTED_KEY="$TEST_HOME/.ssh/id_ed25519" \
    bash "$REPO_ROOT/scripts/account.sh" verify primary

  [ "$status" -eq 0 ]
}

@test "verify primary no requiere include de routing" {
  rm -f "$TEST_HOME/.gitconfig"

  run run_account GITHUB_PRIMARY_USERNAME="acme" \
    SSH_EXPECTED_KEY="$TEST_HOME/.ssh/id_ed25519" \
    bash "$REPO_ROOT/scripts/account.sh" verify primary

  [ "$status" -eq 0 ]
}

@test "add crea clave, fragmento con core.sshCommand y routing" {
  mkdir -p "$TEST_HOME/repos/acme"

  run run_account bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-username acme \
    --scope "$TEST_HOME/repos/acme"

  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.ssh/id_ed25519_acme" ]
  [ -f "$TEST_HOME/.ssh/id_ed25519_acme.pub" ]
  [ -f "$TEST_HOME/.config/git/accounts/acme.gitconfig" ]
  [ -f "$TEST_HOME/.config/git/accounts-routing.gitconfig" ]
  [ -d "$TEST_HOME/repos/acme" ]
  [[ "$output" == *"verify acme"* ]]

  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get user.name
  [ "$output" = "Acme User" ]

  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get user.email
  [ "$output" = "acme@example.test" ]

  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get github.username
  [ "$output" = "acme" ]

  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get core.sshCommand
  [[ "$output" == *"id_ed25519_acme"* ]]
  [[ "$output" == *"IdentitiesOnly=yes"* ]]
}

@test "add resuelve includeIf funcionalmente dentro del scope" {
  mkdir -p "$TEST_HOME/repos/acme/proyecto"
  run run_account bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-username acme \
    --scope "$TEST_HOME/repos/acme"
  [ "$status" -eq 0 ]

  git -C "$TEST_HOME/repos/acme/proyecto" init -q

  run env HOME="$TEST_HOME" \
    git -C "$TEST_HOME/repos/acme/proyecto" config --get user.name
  [ "$status" -eq 0 ]
  [ "$output" = "Acme User" ]

  run env HOME="$TEST_HOME" \
    git -C "$TEST_HOME/repos/acme/proyecto" config --get user.email
  [ "$status" -eq 0 ]
  [ "$output" = "acme@example.test" ]

  run env HOME="$TEST_HOME" \
    git -C "$TEST_HOME/repos/acme/proyecto" config --get core.sshCommand
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_HOME/.ssh/id_ed25519_acme"* ]]
}

@test "add escribe valores con comillas sin inyección de config" {
  mkdir -p "$TEST_HOME/repos/acme"
  local git_name='Acme "Builder"'
  local git_email='acme.builder@example.test'

  run run_account bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "$git_name" \
    --email "$git_email" \
    --github-username acme \
    --scope "$TEST_HOME/repos/acme"

  [ "$status" -eq 0 ]
  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get user.name
  [ "$output" = "$git_name" ]
  run git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" --get user.email
  [ "$output" = "$git_email" ]
}

@test "add rechaza id 'primary'" {
  run run_account bash "$REPO_ROOT/scripts/account.sh" add primary \
    --name "User" \
    --email "user@example.test" \
    --github-username user \
    --scope "$TEST_HOME/repos/acme"

  [ "$status" -ne 0 ]
  [[ "$output" == *"primary"* ]]
}

@test "add aborta si par de claves está incompleto" {
  : > "$TEST_HOME/.ssh/id_ed25519_broken"

  run run_account bash "$REPO_ROOT/scripts/account.sh" add broken \
    --name "User" \
    --email "user@example.test" \
    --github-username user \
    --scope "$TEST_HOME/repos/acme"

  [ "$status" -ne 0 ]
  [[ "$output" == *"par de claves incompleto"* ]]
}

@test "add falla si la cuenta ya existe" {
  mkdir -p "$TEST_HOME/repos/acme"
  run run_account bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-username acme \
    --scope "$TEST_HOME/repos/acme"
  [ "$status" -eq 0 ]

  run run_account bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Other" \
    --email "other@example.test" \
    --github-username other \
    --scope "$TEST_HOME/repos/acme"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ya existe"* ]]
}

@test "add rechaza scope ya asociado a otra cuenta" {
  mkdir -p "$TEST_HOME/repos/work"
  run run_account bash "$REPO_ROOT/scripts/account.sh" add work \
    --name "Work User" \
    --email "work@example.test" \
    --github-username work-user \
    --scope "$TEST_HOME/repos/work"
  [ "$status" -eq 0 ]

  run run_account bash "$REPO_ROOT/scripts/account.sh" add work2 \
    --name "Work2 User" \
    --email "work2@example.test" \
    --github-username work2-user \
    --scope "$TEST_HOME/repos/work"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ya está asociado"* ]]
}

@test "verify secundario usa su clave y autentica" {
  mkdir -p "$TEST_HOME/repos/acme"
  run run_account bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-username acme \
    --scope "$TEST_HOME/repos/acme"
  [ "$status" -eq 0 ]

  run run_account SSH_EXPECTED_KEY="$TEST_HOME/.ssh/id_ed25519_acme" \
    bash "$REPO_ROOT/scripts/account.sh" verify acme

  [ "$status" -eq 0 ]
}

@test "verify secundario sin include de routing falla con mensaje claro" {
  rm -f "$TEST_HOME/.gitconfig"

  mkdir -p "$TEST_HOME/.config/git/accounts"
  git config --file "$TEST_HOME/.config/git/accounts/acme.gitconfig" github.username acme

  run run_account bash "$REPO_ROOT/scripts/account.sh" verify acme

  [ "$status" -ne 0 ]
  [[ "$output" == *"debe incluir el routing"* ]]
}

@test "verify de id inexistente falla con mensaje claro" {
  run run_account bash "$REPO_ROOT/scripts/account.sh" verify missing

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* ]]
  [[ "$output" == *"no encontrada"* ]]
}

@test "verify rechaza saludo que no coincide con username esperado" {
  mkdir -p "$TEST_HOME/repos/acme"
  run run_account bash "$REPO_ROOT/scripts/account.sh" add acme \
    --name "Acme User" \
    --email "acme@example.test" \
    --github-username acme \
    --scope "$TEST_HOME/repos/acme"
  [ "$status" -eq 0 ]

  run run_account SSH_GREETING="Hi other! You've successfully authenticated, but GitHub does not provide shell access." \
    bash "$REPO_ROOT/scripts/account.sh" verify acme

  [ "$status" -ne 0 ]
  [[ "$output" == *"verificación"* ]]
  [[ "$output" == *"fallida"* ]]
}

@test "list muestra cuentas configuradas desde disco" {
  mkdir -p "$TEST_HOME/.config/git/accounts"

  cat > "$TEST_HOME/.config/git/accounts/acme.gitconfig" <<EOF
[user]
    name = Acme User
    email = acme@example.test
EOF

  cat > "$TEST_HOME/.config/git/accounts/work.gitconfig" <<EOF
[user]
    name = Work User
    email = work@example.test
EOF

  run run_account bash "$REPO_ROOT/scripts/account.sh" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"acme"* ]]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"acme@example.test"* ]]
  [[ "$output" == *"work@example.test"* ]]
}

@test "list sin cuentas indica vacío" {
  run run_account bash "$REPO_ROOT/scripts/account.sh" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"no hay cuentas"* ]]
}
