# Instalación

## Requisitos

- bash 4+
- git 2.x
- ~200 MB de espacio libre en disco
- sudo (interactive; se solicita password durante la instalación)

## Distribuciones soportadas

| Distro       | Versión | Estado                                                |
| ------------ | ------- | ----------------------------------------------------- |
| Ubuntu (apt) | 24.04, 26.04 | Soportada por `install.sh`                       |
| WSL2         | 24.04, 26.04 | Soportado sobre una versión Ubuntu admitida       |

CI corre en Ubuntu 26.04 (`.github/workflows/ci.yml`). Ubuntu 24.04 está
admitida por la validación de plataforma, pero no tiene un job de CI separado.

`install.sh` valida la plataforma antes de cualquier `apt-get` o
instalación de bootstrap y rechaza releases no soportadas con un error
explícito. Si ve el rechazo y necesita soporte, abra un issue con la
traza de `/etc/os-release`.

## Instalación base

### Automatizada

```bash
curl -fsSL https://raw.githubusercontent.com/jclementedev/dev-environment/main/bootstrap.sh | bash
```

`bootstrap.sh` valida Ubuntu, clona o actualiza el repositorio y ejecuta
`install.sh`. No crea claves SSH, estado de cuentas ni autenticación de GitHub.

### Manual (clon directo)

```bash
git clone https://github.com/jclementedev/dev-environment.git ~/dev-environment
cd ~/dev-environment
./install.sh
```

`install.sh` orquesta: validar plataforma → cachear sudo → ejecutar bootstraps
requeridos y opcionales → crear datos iniciales de Chezmoi → aplicar Chezmoi.
No inicializa `github-accounts.json` ni modifica `known_hosts`.

Los componentes opcionales incluyen `dev-tools`, que instala Bats, ShellCheck y
shfmt. Homebrew no se ejecuta en este flujo; `bootstrap/brew.sh` permanece como
un script independiente.

`install.sh` requiere sudo interactivo para ejecutar `apt-get install`.
Si su ambiente requiere sudo sin password ( unattended setup ), use una entrada
sudoers de scope estricto solo para los comandos que el install necesita:

```bash
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get update, /usr/bin/apt-get install *" \
  | sudo tee /etc/sudoers.d/dev-env-unattended >/dev/null
```

No use `NOPASSWD: ALL`; otorga privilegios de root a todo el sistema.

## Shell de inicio Zsh

Después de instalar Zsh, `install.sh` intenta configurarlo automáticamente como
shell de inicio. Si el cambio falla, la instalación continúa y muestra el
comando para hacerlo manualmente:

```bash
chsh -s "$(command -v zsh)"
```

Cierre sesión e inicie una sesión nueva para que el shell de inicio actualizado
tenga efecto.

## Variables de entorno

| Variable | Uso |
| --- | --- |
| `DEV_ENVIRONMENT_HOME` | Directorio objetivo de clonación para `bootstrap.sh`; por defecto `~/dev-environment`. |
| `DEV_ENV_STATE_DIR` | Directorio de estado para backups y, cuando se usa `account.sh`, estado de cuentas; por defecto `~/.local/state/dev-env-bootstrap`. |
| `BOOTSTRAP_GIT_USER_NAME` | Nombre Git usado al crear por primera vez `~/.config/chezmoi/chezmoi.toml` sin interacción. |
| `BOOTSTRAP_GIT_USER_EMAIL` | Email Git usado al crear por primera vez la configuración de Chezmoi sin interacción. |
| `BOOTSTRAP_SSH_KEY_PATH` | Ruta de la clave SSH principal almacenada como `data.primary_ssh_key` al crear la configuración de Chezmoi. |
| `GITHUB_PRIMARY_NAME` | Reemplaza `data.git_user_name` al registrar la cuenta GitHub principal. |
| `GITHUB_PRIMARY_EMAIL` | Reemplaza `data.git_user_email` al registrar la cuenta GitHub principal. |
| `GITHUB_PRIMARY_SSH_KEY` | Reemplaza `data.primary_ssh_key` al configurar o verificar la cuenta GitHub principal. |
| `GITHUB_PRIMARY_LOGIN` | Login esperado al verificar la cuenta GitHub principal; también puede definirse como `data.github_login`. |

## Configurar GitHub después de instalar

La cuenta GitHub principal es opcional y se configura explícitamente después de
la instalación base:

```bash
bash scripts/account.sh setup-primary
```

