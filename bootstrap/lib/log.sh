#!/bin/bash
# Logger reutilizable. Lo usan bootstrap/*.sh y scripts/*.sh.
#
# Convenciones:
#   log_info / log_warn / log_error / log_fatal → solo registran; no abortan.
#   die                                          → registra FATAL y termina con código 1.
#
# Los mensajes se escriben en stderr para no contaminar stdout en pipelines.

if [ -n "${_BOOTSTRAP_LIB_LOG_LOADED:-}" ]; then
  return 0
fi
_BOOTSTRAP_LIB_LOG_LOADED=1

log_info() {
  printf '[INFO] %s\n' "$*" >&2
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

log_fatal() {
  printf '[FATAL] %s\n' "$*" >&2
}

die() {
  log_fatal "$@"
  exit 1
}