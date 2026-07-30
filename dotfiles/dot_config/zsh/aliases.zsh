# shellcheck shell=bash
# ~/.config/zsh/aliases.zsh — Alias compartidos del entorno dev-environment.
# Para alias personales, consulta dotfiles/README.md.

# Navegación y listado.
if command -v eza >/dev/null 2>&1; then
  alias ll='eza -lah --git --icons'
  alias la='eza -a --git --icons'
  alias l='eza --icons'
  alias tree='eza --tree --icons'

  llg()
  {
    if (( $# == 0 )); then
      print -u2 'uso: llg <patrón>'
      return 2
    fi

    eza -lah --git --icons | grep -E -- "$@"
  }
else
  alias ll='ls -lah'
  alias la='ls -A'
  alias l='ls -CF'

  llg()
  {
    if (( $# == 0 )); then
      print -u2 'uso: llg <patrón>'
      return 2
    fi

    ls -lah | grep -E -- "$@"
  }
fi

# Git.
alias gs='git status'
alias gpull='git pull'
alias gpush='git push'
alias gd='git diff'
alias gco='git checkout'
alias gcb='git checkout -b'

# Utilidades.
alias diff='diff --color=auto'
alias df='df -h'

# Abrir un archivo o directorio en el Explorador de Windows (solo WSL).
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  alias open='explorer.exe'
fi

# Navegación al directorio anterior.
alias -- -='cd -'
