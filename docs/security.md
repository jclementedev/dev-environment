# Seguridad

## Lo que nunca va al repo

- Claves SSH privadas (`~/.ssh/id_*` privadas)
- Claves GPG privadas (`~/.gnupg/private-keys-v1.d/*`)
- Tokens (`ghp_*`, `glpat-*`, `AKIA*`, etc.)
- Credenciales cloud (`~/.aws/credentials`, `~/.config/doctl/*`)
- Certificados (`*.pem`, `*.key`, `*.p12`)

`dotfiles/private_dot_*` se incluyen en el repositorio. chezmoi aplica permisos
`0600` en el destino, pero `private_` no cifra ni excluye contenido de Git.
No usarlo para claves privadas, tokens o credenciales.

## Pre-chezmoi backup

`install.sh` crea un backup defensivo en
`~/.local/state/dev-env-bootstrap/backups/pre-chezmoi/` antes del primer apply.
Solo contiene configuración, no claves.

## GitHub y claves de host

La instalación base no crea estado de cuentas GitHub ni modifica
`~/.ssh/known_hosts`. La configuración de GitHub es explícita y posterior con
`scripts/account.sh setup-primary` o `scripts/account.sh add`.

Al verificar una cuenta, `account.sh` obtiene las claves de host de GitHub,
valida sus fingerprints SHA-256 contra los publicados oficialmente y actualiza
solo esas entradas en `known_hosts`. La conexión usa
`StrictHostKeyChecking=yes`: no acepta claves desconocidas y rechaza cualquier
discrepancia.

## Docker group

Agregar un usuario al grupo `docker` en un sistema con daemon Docker rootful permite ejecutar contenedores con privilegios de root sobre el host: el contenedor puede montar directorios arbitrarios del host, leer archivos protegidos y escribir en cualquier ubicación. Esto convierte al grupo `docker` en **equivalente a root** para todos los efectos prácticos de seguridad.

Esta es una decisión de diseño de Docker, no del proyecto. Si esto es inaceptable para su ambiente, no agregue usuarios al grupo `docker` y gestione contenedores con `sudo docker` según necesite.

## Gitleaks en CI — version y SHA256 anclados

El job `scan` de `.github/workflows/ci.yml` descarga gitleaks mediante un tarball
verificado contra una SHA256 anclada en el workflow.

**Valores actuales** (en `ci.yml` job `scan`):
```
GITLEAKS_VERSION=8.30.1
GITLEAKS_TARBALL_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
```

**Procedimiento de rotación:**

1. Elegir la versión deseada en `https://github.com/gitleaks/gitleaks/releases`.
2. Descargar la checksum file para esa versión:
   ```bash
   curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/vVERSION/gitleaks_VERSION_checksums.txt
   ```
3. Extraer la SHA256 del tarball linux_x64:
   ```bash
   grep linux_x64.tar.gz gitleaks_VERSION_checksums.txt | awk '{print $1}'
   ```
4. Actualizar `GITLEAKS_VERSION` y `GITLEAKS_TARBALL_SHA256` en `.github/workflows/ci.yml` job `scan`.
5. Confirmar que CI pasa con los nuevos valores.

## Si se confirma un secreto en un commit por error

1. Asumirlo comprometido desde el push.
2. `git rm --cached <archivo>`.
3. Reescribir historial (`git filter-repo`).
4. Rotar la credencial.
5. Auditar accesos del servicio.
