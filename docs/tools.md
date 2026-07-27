# Gestión de herramientas

Este documento describe cómo se instalan, actualizan y administran las herramientas del entorno de desarrollo.

## Scripts principales

El proyecto separa la instalación inicial de la actualización del entorno y de las herramientas.

| Script                    | Responsabilidad                                                                                            |
| ------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `install.sh`              | Instala el entorno y recupera componentes faltantes. No realiza una actualización general de herramientas. |
| `scripts/update.sh`       | Actualiza el repositorio de dotfiles y reaplica Chezmoi. No modifica las herramientas instaladas.          |
| `scripts/update-tools.sh` | Actualiza las herramientas compatibles mediante una operación explícita del usuario.                       |

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

El orquestador invoca `bootstrap/<componente>.sh update` para cada componente listado en `UPDATABLE_COMPONENTS` dentro de `scripts/update-tools.sh`.

| Componente     | Mecanismo de instalación         | Destino                                         | Administración | Comando de actualización                                            |
| -------------- | -------------------------------- | ----------------------------------------------- | -------------- | ------------------------------------------------------------------- |
| `actionlint`   | Descarga desde GitHub Releases   | `~/.local/bin`                                  | repositorio    | `bootstrap/actionlint.sh update`                                    |
| `hadolint`     | Descarga desde GitHub Releases   | `~/.local/bin`                                  | repositorio    | `bootstrap/hadolint.sh update`                                      |
| `checkov`      | `pipx` con `PIPX_BIN_DIR`        | `~/.local/bin`                                  | `pipx`         | `bootstrap/checkov.sh update`                                       |
| `semgrep`      | `pipx` con `PIPX_BIN_DIR`        | `~/.local/bin`                                  | `pipx`         | `bootstrap/semgrep.sh update`                                       |
| `markdownlint` | `npm install -g --prefix`        | `~/.local`                                      | `npm`          | `bootstrap/markdownlint.sh update`                                  |
| `pi`           | Instalador oficial del proveedor | Destino del proveedor; resuelto mediante `PATH` | proveedor      | `bootstrap/pi.sh update` con `pi update --self`                     |
| `opencode`     | Instalador oficial del proveedor | `~/.opencode/bin`                               | proveedor      | `bootstrap/opencode.sh update` con `opencode upgrade --method curl` |
| `herdr`        | Instalador oficial del proveedor | Destino del proveedor; resuelto mediante `PATH` | proveedor      | `bootstrap/herdr.sh update` con `herdr update`                      |
| `aws`          | Instalador oficial del proveedor | `/usr/local/aws-cli`                            | proveedor      | `bootstrap/aws.sh update` con `./aws/install --update`              |
| `chezmoi`      | Instalador oficial con `-b`      | `~/.local/bin`                                  | proveedor      | `bootstrap/chezmoi.sh update`                                       |

## Excepciones de ruta

Las herramientas que utilizan canales oficiales conservan el destino definido por el proveedor o el valor soportado por su gestor:

- **`pipx` (`checkov`, `semgrep`)**: se usa `PIPX_BIN_DIR="$HOME/.local/bin"`. Es la variable oficial de `pipx` para redirigir la ubicación de los binarios.
- **`npm` (`markdownlint`)**: se usa `npm install -g --prefix "$HOME/.local"`. El parámetro `--prefix` es el mecanismo oficial de npm para cambiar el directorio de instalación.
- **`chezmoi`**: se invoca el instalador oficial con `-b "$HOME/.local/bin"`. El parámetro `-b` permite seleccionar el directorio de instalación del binario.
- **Binarios descargados (`actionlint`, `hadolint`)**: el repositorio descarga el binario desde GitHub Releases y lo instala manualmente en `~/.local/bin`, ya que no existe un instalador oficial que permita definir un destino común.

Las herramientas instaladas mediante sus instaladores oficiales, como `pi`, `opencode`, `herdr` y `aws`, conservan el destino predeterminado del proveedor y no redefinen la ubicación de instalación desde el repositorio.

## Exclusiones

Los siguientes componentes no forman parte de `scripts/update-tools.sh`:

| Componente | Motivo                                                                                                                                    |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `node`     | Runtime administrado declarativamente por `bootstrap/node.sh` mediante `fnm`. Cambiar la versión estable requiere modificar el bootstrap. |
| `python`   | Runtime administrado declarativamente por `bootstrap/python.sh`. Conserva la versión proporcionada por la distribución.                   |
| `dotnet`   | SDK administrado declarativamente por `bootstrap/dotnet.sh`. La línea del SDK se define en el bootstrap.                                  |

Para cambiar la versión administrada por el repositorio:

1. Edita la declaración correspondiente en su bootstrap.
2. Vuelve a ejecutar `./install.sh`.

## Política de fallos

El orquestador continúa procesando todos los componentes aunque alguno falle.

| Situación                                           | Código de salida |
| --------------------------------------------------- | ---------------- |
| Todas las actualizaciones finalizaron correctamente | `0`              |
| Uno o más componentes fallaron                      | `1`              |
| Error interno del orquestador                       | `2`              |

Ejemplos de fallos individuales:

- `apt-get` falla durante la actualización.
- `sudo` no está disponible.
- `pipx` no está disponible.
- Una herramienta específica no puede actualizarse.

## Política de versiones

Las herramientas de línea de comandos se actualizan siempre a la versión estable más reciente.

Algunos runtimes y SDKs permiten mantener varias versiones instaladas. La versión efectiva de cada proyecto debe declararse mediante el mecanismo correspondiente. Por ejemplo:

- `.node-version` o `.nvmrc` para Node.js.
- `global.json` para .NET.
- Restricciones declaradas en `package.json`, cuando correspondan.

Python conserva la versión proporcionada por la distribución, salvo que el repositorio adopte en el futuro un gestor específico para múltiples versiones.

## Política de sudo y APT

- `sudo -v` se solicita antes de ejecutar operaciones que requieren elevación.
- Las operaciones sobre APT se ejecutan antes que el resto de actualizaciones.
- APT se ejecuta de forma interactiva, sin `-y` ni modificaciones de Debconf o `needrestart`.
- La actualización de AWS CLI utiliza `sudo` porque el destino oficial del instalador es `/usr/local/aws-cli`.
- No se recomienda configurar `NOPASSWD` global en `sudoers`. Si se requiere automatización, debe limitarse únicamente a los comandos utilizados por los scripts.

## Pruebas

El proyecto incluye dos niveles de pruebas para la administración de herramientas:

| Archivo                        | Propósito                                                                                                                                                                                     |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/bootstrap-scripts.bats` | Valida la estructura, permisos, sintaxis y contrato de argumentos de cada bootstrap. Recorre `UPDATABLE_COMPONENTS` para verificar la acción `update` y el rechazo de acciones no soportadas. |
| `tests/update-tools.bats`      | Valida el comportamiento del orquestador mediante stubs de los comandos externos.                                                                                                             |

Los stubs ubicados en `tests/fixtures/bin/` simulan comandos como `sudo`, `apt-get`, `pipx`, `npm` y `curl`, lo que permite ejecutar las pruebas sin conexión a Internet ni modificaciones del sistema.

## Ver también

- [`README.md`](../README.md) — Inicio rápido y comandos principales.
- [`architecture.md`](architecture.md) — Arquitectura del entorno.
- [`troubleshooting.md`](troubleshooting.md) — Problemas comunes y soluciones.
