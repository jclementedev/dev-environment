# Gestión de herramientas

Este documento describe cómo se instalan, actualizan y administran las herramientas del entorno de desarrollo.

## Scripts principales

El proyecto separa la instalación inicial de la actualización del entorno y de las herramientas.

| Script | Responsabilidad |
| --- | --- |
| `install.sh` | Instala el entorno y recupera componentes faltantes. No realiza una actualización general de herramientas. |
| `scripts/update.sh` | Actualiza el repositorio de dotfiles y reaplica Chezmoi. No modifica las herramientas instaladas. |
| `scripts/update-tools.sh` | Actualiza las herramientas compatibles mediante una operación explícita del usuario. |

## Actualizar herramientas

### Actualizar todas las herramientas

```bash
./scripts/update-tools.sh
```

### Actualizar una herramienta específica

```bash
./bootstrap/<componente>.sh update
```

## Componentes actualizables

Cada componente expone una acción `update` implementada por su bootstrap correspondiente.

| Componente | Mecanismo | Binario |
| --- | --- | --- |
| `actionlint` | Descarga desde GitHub Releases | `~/.local/bin/actionlint` |
| `hadolint` | Descarga desde GitHub Releases | `~/.local/bin/hadolint` |
| `checkov` | `pipx upgrade --install` | `~/.local/bin/checkov` |
| `semgrep` | `pipx upgrade --install` | `~/.local/bin/semgrep` |
| `markdownlint` | `npm install -g markdownlint-cli2@latest` | `~/.local/bin/markdownlint-cli2` |
| `pi` | `npm install -g @earendil-works/pi-coding-agent@latest` | `~/.local/bin/pi` |
| `chezmoi` | Reejecución del instalador oficial | `~/.local/bin/chezmoi` |

Cada bootstrap soporta las siguientes acciones:

| Acción | Descripción |
| --- | --- |
| `install` (predeterminada) | Instala la herramienta si aún no está disponible. |
| `update` | Actualiza la herramienta a la versión estable más reciente. |

Una acción no soportada devuelve el código de salida `2`.

```bash
./bootstrap/checkov.sh invalid-action

# [ERROR] checkov: acción no soportada: invalid-action
# exit 2
```

## Componentes excluidos

Los siguientes componentes no forman parte de `scripts/update-tools.sh`:

| Componente | Motivo |
| --- | --- |
| `opencode` | Su instalador no ofrece un mecanismo de actualización repetible. |
| `herdr` | Su instalador no ofrece un mecanismo de actualización repetible. |
| `node` | Runtime administrado mediante versiones declaradas. |
| `python` | Runtime administrado mediante versiones declaradas. |
| `dotnet` | Runtime administrado mediante versiones declaradas. |

Para cambiar la versión de un runtime, modifica su bootstrap correspondiente y vuelve a ejecutar:

```bash
./install.sh
```

## Política de fallos

El orquestador continúa procesando todos los componentes aunque alguno falle.

| Situación | Código de salida |
| --- | --- |
| Todas las actualizaciones finalizaron correctamente | `0` |
| Uno o más componentes fallaron | `1` |
| Error interno del orquestador | `2` |

Ejemplos de fallos individuales:

- `apt-get` falla durante la actualización.
- `sudo` no está disponible.
- `pipx` no está disponible.
- Una herramienta específica no puede actualizarse.

## Política de versiones

Las herramientas de línea de comandos se actualizan siempre a la versión estable más reciente.

Los runtimes y SDKs permiten múltiples versiones instaladas. Cada proyecto define la versión que utiliza mediante sus propios mecanismos, por ejemplo:

- `global.json`
- `mise.toml`
- `package.json`

## Política de sudo y APT

- `sudo -v` se solicita antes de ejecutar operaciones que requieren elevación.
- Las operaciones sobre APT se ejecutan antes que el resto de actualizaciones.
- APT se ejecuta de forma interactiva, sin `-y` ni modificaciones de Debconf o `needrestart`.
- No se recomienda configurar `NOPASSWD` global en `sudoers`. Si se requiere automatización, debe limitarse únicamente a los comandos utilizados por los scripts.

## Pruebas

El proyecto incluye dos niveles de pruebas para la administración de herramientas:

| Archivo | Propósito |
| --- | --- |
| `tests/bootstrap-scripts.bats` | Valida la estructura, permisos, sintaxis y contrato básico de los scripts en `bootstrap/`. |
| `tests/update-tools.bats` | Valida el comportamiento del orquestador utilizando stubs de los comandos externos. |

Los stubs ubicados en `tests/fixtures/bin/` simulan comandos como `sudo`, `apt-get`, `pipx`, `npm`, `curl` y `jq`, permitiendo ejecutar las pruebas sin depender de Internet ni modificar el sistema.

## Ver también

- [`README.md`](../README.md) — Inicio rápido y comandos principales.
- [`architecture.md`](architecture.md) — Arquitectura del entorno.
- [`troubleshooting.md`](troubleshooting.md) — Problemas comunes y soluciones.
