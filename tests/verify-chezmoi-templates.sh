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

HOME="$home_directory" ssh -G -F "$rendered_ssh_config" template-check.invalid >/dev/null
