# Convenciones de chezmoi

| Nombre | Destino | Notas |
|---|---|---|
| `dot_X` | `~/.X` | archivo en home |
| `dot_X.tmpl` | `~/.X` | archivo template (variables `.chezmoi.*`, etc.) |
| `dot_config/Y` | `~/.config/Y` | subcarpeta de config |
| `dot_ssh/Y` | `~/.ssh/Y` | subcarpeta SSH (no para secretos) |
| `private_dot_X` | `~/.X` | permisos 600 en destino; contenido sin cifrar |
| `*.tmpl` | (igual nombre, sin sufijo) | procesado al aplicar |

## Variables disponibles en templates

- `.chezmoi.os` — `"linux"` o `"darwin"`
- `.chezmoi.osRelease` — contenido de `/etc/os-release`
- `.chezmoi.hostname` — nombre del host
- `.chezmoi.username` — usuario
- `.chezmoi.homeDir` — `$HOME`

Más las propias del source bajo `[data]` (por ejemplo, `.git_user_email`).
La instalación crea o completa `git_user_name`, `git_user_email` y
`primary_ssh_key` en `~/.config/chezmoi/chezmoi.toml`, sin sobrescribir los
valores ni la configuración existentes. `github_login` es opcional y solo se
consulta al verificar la cuenta principal con `account.sh`.

## Override por máquina

```toml
# ~/.config/chezmoi/chezmoi.toml
[data]
    git_user_name = "Tu nombre"
    git_user_email = "tu@email-real.com"
    primary_ssh_key = "/home/tu-usuario/.ssh/id_ed25519"
```

Estos datos sobrescriben los valores del source. `install.sh` no interpreta
`CHEZMOI_DATA_JSON`; use `BOOTSTRAP_GIT_USER_NAME`,
`BOOTSTRAP_GIT_USER_EMAIL` y `BOOTSTRAP_SSH_KEY_PATH` para crear el archivo en
modo no interactivo.

## `private_*` vs secretos

`private_dot_*` se incluye en el repositorio fuente de chezmoi y aplica permisos `0600`
al archivo de destino. No cifra ni excluye el contenido de Git.

No usar `private_` para claves privadas, tokens o credenciales. Usar cifrado en
el source o un gestor externo, según la política de seguridad del proyecto.

## Verificar diferencias

```bash
chezmoi diff --source ./dotfiles
```
