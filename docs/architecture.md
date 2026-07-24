# Arquitectura

## Flujo de instalación

```
bootstrap.sh (valida Ubuntu, clona o actualiza el repositorio)
  └─ install.sh (orquestador)
       ├─ validar plataforma Ubuntu soportada
       ├─ sudo -v (cache)
       ├─ bootstrap/*  →  instalar herramientas requeridas y opcionales
       ├─ crear datos iniciales de Chezmoi
       └─ chezmoi apply  →  dotfiles en $HOME

post-instalación (opcional)
  └─ scripts/account.sh setup-primary  →  clave, verificación y estado GitHub
```

`bootstrap/dev-tools.sh` es un componente opcional que instala las herramientas
de calidad usadas por el proyecto: Bats, ShellCheck y shfmt. Homebrew no forma
parte del flujo predeterminado de `install.sh`; `bootstrap/brew.sh` se mantiene
como un script separado.
