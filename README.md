# Portable ES-DE for Linux

<p align="center">
<strong>A portable Linux retro gaming bundle built around ES-DE, RetroArch, curated AppImages, source ports, import tooling, BIOS checks, and update helpers.</strong>
</p>

<p align="center">
<a href="https://es-de.org/"><img alt="Frontend" src="https://img.shields.io/badge/frontend-ES--DE-4ea94b"></a>
<a href="https://www.retroarch.com/"><img alt="RetroArch" src="https://img.shields.io/badge/core_system-RetroArch-cc0000"></a>
<img alt="Theme" src="https://img.shields.io/badge/theme-Art%20Book%20Next-green">
<img alt="Platform" src="https://img.shields.io/badge/platform-Linux-blue">
<img alt="Install" src="https://img.shields.io/badge/install-portable-purple">
</p>

> RetroBat style portability for Linux, built around ES-DE, curated AppImages, RetroArch cores, tidy media paths, and a safer import workflow.

![ES-DE Portable Ports Preview](ports-system-preview.png)

## Quick start

```bash
curl -LO https://raw.githubusercontent.com/flexcrush420/portable-esde-linux/main/setup-portable-esde.sh
chmod +x setup-portable-esde.sh
./setup-portable-esde.sh
```

Default install location:

```text
./ES-DE
```

Launch:

```bash
cd ./ES-DE
./launch.sh
```

Run a read only import audit:

```bash
./import-collection.sh --audit
```

## What this builds

| Layer | Included |
|---|---|
| Frontend | ES-DE in portable mode |
| Theme policy | Art Book Next by default. Unsupported standalone ports are grouped under `ports` so missing logos do not break the frontend look |
| Libretro | RetroArch AppImage plus curated `.so` cores |
| Standalone emulators | Dolphin, DuckStation, PCSX2, RPCS3, PPSSPP, Azahar, melonDS, Cemu, xemu, Xenia Canary, shadPS4, MAME, Supermodel, VPinball, and more |
| Ports and engines | Launchers inside `ROMs/ports`, backed by bundled AppImages in `Emulators/` |
| Importer | RetroBat and Batocera style collection importer with media, gamelist, BIOS, and nested system handling |
| Maintenance | Update script for emulator AppImages and RetroArch cores |

## Highlights

- Portable folder structure, no global install required.
- ES-DE custom systems and find rules are generated automatically.
- Art Book Next is installed as the default theme.
- Unsupported standalone ports are grouped under `ports`, keeping theme art clean.
- RetroBat media folders are mapped to ES-DE media folders.
- Gamelists are merged and cleaned instead of blindly overwritten.
- BIOS files are routed to `ROMs/bios`, including BIOS files found beside ROMs.
- Generic BIOS archives are extracted into `ROMs/bios` without overwriting existing files.
- MSU and tidy nested systems are supported, including `snes-msu`, `msu-md`, `nes-msu`, and `neogeomvs`.
- Setup is rerun safe. User configs are preserved and managed generated files are backed up before replacement.

<details>
<summary><strong>Supported system categories</strong></summary>

| Category | Examples |
|---|---|
| Nintendo | NES, SNES, N64, GameCube, Wii, Wii U, DS, 3DS, Switch, hacks and homebrew variants |
| Sega | Master System, Genesis/Mega Drive, Sega CD, 32X, Saturn, Dreamcast, Model 3 |
| Sony | PlayStation, PlayStation 2, PlayStation 3, PlayStation 4, PSP |
| Microsoft | Xbox, Xbox 360, Windows 9x, Windows launchers |
| Arcade | Arcade, FinalBurn Neo, CPS1/2/3, MAME software list systems |
| Computers | Amiga, Atari ST, C64, MSX, Sharp X68000, DOS, PC variants |
| Ports | Doom ports, Diablo, Theme Hospital, Commander Keen, Jazz Jackrabbit, Tyrian 2000, OpenBOR, OpenRCT2, OpenLoco, OpenRA, Half-Life, Quake II, Quake III, Doom 3 |

</details>

<details>
<summary><strong>Ports and engines currently wired</strong></summary>

These launch from the visible ES-DE `ports` system for Art Book Next compatibility. The actual AppImages live in `Emulators/`.

