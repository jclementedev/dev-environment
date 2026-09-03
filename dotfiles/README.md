# dotfiles/

Fuente de configuración de [chezmoi](https://chezmoi.io), aplicada por
`install.sh` mediante `chezmoi apply --source ./dotfiles`.

## Contenido

- `.chezmoi.toml` — Valor predeterminado de `primary_ssh_key`.
- `dot_zshrc.tmpl` — Configuración de Zsh, plugins y Starship.
- `dot_gitconfig.tmpl` — Configuración base de Git e inclusiones condicionales por máquina.
- `dot_ssh/config.tmpl` — Configuración SSH con `IdentitiesOnly=yes`.
- `dot_config/git/ignore` — Archivo global de exclusiones de Git.
- `dot_config/zsh/aliases.zsh` — Alias y funciones compartidos del entorno.

## Datos por máquina

`~/.config/chezmoi/chezmoi.toml` contiene los datos específicos de cada máquina.
`install.sh` crea o completa los valores faltantes de `git_user_name`,
`git_user_email` y `primary_ssh_key`, sin sobrescribir los valores ni la
configuración existentes. Consulta `docs/installation.md`.

## Agregar un dotfile

1. Usa `dot_X.tmpl` para archivos en el directorio personal o `dot_config/Y/Z`
   para archivos dentro de `~/.config`.
2. Si requiere datos por máquina, agrégalos a `[data]` en `.chezmoi.toml`.
3. Para secretos reales, utiliza cifrado o un gestor externo; el prefijo
   `private_` solo restringe los permisos del archivo de destino.
4. Valida los cambios con:

   ```bash
   chezmoi --source ./dotfiles diff
   ```

## Alias locales

Los alias y funciones compartidos viven en `dot_config/zsh/aliases.zsh` y se
cargan automáticamente desde `dot_zshrc.tmpl`.

Para añadir alias o funciones personales, especialmente aquellos ligados a la
estructura de directorios del usuario, crea manualmente el archivo:

```text
~/.config/zsh/aliases.local.zsh
```

Este archivo es opcional, no está administrado por chezmoi y se carga
automáticamente cuando existe.

`dot_config/zsh/aliases.local.zsh` figura en `.chezmoiignore` como una medida de
protección para evitar que sea administrado accidentalmente.

### Ejemplo para un equipo personal

```zsh
alias dev='cd "$HOME/dev"'
alias work='cd "$HOME/dev/work"'
alias clients='cd "$HOME/dev/clients"'
alias personal='cd "$HOME/dev/personal"'
alias lab='cd "$HOME/dev/lab"'
alias examples='cd "$HOME/dev/examples"'
alias playground='cd "$HOME/dev/playground"'
```

### Ejemplo para un equipo corporativo

```zsh
alias dev='cd "$HOME/dev"'
alias projects='cd "$HOME/dev/projects"'
alias lab='cd "$HOME/dev/lab"'
alias examples='cd "$HOME/dev/examples"'
alias playground='cd "$HOME/dev/playground"'
```
