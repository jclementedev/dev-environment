# dotfiles/

Fuente [chezmoi](https://chezmoi.io). Aplicada por `install.sh` con
`chezmoi apply --source ./dotfiles`.

## Contenido

- `.chezmoi.toml` — default: `primary_ssh_key`.
- `dot_zshrc.tmpl` — zsh + plugins + starship.
- `dot_gitconfig.tmpl` — base, includes condicionales por máquina.
- `dot_ssh/config.tmpl` — SSH config con `IdentitiesOnly=yes`.
- `dot_config/git/ignore` — gitignore global.

## Datos por máquina

`~/.config/chezmoi/chezmoi.toml` contiene los datos por máquina. `install.sh`
crea o completa los valores faltantes de `git_user_name`, `git_user_email` y
`primary_ssh_key`, sin sobrescribir los valores ni la configuración existentes.
`github_login` es opcional y se usa únicamente por `account.sh` para verificar
la cuenta principal. Ver `docs/installation.md`.

## Agregar un dotfile

1. `dot_X.tmpl` (home) o `dot_config/Y/Z` (subcarpeta).
2. Si tiene datos, agregar a `[data]` en `.chezmoi.toml`.
3. Para secretos reales, usar cifrado o un gestor externo; `private_` solo aplica permisos al archivo de destino.
4. Validar con `chezmoi --source ./dotfiles diff`.
