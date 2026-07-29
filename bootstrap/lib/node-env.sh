#!/bin/bash
# Expone Node.js y npm administrados por fnm en el proceso Bash actual.
#
# Requiere que lib/log.sh haya sido cargado previamente.

load_node_env()
{
  local fnm_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
  local fnm_bin="$fnm_dir/fnm"

  if [ ! -x "$fnm_bin" ]; then
    log_error "node: fnm no está disponible; ejecuta bootstrap/node.sh primero"
    return 1
  fi

  if ! eval "$("$fnm_bin" env --shell bash)"; then
    log_error "node: no se pudo inicializar el entorno de fnm"
    return 1
  fi

  if ! command -v node >/dev/null 2>&1; then
    log_error "node: node no quedó disponible tras inicializar fnm"
    return 1
  fi

  if ! command -v npm >/dev/null 2>&1; then
    log_error "node: npm no quedó disponible tras inicializar fnm"
    return 1
  fi
}