# ntfs4mac

**Read & write NTFS drives on macOS — free, no kernel extension, no "Reduced Security".**

[Español](README.es.md)

macOS can only *read* NTFS. The usual fixes are either paid (Paragon, Tuxera) or require
macFUSE, whose kernel extension on Apple Silicon forces you to boot into Recovery and
lower your Mac's security. `ntfs4mac` avoids both:

| | ntfs4mac | macFUSE + ntfs-3g | Paragon / Tuxera |
|---|---|---|---|
| Price | Free | Free | ~$20–30 |
| Kernel extension | **No** | Yes | Varies |
| Lower boot security on Apple Silicon | **No** | Yes | — |
| Restart needed | **No** | Yes | Varies |

It builds [ntfs-3g](https://github.com/tuxera/ntfs-3g) (the standard open-source NTFS driver)
against [FUSE-T](https://www.fuse-t.org), a FUSE implementation that runs entirely in user
space by serving the filesystem to macOS through a local NFS server.

Tested on macOS 26 (Tahoe) on Apple Silicon (M1 Pro). Intel Macs should work too.

It comes as a **Mac app** for everyday use and a **command-line tool** for the terminal.

## The app

A Finder-like window to use your NTFS drives without the terminal:

- **One-click setup**: checks what's missing and installs it, with a live log.
- **Enable writing / Eject safely** for each drive, plus a menu bar icon for quick access.
- **File browser**: path bar, sortable columns, search, back/forward, hidden files toggle.
- **Quick Look preview and details** (kind, size, dates, location) for the selected file.
- **File operations**: new folder, rename, delete, copy in and out, drag and drop from Finder.
- Clear warnings for drives Windows left hibernated, and removal of `._*` files.
- English and Spanish.

### Get it

**Download** `ntfs4mac-app.zip` from [Releases](https://github.com/edgarlugo/ntfs4mac/releases),
unzip it and move `ntfs4mac.app` to Applications. The app is not notarized by Apple, so the
first time macOS will refuse to open it: go to **System Settings → Privacy & Security** and
click **Open Anyway**.

**Or build it yourself** (only the Command Line Tools needed, no Xcode):

```bash
git clone https://github.com/edgarlugo/ntfs4mac.git
cd ntfs4mac
./build-app.sh --install         # builds and copies it to /Applications
```

Open the app and press **Install** on the setup screen. It does exactly what
`./ntfs4mac install` does (below), and asks for your Mac password when it needs it.

## Install (command line)

You need [Homebrew](https://brew.sh) and the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/edgarlugo/ntfs4mac.git
cd ntfs4mac
./ntfs4mac install
```

The installer:

1. installs FUSE-T with Homebrew (if missing),
2. installs only the build tools you are missing (`autoconf automake libtool pkgconf`) — it won't upgrade the rest of your Homebrew packages,
3. downloads ntfs-3g `2022.10.3` and **verifies its SHA-256**,
4. compiles it for your CPU with every core,
5. installs it to `/usr/local/ntfs4mac` (root-owned, since it runs with `sudo`) and puts `ntfs4mac` in `/usr/local/bin`.

It asks for your password twice: once for FUSE-T and once to install.

## Use

```bash
ntfs4mac list                    # see your NTFS drives
ntfs4mac mount                   # remount the (only) NTFS drive read-write
ntfs4mac mount "My Drive"        # or pick one by name…
ntfs4mac mount disk4s2           # …or by device
ntfs4mac mount --all             # every NTFS drive
ntfs4mac unmount                 # flush and unmount before unplugging
```

```
$ ntfs4mac list
DEVICE     NAME                         STATE       MOUNT POINT
disk4s2    My Drive                     read-write  /Volumes/My Drive
```

The drive appears in Finder as usual. Each time you plug the drive in, macOS mounts it
read-only again; run `ntfs4mac mount` to switch it to read-write.

**Always run `ntfs4mac unmount` before unplugging** so all writes reach the disk.

## Good to know

- **"Windows is hibernated" / "unclean" errors.** Windows' *Fast Startup* leaves NTFS drives
  in a half-closed state, and writing to them then can corrupt data. ntfs4mac refuses to
  mount them read-write. Shut Windows down fully (`shutdown /s /t 0`) or turn off Fast
  Startup. Until then, `ntfs4mac mount --ro NAME` lets you read the drive.
- **`._*` files.** FUSE-T talks to macOS over NFS, which has no extended attributes, so macOS
  writes them as hidden `._name` companion files. They are harmless but show up on Windows.
  Remove them with `ntfs4mac clean "/Volumes/My Drive/folder"`. To stop Finder from
  writing `.DS_Store` files too:
  ```bash
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  ```
- **Windows-safe names.** Drives are mounted with `windows_names`, so macOS can't create
  files whose names Windows couldn't open (`:`, `?`, `*`, trailing dots…).
- **macFUSE not needed.** If you installed it while trying other guides, you can remove it:
  `brew uninstall --cask macfuse`. `ntfs4mac doctor` checks your setup.

## Uninstall

```bash
ntfs4mac uninstall
brew uninstall --cask fuse-t     # optional
```

## Licenses

- `ntfs4mac` (the script and the app): [MIT](LICENSE).
- **ntfs-3g**: GPL-2.0-or-later / LGPL. Downloaded from Tuxera's official repository and built on your Mac; not redistributed here.
- **FUSE-T**: installed from Homebrew, not redistributed here. Its binary is **free for non-commercial use**; commercial use needs a license from its authors. Its bundled libfuse is LGPL.

NTFS writing through ntfs-3g is mature, but keep backups of anything important, as with any
third-party filesystem driver.