| Port launcher | Runtime source |
|---|---|
| `DevilutionX.sh` | DevilutionX AppImage Enhanced |
| `Theme Hospital (CorsixTH).sh` | CorsixTH AppImage Enhanced |
| `Commander Genius.sh` | Commander Genius AppImage |
| `C-Dogs SDL.sh` | C-Dogs SDL AppImage |
| `EDuke32.sh` | EDuke32 AppImage |
| `Ghostship.sh` | Ghostship AppImage Enhanced |
| `Nugget Doom.sh` | Nugget Doom AppImage Enhanced |
| `Crispy Doom.sh` | Crispy Doom AppImage |
| `OpenBOR.sh` | OpenBOR, AppImage if upstream release provides one |
| `OpenJazz.sh` | OpenJazz AppImage |
| `OpenTyrian 2000.sh` | OpenTyrian2000 AppImage |
| `OpenRCT2.sh` | OpenRCT2 AppImage Enhanced |
| `OpenLoco.sh` | OpenLoco AppImage |
| `OpenRA.sh` | OpenRA AppImage Enhanced |
| `Half-Life (Xash3D FWGS).sh` | Xash3D FWGS AppImage Enhanced |
| `Quake II (Yamagi).sh` | Yamagi Quake II AppImage |
| `Quake III Arena (ioquake3).sh` | ioquake3 AppImage |
| `Doom 3 (dhewm3).sh` | dhewm3 AppImage |

</details>

<details>
<summary><strong>Directory structure</strong></summary>

```text
ES-DE/
├── ES-DE_x64.AppImage
├── launch.sh
├── update.sh
├── import-collection.sh
├── fetch-vpx-patches.sh
├── ES-DE/
│   ├── custom_systems/
│   ├── settings/
│   ├── gamelists/
│   └── themes/
├── Emulators/
│   ├── RetroArch*.AppImage
│   ├── retroarch-cores/
│   └── standalone emulator AppImages and wrappers
├── ROMs/
│   ├── bios/
│   ├── ports/
│   │   ├── OpenTyrian 2000.sh
│   │   ├── OpenRCT2.sh
│   │   └── other port launchers
│   ├── nes/
│   ├── snes/
│   ├── megadrive/
│   ├── psx/
│   └── one folder per supported system
├── downloaded_media/
└── Saves/
```

</details>

<details>
<summary><strong>Importing from RetroBat or Batocera style collections</strong></summary>

The importer can be run during setup or later:

```bash
./import-collection.sh
```

Read only audit mode:

```bash
./import-collection.sh --audit
```

The importer handles:

- ROM folder remaps, for example `neogeomvs` to `neogeo/neogeomvs`.
- MSU nesting, for example `snes-msu` to `snes/snes-msu`.
- ProjectNested NES-MSU as `ROMs/nes/nes-msu` with a custom `nes-msu` launcher using Snes9x.
- Port and engine folders routed under `ROMs/ports/<engine>` for theme safety.
- Media conversion from RetroBat folder names to ES-DE media folders.
- Gamelist path rewriting for nested folders.
- BIOS routing to `ROMs/bios`.
- Existing file protection.

</details>

<details>
<summary><strong>BIOS and firmware notes</strong></summary>

BIOS files are not included. Use files dumped from hardware you own.

Common examples:

| System | Examples |
|---|---|
| PlayStation | `scph5500.bin`, `scph5501.bin`, `scph5502.bin` |
| PlayStation 2 | PCSX2 BIOS files |
| Dreamcast | `dc_boot.bin`, `dc_flash.bin` |
| Sega CD | `bios_CD_J.bin`, `bios_CD_U.bin`, `bios_CD_E.bin` |
| Neo Geo | `neogeo.zip` |
| PC Engine CD | `syscard3.pce` |

The importer checks BIOS status and routes recognised BIOS sidecars into `ROMs/bios`.

</details>

<details>
<summary><strong>Updating</strong></summary>

```bash
./update.sh
```

The update helper checks emulator AppImages and RetroArch cores. It keeps existing files unless you choose to replace them.

</details>

## Requirements

| Requirement | Notes |
|---|---|
| Linux | Tested target is Linux desktop, especially Mint/Ubuntu style systems |
| bash 4.0+ | Standard on most distributions |
| curl | Downloads release assets |
| python3 | Gamelist processing |
| unzip | Theme and archive extraction |
| Optional tools | `7z` and `unrar` improve BIOS and archive extraction |
| Free space | Roughly 15GB+ for emulator assets before ROMs/media |

Some AppImages may require `libfuse2` on certain distributions, although many newer PkgForge AppImages use runtimes that avoid that dependency.

## First run notes

Some emulators still need one time setup because firmware, keys, BIOS files, game data, or licensing cannot be bundled.

- RPCS3 requires PlayStation 3 firmware installed through RPCS3.
- shadPS4 requires dumped PS4 firmware modules.
- xemu requires Xbox BIOS/HDD setup.
- 86Box requires your own OS install media and machine configuration.
- Switch family tools require your own firmware and keys.
- Source ports such as DevilutionX, CorsixTH, Commander Genius, EDuke32, OpenJazz, OpenRCT2, OpenLoco, Xash3D, Yamagi Quake II, ioquake3, and dhewm3 may need original game data.

## Legal

This project downloads open source emulator software, source ports, and helper assets. It does not include commercial games, ROMs, BIOS files, firmware, keys, or copyrighted game data.

Only import or use software and data you are legally allowed to use.

---

Made with ❤️ for the Linux retro gaming community
