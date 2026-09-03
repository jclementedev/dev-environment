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

## Estrategia de uso de versiones

El entorno prepara capacidades transversales. Cada proyecto decide
qué versiones exactas necesita y cómo aplica las herramientas.

### Regla general

Versiones recientes y estables por defecto. Se fija una versión únicamente
cuando:

- hay líneas de compatibilidad que administrar (runtimes, SDKs);
- varios proyectos requieren versiones distintas;
- existe incompatibilidad conocida con latest.

### Quién decide qué versión

Cada proyecto declara explícitamente:

- **Versiones exactas**: `global.json` (`.NET`), `.nvmrc` (Node), `.python-version`,
  `.terraform-version`.
- **Reglas por linter**: `.hadolint.yaml`, `.shellcheckrc`, `.markdownlint.json`,
  etc.

El entorno prepara los ejecutables. El proyecto decide cómo los usa.

### Categorías

**Latest estable (sin pin):**

- Linters y validadores: bats, shellcheck, shfmt, yamllint, actionlint,
  hadolint, semgrep, checkov, markdownlint
- Instaladores oficiales: opencode, herdr, aws, brew
- Utilidades: ripgrep, fzf, bat, eza, zoxide, jq, yq, gh

**Versionado por línea (gestionado por la herramienta):**

- `.NET SDK` 8.0 y 10.0 (coexisten; cada proyecto usa `global.json`)
- `Terraform` estable (cada proyecto usa `.terraform-version`)
- `Node.js` LTS (cada proyecto usa `.nvmrc`)
- `Python` del sistema (cada proyecto usa `.python-version`)

## Instalación base

### Automatizada

```bash
curl -fsSL https://raw.githubusercontent.com/jclementedev/dev-environment/main/bootstrap.sh | bash
```

`bootstrap.sh` valida Ubuntu, clona o actualiza el repositorio y ejecuta
`install.sh`. No crea claves SSH, estado de cuentas ni autenticación de GitHub.

### Manual (clon directo)

```bash
git clone https://github.com/jclementedev/dev-environment.git ~/.local/share/dev-environment
cd ~/.local/share/dev-environment
./install.sh
```

`install.sh` orquesta: validar plataforma → cachear sudo → ejecutar bootstraps
requeridos y opcionales → crear datos iniciales de Chezmoi → aplicar Chezmoi.
No inicializa cuentas GitHub ni modifica `known_hosts`.

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
| `DEV_ENVIRONMENT_HOME` | Directorio objetivo de clonación para `bootstrap.sh`; por defecto `${XDG_DATA_HOME:-$HOME/.local/share}/dev-environment`. |
| `DEV_ENV_STATE_DIR` | Directorio de estado para backups; por defecto `~/.local/state/dev-env-bootstrap`. |
| `BOOTSTRAP_GIT_USER_NAME` | Nombre Git usado al crear por primera vez `~/.config/chezmoi/chezmoi.toml` sin interacción. |
| `BOOTSTRAP_GIT_USER_EMAIL` | Email Git usado al crear por primera vez la configuración de Chezmoi sin interacción. |
| `BOOTSTRAP_SSH_KEY_PATH` | Ruta a la clave SSH principal almacenada como `data.primary_ssh_key` al crear la configuración de Chezmoi. |
| `GITHUB_PRIMARY_EMAIL` | Reemplaza `data.git_user_email` al crear la clave SSH principal. |

## Configurar GitHub después de instalar

La cuenta GitHub principal se configura explícitamente después de la
instalación base:

```bash
bash scripts/account.sh setup-primary
```

El comando genera o reutiliza la clave indicada por `data.primary_ssh_key`,
muestra la clave pública para agregarla en GitHub y, si se confirma, verifica la
autenticación y registra el estado de la cuenta.

## Agregar cuentas secundarias

Después de configurar la cuenta principal si la necesita, agregue cuentas
secundarias con `account.sh add`. El script fija la identidad de cada cuenta
secundaria mediante `core.sshCommand` en su fragmento gitconfig, lo que permite
clonar con URLs estándar de GitHub sin alias especiales.

```bash
bash scripts/account.sh add <id> \
  --name "Jane" \
  --email "jane@acme.test" \
  --github-username jane-acme \
  --scope /srv/repos/acme
```

Los cuatro flags son requeridos:

| Flag                | Descripción                                                |
| ------------------- | ---------------------------------------------------------- |
| `--name`            | Nombre para mostrar en la identidad Git de la cuenta       |
| `--email`           | Dirección de email de GitHub para la cuenta                |
| `--github-username` | Usuario público de GitHub para verificar la conexión SSH   |
| `--scope`           | Prefijo de path absoluto para routing basado en gitdir (nunca se crea ni toca) |

La clave SSH se genera automáticamente en `~/.ssh/id_ed25519_<id>` (o se reutiliza
si ya existe) y la ruta se incrusta en el fragmento via `core.sshCommand`. El
script rechaza scopes duplicados y no modifica cuentas existentes.

La verificación primaria comprueba que GitHub acepte la clave, sin requerir el
usuario de la cuenta. Cada cuenta secundaria conserva su propio usuario en su
fragmento Git para comprobar además que se esté usando la cuenta correcta. No
se utiliza ningún archivo de estado JSON.

## Claves de host SSH de GitHub

Ni `bootstrap.sh` ni `install.sh` ejecutan `trust_github_host()` ni escriben
`~/.ssh/known_hosts`. Durante la configuración explícita de GitHub,
`account.sh` obtiene las claves de host, valida sus fingerprints SHA-256 contra
los publicados por GitHub y actualiza solo esas entradas. La autenticación usa
`StrictHostKeyChecking=yes`, por lo que no acepta claves desconocidas ni
reemplaza discrepancias automáticamente.

## Reinstalación limpia

Para resetear el ambiente y reinstalar desde cero:

1. Desactivar el routing de cuentas — `rm -f ~/.config/git/accounts-routing.gitconfig`. Esta operación no es atómica; cierre procesos Git que puedan usarlo antes de ejecutarla.
2. Remover fragmentos de cuenta — `rm -rf ~/.config/git/accounts`.
3. Remover estado local de Chezmoi y archivos base manejados — `rm -f ~/.gitconfig ~/.config/chezmoi/chezmoi.toml ~/.ssh/config`. `~/.ssh/known_hosts` no se elimina: las entradas de GitHub las administra `account.sh` y el backup no preserva el archivo completo.
4. OPCIONAL: remover claves secundarias generadas — puede remover `~/.ssh/id_*` (excepto la clave primary) si desea. La clave primary `~/.ssh/id_ed25519` debería conservarse si planea volver a ejecutar bootstrap.
5. Revertir source y volver a ejecutar bootstrap — `git -C <dev-environment-repo> checkout dotfiles/ scripts/` (o `git restore`) y volver a ejecutar `bash bootstrap.sh` o `curl ... | bash` según el flujo de instalación.

## Próximos pasos

```bash
bash scripts/update.sh                 # pull + apply
bash scripts/backup.sh                 # snapshot de dotfiles con timestamp
bash scripts/backup.sh --list          # listar snapshots
bash scripts/restore.sh <path>         # rollback (snapshot defensivo automático)
```
