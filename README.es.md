# ntfs4mac

**Lee y escribe discos NTFS en macOS: gratis, sin extensión de kernel y sin bajar la seguridad.**

[English](README.md)

macOS solo puede *leer* NTFS. Las soluciones habituales son de pago (Paragon, Tuxera) o
usan macFUSE, cuya extensión de kernel en Apple Silicon te obliga a entrar en Recuperación
y bajar la seguridad del Mac. `ntfs4mac` evita ambas cosas:

| | ntfs4mac | macFUSE + ntfs-3g | Paragon / Tuxera |
|---|---|---|---|
| Precio | Gratis | Gratis | ~20–30 USD |
| Extensión de kernel | **No** | Sí | Depende |
| Bajar seguridad en Apple Silicon | **No** | Sí | — |
| Reiniciar | **No** | Sí | Depende |

Compila [ntfs-3g](https://github.com/tuxera/ntfs-3g) (el driver NTFS open source de
referencia) contra [FUSE-T](https://www.fuse-t.org), una implementación de FUSE que corre
entera en espacio de usuario y le sirve el disco a macOS mediante un servidor NFS local.

Probado en macOS 26 (Tahoe) con Apple Silicon (M1 Pro). En Macs Intel también debería funcionar.

## Instalación

Necesitas [Homebrew](https://brew.sh) y las Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/edgarlugo/ntfs4mac.git
cd ntfs4mac
./ntfs4mac install
```

El instalador:

1. instala FUSE-T con Homebrew (si no lo tienes),
2. instala solo las herramientas de compilación que te falten (`autoconf automake libtool pkgconf`), sin actualizar el resto de tus paquetes,
3. descarga ntfs-3g `2022.10.3` y **verifica su SHA-256**,
4. lo compila para tu CPU usando todos los núcleos,
5. lo instala en `/usr/local/ntfs4mac` (propiedad de root, porque se ejecuta con `sudo`) y deja `ntfs4mac` en `/usr/local/bin`.

Te pide la contraseña dos veces: una para FUSE-T y otra para instalar.

## Uso

```bash
ntfs4mac list                    # ver tus discos NTFS
ntfs4mac mount                   # pasar a lectura/escritura el (único) disco NTFS
ntfs4mac mount "Mi Disco"        # o elegir uno por nombre…
ntfs4mac mount disk4s2           # …o por dispositivo
ntfs4mac mount --all             # todos los discos NTFS
ntfs4mac unmount                 # vaciar caché y desmontar antes de desconectar
```

```
$ ntfs4mac list
DEVICE     NAME                         STATE       MOUNT POINT
disk4s2    Mi Disco                     read-write  /Volumes/Mi Disco
```

El disco aparece en el Finder como siempre. Cada vez que lo conectas, macOS lo vuelve a
montar en solo lectura; ejecuta `ntfs4mac mount` para pasarlo a lectura/escritura.

**Ejecuta siempre `ntfs4mac unmount` antes de desconectarlo**, para que todo se escriba en el disco.

## Conviene saber

- **Errores "hibernated" / "unclean".** El *Inicio rápido* de Windows deja los discos NTFS
  medio cerrados, y escribir en ellos así puede corromper datos. ntfs4mac se niega a
  montarlos con escritura. Apaga Windows del todo (`shutdown /s /t 0`) o desactiva el Inicio
  rápido. Mientras tanto, `ntfs4mac mount --ro NOMBRE` te deja leerlo.
- **Archivos `._*`.** FUSE-T habla con macOS por NFS, que no soporta atributos extendidos,
  así que macOS los guarda como archivos ocultos `._nombre`. No hacen daño, pero se ven en
  Windows. Bórralos con `ntfs4mac clean "/Volumes/Mi Disco/carpeta"`. Para que el Finder
  tampoco cree `.DS_Store`:
  ```bash
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  ```
- **Nombres compatibles con Windows.** Se monta con `windows_names`, así macOS no puede crear
  archivos que Windows no podría abrir (`:`, `?`, `*`, puntos al final…).
- **No necesitas macFUSE.** Si lo instalaste siguiendo otras guías, puedes quitarlo:
  `brew uninstall --cask macfuse`. `ntfs4mac doctor` revisa tu instalación.

## Desinstalar

```bash
ntfs4mac uninstall
brew uninstall --cask fuse-t     # opcional
```

## Licencias

- `ntfs4mac` (este script): [MIT](LICENSE).
- **ntfs-3g**: GPL-2.0 o posterior / LGPL. Se descarga del repositorio oficial de Tuxera y se compila en tu Mac; no se redistribuye aquí.
- **FUSE-T**: lo instala Homebrew, no se redistribuye aquí. Su binario es **gratis para uso no comercial**; para uso comercial hace falta una licencia de sus autores. La libfuse que incluye es LGPL.

La escritura NTFS de ntfs-3g es madura, pero guarda copias de lo importante, como con
cualquier driver de sistema de archivos de terceros.