El comando genera o reutiliza la clave indicada por `data.primary_ssh_key`,
muestra la clave pública para agregarla en GitHub y, si se confirma, verifica la
autenticación y registra el estado de la cuenta.

## Agregar cuentas secundarias

Después de configurar la cuenta principal si la necesita, agregue cuentas
secundarias con `account.sh add`. Cada cuenta usa la clave indicada: se genera
una nueva si no existe o se reutiliza una clave existente válida. También recibe
un alias SSH y routing basado en gitdir scope.

```bash
bash scripts/account.sh add <id> \
  --name "Jane" \
  --email "jane@acme.test" \
  --github-login jane-acme \
  --ssh-key ~/.ssh/id_acme \
  --ssh-alias gh-acme \
  --scope /srv/repos/acme
```

Los seis flags son requeridos:

| Flag          | Descripción                                                |
| ------------- | ---------------------------------------------------------- |
| `--name`      | Nombre para mostrar en la identidad Git de la cuenta       |
| `--email`     | Dirección de email de GitHub para la cuenta                |
| `--github-login` | Login de GitHub que debe identificar el saludo de autenticación SSH |
| `--ssh-key`   | Path absoluto a la clave SSH privada (se genera si no existe) |
| `--ssh-alias` | Alias SSH único usado en `~/.ssh/config` y reescrituras de URL de Git |
| `--scope`     | Prefijo de path absoluto para routing basado en gitdir (nunca se crea ni toca) |

Los scopes deben ser distintos y no superpuestos. Scopes anidados o iguales son rechazados. Los aliases deben ser únicos en todas las cuentas (comparación case-insensitive). El ID `primary` está reservado y no puede usarse.

La verificación primaria requiere el login esperado mediante `GITHUB_PRIMARY_LOGIN` o `data.github_login` en `~/.config/chezmoi/chezmoi.toml`. El estado previo que no contiene `github_login` se mantiene legible, pero no puede considerarse un registro de identidad verificada.

## Claves de host SSH de GitHub

Ni `bootstrap.sh` ni `install.sh` ejecutan `trust_github_host()` ni escriben
`~/.ssh/known_hosts`. Durante la configuración explícita de GitHub,
`account.sh` obtiene las claves de host, valida sus fingerprints SHA-256 contra
los publicados por GitHub y actualiza solo esas entradas. La autenticación usa
`StrictHostKeyChecking=yes`, por lo que no acepta claves desconocidas ni
reemplaza discrepancias automáticamente.

## Reinstalación limpia

Para resetear el ambiente y reinstalar desde cero:

1. Leer estado — `cat ~/.local/state/dev-env-bootstrap/github-accounts.json | jq .` (o anotar dónde está el archivo).
2. Conservar el backup anunciado `~/.local/state/dev-env-bootstrap/backups/pre-chezmoi/`; no lo elimine hasta comprobar la nueva instalación.
3. Desactivar el routing de cuentas — `rm -f ~/.config/git/accounts-routing.gitconfig`. Esta operación no es atómica; cierre procesos Git que puedan usarlo antes de ejecutarla.
4. Remover estado, lock y staging — `rm -rf ~/.local/state/dev-env-bootstrap/{accounts.lock,github-accounts.json,transactions}`. No remover claves SSH generadas aquí aún (ver paso 7).
5. Remover fragmentos de cuenta y configuración SSH de cuenta — `rm -rf ~/.config/git/accounts ~/.ssh.d/accounts`.
6. Remover estado local de Chezmoi y archivos base manejados — `rm -f ~/.gitconfig ~/.config/chezmoi/chezmoi.toml ~/.ssh/config`. `~/.ssh/known_hosts` no se elimina: las entradas de GitHub las administra `account.sh` y el backup no preserva el archivo completo.
7. OPCIONAL: remover claves secundarias generadas — estas claves no se reutilizan en ningún otro lado; puede remover `~/.ssh/id_*` (excepto la clave primary) si desea. La clave primary en `primary_ssh_key` debería conservarse si planea volver a ejecutar bootstrap.
8. Revertir source y volver a ejecutar bootstrap — `git -C <dev-environment-repo> checkout dotfiles/ scripts/` (o `git restore`) y volver a ejecutar `bash bootstrap.sh` o `curl ... | bash` según el flujo de instalación.

## Próximos pasos

```bash
bash scripts/update.sh                 # pull + apply
bash scripts/backup.sh                 # snapshot de dotfiles con timestamp
bash scripts/backup.sh --list          # listar snapshots
bash scripts/restore.sh <path>         # rollback (snapshot defensivo automático)
```
