# dev-environment

Entorno de desarrollo reproducible. Bootstrap + dotfiles + CI.

## Inicio rápido

```bash
curl -fsSL https://raw.githubusercontent.com/jclementedev/dev-environment/main/bootstrap.sh | bash
```

O clonar manualmente:

```bash
git clone https://github.com/jclementedev/dev-environment.git
cd dev-environment
./install.sh
```

### Shell de inicio de sesión

`install.sh` configura Zsh automáticamente como shell de inicio. Si no puede
hacerlo, ejecute:

```bash
chsh -s "$(command -v zsh)"
```

## Estructura

| Path | Uso |
| ---- | --- |
| `bootstrap/`       | scripts de instalación por herramienta |
| `bootstrap/lib/`   | libs compartidas (log, os, pkg-manager, ssh) |
| `dotfiles/`        | fuente chezmoi |
| `scripts/`         | soporte: backup, restore, update, account |
| `scripts/lib/`     | libs de scripts (github-accounts) |
| `tests/`           | Pruebas Bats, datos de prueba y validación de plantillas de Chezmoi |
| `docs/`            | documentación funcional |
| `.github/`         | workflows CI |
| `install.sh`       | orquestador: validate → bootstrap → chezmoi apply |
| `bootstrap.sh`     | entry point con auto-clone y actualización del repositorio |

## Comandos

```bash
bash scripts/update.sh                 # pull + apply
bash scripts/backup.sh                 # snapshot de dotfiles
bash scripts/restore.sh <snapshot>     # rollback
bash scripts/account.sh setup-primary  # configurar GitHub después de instalar
bash scripts/account.sh add <id> ...   # cuenta secundaria de GitHub
```

## Configurar identidad

`install.sh` crea o completa `~/.config/chezmoi/chezmoi.toml` con
`data.git_user_name`, `data.git_user_email` y `data.primary_ssh_key`, sin
sobrescribir valores ni configuración existentes. Para configurar GitHub después
de instalar, ejecutar `bash scripts/account.sh setup-primary`.

## Multi-cuenta

```bash
bash scripts/account.sh add acme --name "Jane" --email "jane@acme.test" --github-login jane-acme \
  --ssh-key ~/.ssh/id_acme --ssh-alias gh-acme --scope /srv/repos/acme
```

Ver [`docs/installation.md`](docs/installation.md) para el procedimiento completo.

## Ver también

- [`docs/installation.md`](docs/installation.md) — instalación detallada
- [`docs/security.md`](docs/security.md) — qué no va al repo
- [`docs/architecture.md`](docs/architecture.md) — flujo de instalación
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — fallos comunes y remediación
- [`docs/chezmoi-conventions.md`](docs/chezmoi-conventions.md) — convenciones de chezmoi
