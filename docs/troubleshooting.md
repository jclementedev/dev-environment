# Resolución de problemas

## Permisos SSH

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_<key>
```

## credential.helper cache

```bash
git config --global credential.helper cache
# o: cache --timeout=3600
```

## chezmoi: diferencias

```bash
chezmoi --source ./dotfiles diff
chezmoi --source ./dotfiles apply --force
```

## `update.sh` git pull falló

`git pull --ff-only` no se resuelve con `git push`: son operaciones distintas. Primero
inspeccione la divergencia:

```bash
git -C <repo> status                          # estado del árbol
git -C <repo> fetch origin                    # traer refs remotas
git -C <repo> log --oneline main..origin/main # commits remotos que faltan localmente
git -C <repo> log --oneline origin/main..main # commits locales no enviados
```

### Descartar cambios locales no enviados

ADVERTENCIA: guarde un parche o cree una rama de respaldo antes de continuar.
Solo entonces:

```bash
git -C <repo> reset --hard origin/main
```

## shell sin plugins zsh

```bash
sudo apt install zsh-autosuggestions zsh-syntax-highlighting
exec zsh
```

## starship no aparece

```bash
bash install.sh             # reintentar la instalación
exec zsh                    # recargar PATH
```

## GitHub no está configurado tras instalar

La instalación base no crea claves ni estado de cuentas GitHub. Configure la
cuenta principal explícitamente:

```bash
bash scripts/account.sh setup-primary
```

Para verificar una clave ya registrada, defina `GITHUB_PRIMARY_LOGIN` (o
`data.github_login` en `~/.config/chezmoi/chezmoi.toml`) y ejecute:

```bash
bash scripts/account.sh verify-primary
```

## chezmoi apply — file already exists

`install.sh` no usa `--force`; revise el archivo existente y ejecute
`chezmoi --source ./dotfiles apply --force` solo si desea reemplazarlo.

## WSL — `sudo: unable to resolve host`

```bash
grep -qw "$(hostname)" /etc/hosts || \
  printf '127.0.1.1 %s\n' "$(hostname)" | sudo tee -a /etc/hosts >/dev/null
```

## Restore rollback

`scripts/backup.sh --list` y `scripts/restore.sh <snapshot>`.
