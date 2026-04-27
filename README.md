# Portable ES-DE for Linux

> A fully self-contained retro gaming bundle for Linux. One script downloads and configures everything — just add ROMs and play.

![ES-DE Version](https://img.shields.io/badge/ES--DE-3.4.1-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-orange)

---

## What is this?

**RetroBat** on Windows gives you a portable, plug-and-play retro gaming setup in a single folder. Nothing like it existed for Linux — until now.

`setup-portable-esde.sh` is a single script that builds a complete portable [ES-DE](https://es-de.org/) retro gaming bundle on any Linux machine. Unplug it, plug it into another machine, and it just works.

---

## What you get

| Component | System | Notes |
|---|---|---|
| **ES-DE 3.4.1** | Frontend | Portable mode — no system installation |
| **RetroArch** | 40+ systems | NES, SNES, Genesis, GB/GBC/GBA, N64, Saturn, Dreamcast, Arcade & more |
| | ***— Sony —*** | |
| **DuckStation** | PlayStation 1 | |
| **PCSX2** | PlayStation 2 | |
| **RPCS3** | PlayStation 3 | |
| **shadPS4** | PlayStation 4 | |
| **PPSSPP** | PlayStation Portable | |
| | ***— Nintendo —*** | |
| **melonDS** | Nintendo DS | |
| **Azahar** | Nintendo 3DS | |
| **Ryubing** | Nintendo Switch | Ryujinx lineage |
| **Eden** | Nintendo Switch | Yuzu lineage |
| **Dolphin** | GameCube / Wii | |
| **Cemu** | Wii U | |
| | ***— Microsoft —*** | |
| **xemu** | Original Xbox | |
| **Xenia Canary** | Xbox 360 | |
| | ***— PC —*** | |
| **86Box** | Windows 9x / retro PC | Win95, Win98, DOS |
| **3dSen** | NES in 3D | Commercial — buy on [Steam](https://store.steampowered.com/app/1147940/3dSen/) or [itch.io](https://geod.itch.io/3dsen), auto-detected if installed |

All configured for fullscreen, portable paths, and your chosen internal resolution out of the box.

---

## Quick start

```bash
curl -LO https://raw.githubusercontent.com/flexcrush420/portable-esde-linux/main/setup-portable-esde.sh
chmod +x setup-portable-esde.sh
./setup-portable-esde.sh
```

The script will ask you:
- **Where to install** (defaults to `./ES-DE-Portable` in the current directory)
- **Which theme** to use (Epic Noir Next, Carbon, Iconic, Canvas, or ES-DE default)
- **Internal resolution** (Native / 1080p / 1440p / 4K)
- **Whether to import a RetroBat collection** (optional)
- **Whether to create a desktop shortcut**

Then it downloads everything, configures it all, and you're done. Add your ROMs to `ROMs/<system>/`, add BIOS files to `ROMs/bios/`, and launch with `./launch.sh`.

---

## Requirements

| Requirement | Notes |
|---|---|
| **Linux** | Any modern distro — Ubuntu, Mint, Arch, Fedora, openSUSE, Pop!_OS etc. |
| **bash 4.0+** | Standard on all distros |
| **curl** | For downloads |
| **python3** | For gamelist processing |
| **unzip** | For theme extraction |
| **~15GB free space** | For emulators + cores (ROMs not included) |

> **Note:** Some AppImages require `libfuse2`. ES-DE 3.4.1 uses the newer uruntime format and may not need it, but other emulators might. Install with `sudo apt install libfuse2` on Ubuntu/Mint, `sudo dnf install fuse-libs` on Fedora, or `sudo pacman -S fuse2` on Arch.

---

## Directory structure

After running the script:

```
ES-DE-Portable/
├── ES-DE_x64.AppImage          ← ES-DE frontend
├── launch.sh                   ← Run this to play
├── update.sh                   ← Update emulators and cores
├── convert-retrobat.sh         ← Import RetroBat collections anytime
├── ES-DE/
│   ├── custom_systems/         ← Hack system definitions (snesh, nesh, etc.)
│   ├── settings/               ← ES-DE configuration
│   ├── gamelists/              ← Game metadata
│   └── themes/                 ← Downloaded theme
├── Emulators/
│   ├── RetroArch*.AppImage
│   ├── retroarch-cores/        ← 40+ .so core files
│   ├── PCSX2*.AppImage
│   └── ...                     ← All other emulators
├── ROMs/
│   ├── nes/ snes/ gb/ gba/     ← Add your ROMs here
│   ├── dreamcast/ ps2/ gc/     ← One folder per system
│   ├── ps4/ windows9x/         ← Newer systems
│   └── bios/                   ← BIOS files go here
├── downloaded_media/           ← Scraped artwork and videos
└── Saves/                      ← Save files and states
```

---

## BIOS files

BIOS files are required for many systems and must be sourced from hardware you own. Place them in `ROMs/bios/`. Common requirements:

| System | File(s) |
|---|---|
| PlayStation 1 | `scph5501.bin` (and other regional variants) |
| PlayStation 2 | PCSX2 BIOS files |
| PlayStation 3 | PS3 firmware (`PS3UPDAT.PUP`) via RPCS3 |
| PlayStation 4 | Firmware modules via shadPS4 (dumped from your PS4) |
| Sega Saturn | `saturn_bios.bin` |
| Sega Dreamcast | `dc_boot.bin`, `dc_flash.bin` |
| Nintendo DS | `bios7.bin`, `bios9.bin`, firmware |
| PC Engine CD | `syscard3.pce` |
| Neo Geo | `neogeo.zip` |
| Windows 9x | Windows installation ISO (your own licensed copy) via 86Box |

---

## Importing from RetroBat

If you have an existing RetroBat collection on Windows (dual-boot or a mounted drive), the script can import it automatically — media, gamelists, and ROMs:

```bash
# During initial setup — answer yes to the RetroBat prompt
./setup-portable-esde.sh

# Or anytime after setup using the included converter
./convert-retrobat.sh
```

The importer:
- Maps all RetroBat media types to ES-DE's folder structure
- Cleans gamelists (strips incompatible tags, flattens paths for category-organised systems like C64)
- Handles system name differences between RetroBat and ES-DE (e.g. `snesh` → own hack system, `sfc` → `snes`)
- Supports multiple collections in one pass
- Offers cut mode (moves files without doubling disk usage) or copy mode

---

## Hack ROM systems

Hacked and homebrewed ROMs get their own dedicated sidebar entries rather than being mixed in with official ROMs:

| ES-DE System | Full Name |
|---|---|
| `snesh` | Super Nintendo (Hacks & Homebrew) |
| `nesh` | Nintendo Entertainment System (Hacks & Homebrew) |
| `gbh` | Game Boy (Hacks & Homebrew) |
| `gbch` | Game Boy Color (Hacks & Homebrew) |
| `gbah` | Game Boy Advance (Hacks & Homebrew) |
| `genh` | Sega Genesis (Hacks & Homebrew) |
| `n64h` | Nintendo 64 (Hacks & Homebrew) |
| `ggh` | Game Gear (Hacks & Homebrew) |

---

## Updating

Run the included update script anytime to check for newer versions:

```bash
./update.sh
```

It checks every emulator against its latest GitHub release, shows you what's changed, and asks before downloading anything. RetroArch and RPCS3 are nightly builds — re-downloading always gets the latest. All 40+ RetroArch cores can also be updated in one go from buildbot.libretro.com.

To update ES-DE itself, the update script will prompt you to re-download from es-de.org when a new version is detected.

---

## Themes

The following themes are available during setup:

| Theme | Description |
|---|---|
| [Epic Noir Next](https://github.com/anthonycaccese/epic-noir-next-es-de) | Dark cinematic — great for night gaming |
| [Carbon](https://github.com/lilbud/carbon-es-de) | Classic clean look (RetroPie heritage) |
| [Iconic](https://github.com/Siddy212/iconic-es-de) | Modern with iconic game character artwork |
| [Canvas](https://github.com/Siddy212/canvas-es-de) | Modern with easy wallpaper customization |
| Slate | ES-DE's built-in default — no download needed |

Additional themes can be installed anytime via ES-DE's built-in Theme Downloader (ES-DE menu → UI Settings → Theme Downloader).

---

## First-run notes for specific emulators

Some emulators require one-time setup that can't be scripted due to legal/firmware constraints:

- **RPCS3** — requires PlayStation 3 firmware installed via `File → Install Firmware` on first launch
- **shadPS4** — requires PS4 firmware modules placed in `Emulators/config/shadps4/sys_modules/` dumped from your own PS4
- **xemu** — requires an Xbox HDD image and MCPX/BIOS files configured on first launch
- **86Box** — requires a Windows installation ISO and ROM set to create virtual machines
- **Azahar / Ryubing / Eden** — require Switch firmware and `prod.keys` / `title.keys` dumped from your own hardware
- **3dSen** — commercial application, purchase on [Steam](https://store.steampowered.com/app/1147940/3dSen/) or [itch.io](https://geod.itch.io/3dsen)

---

## Compatibility

Tested on **Linux Mint** and **Ubuntu**. Should work on any distro with bash 4.0+, curl, python3, and unzip.

---

## Credits

- [ES-DE](https://es-de.org/) — the frontend that makes this possible
- [RetroArch](https://www.retroarch.com/) and the [libretro](https://www.libretro.com/) core authors
- [pkgforge-dev](https://github.com/pkgforge-dev) — community AppImage builds for Dolphin and melonDS
- All the emulator teams whose work powers this bundle
- [Team Pixel Nostalgia](https://pixelnostalgia.github.io/) — [ES-DE - Convert RGS ROMpacks for use with ES-DE](https://www.youtube.com/watch?v=ee0j1yGnqwA)

---

## Legal

This script downloads open-source emulator software. It does not include, distribute, or facilitate downloading of any copyrighted game ROMs, BIOS files, or firmware. You are responsible for ensuring you have the legal right to use any game software you run with this bundle.

---

*Made with ❤️ for the Linux retro gaming community*
