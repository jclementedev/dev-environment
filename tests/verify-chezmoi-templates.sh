#!/bin/bash

# Render the source against fixture data and parse the generated consumers.
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly FIXTURE_CONFIG="$REPO_ROOT/tests/fixtures/chezmoi.toml"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

home_directory="$temporary_directory/home"
rendered_git_config="$temporary_directory/gitconfig"
rendered_ssh_config="$temporary_directory/ssh-config"
rendered_zshrc="$temporary_directory/zshrc"

mkdir -p "$home_directory/.ssh.d/accounts"

chezmoi cat \
  --config "$FIXTURE_CONFIG" \
  --source "$REPO_ROOT/dotfiles" \
  --destination "$home_directory" \
  "$home_directory/.gitconfig" >"$rendered_git_config"

chezmoi cat \
  --config "$FIXTURE_CONFIG" \
  --source "$REPO_ROOT/dotfiles" \
  --destination "$home_directory" \
  "$home_directory/.ssh/config" >"$rendered_ssh_config"

expected_git_user_name="$(printf 'Ada "Quoted"\nExample')"
actual_git_user_name="$(git config --file "$rendered_git_config" --get user.name)"

[ "$actual_git_user_name" = "$expected_git_user_name" ]
[ "$(git config --file "$rendered_git_config" --get user.email)" = "ada@example.test" ]

HOME="$home_directory" \
  ssh -G -F "$rendered_ssh_config" template-check.invalid >/dev/null

# Aliases: configuración compartida y personalización local opcional.
chezmoi cat \
  --config "$FIXTURE_CONFIG" \
  --source "$REPO_ROOT/dotfiles" \
  --destination "$home_directory" \
  "$home_directory/.zshrc" >"$rendered_zshrc"

# Los archivos de alias compartidos y locales se cargan solo si son legibles.
grep -qF \
  'if [[ -r "$ZSH_CONFIG_DIR/aliases.zsh" ]]; then' \
  "$rendered_zshrc"

grep -qF \
  'source "$ZSH_CONFIG_DIR/aliases.zsh"' \
  "$rendered_zshrc"

grep -qF \
  'if [[ -r "$ZSH_CONFIG_DIR/aliases.local.zsh" ]]; then' \
  "$rendered_zshrc"

grep -qF \
  'source "$ZSH_CONFIG_DIR/aliases.local.zsh"' \
  "$rendered_zshrc"

# Los alias compartidos ya no están definidos inline en .zshrc.
! grep -qE '^[[:space:]]*alias ll=' "$rendered_zshrc"
! grep -qE '^[[:space:]]*alias gs=' "$rendered_zshrc"

# Los alias compartidos viven en el archivo administrado.
aliases_zsh="$REPO_ROOT/dotfiles/dot_config/zsh/aliases.zsh"

[ -s "$aliases_zsh" ]
grep -qE '^[[:space:]]*alias ll=' "$aliases_zsh"
grep -qE '^[[:space:]]*alias gs=' "$aliases_zsh"

# Los archivos locales no forman parte del source state de chezmoi.
[ ! -e "$REPO_ROOT/dotfiles/dot_config/zsh/aliases.local.zsh" ]
[ ! -e "$REPO_ROOT/dotfiles/dot_config/zsh/aliases.local.zsh.example" ]

# Evita que el archivo local termine administrado por accidente.
grep -qFx \
  'dot_config/zsh/aliases.local.zsh' \
  "$REPO_ROOT/dotfiles/.chezmoiignore"
