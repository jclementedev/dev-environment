# dev-environment

Entorno de desarrollo reproducible con instalación, configuración y mantenimiento automatizados.

## Plataformas soportadas

| Plataforma           | Estado         | Notas                                                       |
| -------------------- | -------------- | ----------------------------------------------------------- |
| Ubuntu LTS           | ✅ Soportado   | Plataforma principal.                                       |
| WSL2                 | ✅ Soportado   | Entorno recomendado para Windows.                           |
| Windows (PowerShell) | 🚧 Planificado | Automatización de la configuración de aplicaciones nativas. |

Consulta [`docs/installation.md`](docs/installation.md) para conocer los requisitos y las plataformas soportadas.

## Inicio rápido

Instalación automática:

```bash
curl -fsSL https://raw.githubusercontent.com/jclementedev/dev-environment/main/bootstrap.sh | bash
```

O clonar el repositorio manualmente:

```bash
git clone https://github.com/jclementedev/dev-environment.git ~/.local/share/dev-environment
cd ~/.local/share/dev-environment
./install.sh
```

### Shell de inicio de sesión

`install.sh` configura automáticamente Zsh como shell de inicio. Si no puede hacerlo, ejecute:

```bash
chsh -s "$(command -v zsh)"
```

## Estructura

| Ruta             | Descripción                                                                               |
| ---------------- | ----------------------------------------------------------------------------------------- |
| `bootstrap/`     | Scripts de instalación por herramienta.                                                   |
| `bootstrap/lib/` | Bibliotecas compartidas para los bootstraps.                                              |
| `dotfiles/`      | Configuración administrada por Chezmoi (Git, Zsh, SSH y otros archivos de configuración). |
| `scripts/`       | Scripts auxiliares del entorno.                                                           |
| `scripts/lib/`   | Bibliotecas compartidas para los scripts auxiliares.                                      |
| `tests/`         | Pruebas Bats, fixtures y validaciones.                                                    |
| `docs/`          | Documentación del proyecto.                                                               |
| `.github/`       | Workflows de CI.                                                                          |
| `install.sh`     | Orquestador principal de instalación.                                                     |
| `bootstrap.sh`   | Punto de entrada con clonación y actualización automática del repositorio.                |

## Comandos principales

```bash
bash scripts/update.sh                 # actualizar el entorno y reaplicar Chezmoi
bash scripts/update-tools.sh           # actualizar las herramientas instaladas
bash scripts/backup.sh                 # crear un snapshot de los dotfiles
bash scripts/restore.sh <snapshot>     # restaurar un snapshot
bash scripts/account.sh setup-primary  # configurar la cuenta principal de GitHub
bash scripts/account.sh add <id> ...   # agregar una cuenta adicional de GitHub
```

## Actualización

### Actualizar el entorno

Actualiza el repositorio y reaplica la configuración administrada por Chezmoi.

```bash
./scripts/update.sh
```

### Actualizar herramientas

Actualiza las herramientas compatibles instaladas en `~/.local/bin`.

```bash
./scripts/update-tools.sh
```

Consulta [`docs/tools.md`](docs/tools.md) para conocer:

- herramientas compatibles;
- componentes excluidos;
- política de versiones;
- comportamiento ante fallos.

## Configuración de GitHub

Durante la instalación se crea (o completa) `~/.config/chezmoi/chezmoi.toml` sin sobrescribir la configuración existente.

Para configurar la cuenta principal después de instalar:

```bash
bash scripts/account.sh setup-primary
```

## Agregar una cuenta adicional

```bash
bash scripts/account.sh add acme \
  --name "Jane" \
  --email "jane@acme.test" \
  --github-username jane-acme \
  --scope /srv/repos/acme
```

Consulta [`docs/installation.md`](docs/installation.md) para conocer el procedimiento completo.

## Ver también

- [`docs/installation.md`](docs/installation.md) — Instalación, requisitos y plataformas soportadas.
- [`docs/tools.md`](docs/tools.md) — Gestión y actualización de herramientas.
- [`docs/security.md`](docs/security.md) — Consideraciones de seguridad.
- [`docs/architecture.md`](docs/architecture.md) — Arquitectura del entorno.
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — Problemas comunes y soluciones.
- [`docs/chezmoi-conventions.md`](docs/chezmoi-conventions.md) — Convenciones utilizadas por Chezmoi.
