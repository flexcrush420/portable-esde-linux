# Portable ES-DE for Linux

A fully self-contained retro gaming bundle — no installation needed.

## What is this?

**RetroBat** on Windows gives you a portable, plug-and-play retro gaming setup in a single folder. Nothing like it existed for Linux — until now.

`setup-portable-esde.sh` is a single script that builds a complete portable [ES-DE](https://es-de.org/) retro gaming bundle on any Linux machine. Fully portable: works on any machine, survives OS reinstallations, and runs from any external drive.

---

## What you get

| Application | System | Notes |
|---|---|---|
| **ES-DE** | Frontend | Portable mode — no system installation |
| **RetroArch** | 76 libretro cores | NES, SNES, Genesis, GB/GBC/GBA, N64, PS1, Saturn, Dreamcast, Arcade, MAME, MSX, Amiga, CPC, X68000, and many more |
| | | |
| **DuckStation** | PlayStation 1 | |
| **PCSX2** | PlayStation 2 | |
| **RPCS3** | PlayStation 3 | |
| **shadPS4** | PlayStation 4 | Requires Vulkan 1.3+ |
| **PPSSPP** | PlayStation Portable | |
| | | |
| **melonDS** | Nintendo DS | |
| **Azahar** | Nintendo 3DS | |
| **Ryubing** | Nintendo Switch | Ryujinx lineage |
| **Eden** | Nintendo Switch | Yuzu lineage |
| **Dolphin** | GameCube / Wii | |
| **Cemu** | Wii U | |
| | | |
| **xemu** | Original Xbox | |
| **Xenia Canary** | Xbox 360 | |
| | | |
| **MAME** | Arcade + obscure systems | Standalone — used as fallback for ADAM, Apple IIgs, Archimedes, Dragon32, FM-7, TI-99/4A, Super A'Can, etc. |
| **Supermodel** | Sega Model 3 | Community AppImage via pkgforge-dev |
| **DOSBox-X** | DOS games | |
| **86Box** | Win 9x / Retro PC | Configure with your own Windows ISO |
| **EKA2L1** | Symbian / N-Gage | |
| **Ruffle** | Adobe Flash | |
| **SimCoupe** | MGT SAM Coupé | |
| **Solarus** | Solarus engine games | |
| **VPinball** | Visual Pinball | BGFX + GL builds |
| **3dSen** | NES in 3D | Commercial — buy on [Steam](https://store.steampowered.com/app/1147940/3dSen/) or [itch.io](https://geod.itch.io/3dsen), auto-detected if installed |

All configured for fullscreen, portable paths, and your chosen internal resolution out of the box.

---

## Quick start

```bash
curl -LO https://raw.githubusercontent.com/flexcrush420/portable-esde-linux/main/setup-portable-esde.sh
chmod +x setup-portable-esde.sh
./setup-portable-esde.sh
```

If `whiptail` isn't installed, the script will offer to install it for you (one-line `apt`/`dnf`/`pacman`/`zypper` invocation — only the first prompt is plain text; everything else is in a TUI).

After that, you'll click through a series of dialogs:

1. **Where to install** (defaults to `./ES-DE-Portable` in the current directory)
2. **Which theme** to use — Art Book Next, Carbon, IISU Interpreted, Linear (ES-DE built-in), Meringue, or Slick Remixed
3. **RetroBat or ROM-pack paths to import** (optional, repeatable)
4. **Transfer mode** — copy (keep originals) or cut (move)
5. **Internal resolution** — Native / 1080p / 1440p / 4K
6. **Desktop shortcut** — yes or no
7. **Full install vs Custom** —
   - **Full** downloads every emulator + every libretro core (~3 GB)
   - **Custom** opens two checklists: pick standalone emulators, then pick libretro cores. Your selections are remembered in `.setup-selections.cfg` for next run.

Then the script downloads, configures, and installs everything. Add your ROMs to `ROMs/<system>/`, BIOS files to `ROMs/bios/`, and launch with `./launch.sh`.

---

## Requirements

| Requirement | Notes |
|---|---|
| **Linux** | Any modern distro — Ubuntu, Mint, Arch, Fedora, openSUSE, Pop!_OS etc. |
| **bash 4.0+** | Standard on all distros |
| **curl** | For downloads |
| **python3** | For gamelist processing |
| **unzip** | For theme extraction |
| **whiptail** | For interactive dialogs. The script will offer to install it if missing. |
| **~15GB free space** | For emulators + cores (ROMs not included) |

> **Note:** Some AppImages require `libfuse2`. ES-DE uses the newer uruntime format and may not need it, but other emulators might. Install with `sudo apt install libfuse2` on Ubuntu/Mint, `sudo dnf install fuse-libs` on Fedora, or `sudo pacman -S fuse2` on Arch.

> **Immutable distros (Bazzite, SteamOS, Silverblue):** The script can't auto-install whiptail because `/usr` is read-only. It'll print the right manual command for your distro and ask you to re-run after installing. On SteamOS specifically: `sudo steamos-readonly disable && sudo pacman -Sy libnewt && sudo steamos-readonly enable`.

---

## Directory structure

After running the script:

```
ES-DE-Portable/
├── ES-DE_x64.AppImage          ← ES-DE frontend
├── launch.sh                   ← Run this to play
├── update.sh                   ← Update emulators and cores
├── convert-retrobat.sh         ← Import RetroBat collections anytime
├── verify-bios.sh              ← Check BIOS files per system (auto-runs after imports)
├── install-emulator.sh         ← Install a single standalone emulator on demand
├── install-core.sh             ← Install a single libretro core on demand
├── ES-DE/
│   ├── custom_systems/         ← Hack system definitions (snesh, nesh, etc.)
│   ├── settings/               ← ES-DE configuration
│   ├── gamelists/              ← Game metadata
│   └── themes/                 ← Downloaded theme
├── Emulators/
│   ├── RetroArch*.AppImage
│   ├── retroarch-cores/        ← Up to 76 .so core files
│   ├── PCSX2*.AppImage
│   └── ...                     ← All other emulators
├── ROMs/
│   ├── nes/ snes/ gb/ gba/     ← Add your ROMs here
│   ├── dreamcast/ ps2/ gc/     ← One folder per system
│   ├── ps4/ win98/             ← Newer systems
│   └── bios/                   ← BIOS files go here
├── downloaded_media/           ← Scraped artwork and videos
└── Saves/                      ← Save files and states
```

---

## BIOS files

BIOS files are required for many systems and must be sourced from hardware you own. Place them in `ROMs/bios/`.

The bundle includes a built-in **BIOS verifier** (`verify-bios.sh`) which checks 50 systems against known-good MD5 hashes sourced from emulator source code, Redump, MAME DAT, and the [Abdess/retrobios](https://github.com/Abdess/retrobios) database. It reports three states per system:

- **PASS** — required BIOS present and hash-verified
- **WARN** — system will work; optional BIOS missing or hash mismatched
- **FAIL** — system will not boot — required BIOS missing or hash mismatched

When a file is present but the hash is wrong (e.g. wrong-region PS1 BIOS, corrupt download), the report shows the observed vs expected MD5 inline so you can spot the cause immediately.

Run anytime:

```bash
./verify-bios.sh                # check all systems present in ROMs/
./verify-bios.sh psx            # check one specific system
./verify-bios.sh --list         # show all systems in the table
./verify-bios.sh --table        # dump the full BIOS table
```

The verifier also runs automatically after each system import in `convert-retrobat.sh`, plus a final all-system sweep when the import completes.

### Common BIOS requirements

| System | File(s) |
|---|---|
| PlayStation 1 | `scph5500.bin` / `scph5501.bin` / `scph5502.bin` (region-specific, any one works) |
| PlayStation 2 | PCSX2 BIOS files |
| PlayStation 3 | PS3 firmware (`PS3UPDAT.PUP`) via RPCS3 |
| PlayStation 4 | Firmware modules via shadPS4 (dumped from your PS4) |
| Sega Saturn | `sega_101.bin` (NTSC-J) or `mpr-17933.bin` (NTSC-U/PAL) |
| Sega CD / Mega-CD | `bios_CD_J.bin` / `bios_CD_U.bin` / `bios_CD_E.bin` |
| Sega Dreamcast | `dc_boot.bin` (recommended, HLE fallback exists) |
| Nintendo DS | `bios7.bin`, `bios9.bin`, firmware |
| PC Engine CD | `syscard3.pce` |
| Neo Geo | `neogeo.zip` |
| NeoGeo CD | `neocd_z.rom` (or `_t.rom` / `_f.rom`) |
| NAOMI / Atomiswave | `naomi.zip` / `awbios.zip` |
| 3DO | `panafz1.bin` or `panafz10.bin` |
| Atari Lynx | `lynxboot.img` |
| Atari 5200 | `5200.rom` |
| ColecoVision | `colecovision.rom` |
| Intellivision | `exec.bin` + `grom.bin` |
| Commodore Amiga | Kickstart ROMs (`kick34005.A500`, `kick40068.A1200`, etc.) |
| Win9x / Retro PC | Windows installation ISO (your own licensed copy) via 86Box |

Run `./verify-bios.sh --list` to see all 50 systems with BIOS data.

---

## Importing from RetroBat (or any ROM collection)

If you have an existing RetroBat collection, a ROM pack from elsewhere, or even a single-system folder, the script can import it:

```bash
# During initial setup — answer the path prompt with one or more sources
./setup-portable-esde.sh

# Or anytime after setup using the included converter
./convert-retrobat.sh
```

The importer accepts three input shapes per path:

- **Full RetroBat install** (folder containing `roms/`, `bios/`, `system/`, etc.)
- **ROM pack collection** (folder containing system subfolders like `psx/`, `snes/`, `dreamcast/`)
- **Single-system folder** (e.g. a `dreamcast/` folder directly) — system name is inferred from the directory name

Per system, the importer:

- Maps RetroBat media types to ES-DE's folder structure (thumbnails → 3dboxes, box2d → covers, etc.)
- Also handles EmulationStation/Batocera-style flat layouts where media files use type suffixes (e.g. `<rom>-image.png`, `<rom>-marquee.png`, `<rom>-Video.mp4`)
- Cleans gamelists (strips incompatible tags, flattens paths for category-organised systems)
- Handles system name differences (`snesh` → own hack system, `sfc` → `snes`, etc.)
- Runs `verify-bios.sh` for that system to report PASS/WARN/FAIL
- **Auto-detects missing emulators or cores** — if you imported GameCube ROMs but didn't install Dolphin during setup, you'll get a whiptail prompt: *"Install Dolphin now? [Yes/No]"*. Same for missing RetroArch + libretro cores. Skips quietly if you decline.

Supports multiple sources in one pass, and offers cut mode (moves files without doubling disk usage) or copy mode.

---

## On-demand emulator installation

`install-emulator.sh` and `install-core.sh` are bundled in the directory and can be invoked directly for ad-hoc installation, no need to re-run setup:

```bash
./install-emulator.sh dolphin       # install Dolphin standalone
./install-emulator.sh --help        # list all 23 installable standalone emulators
./install-core.sh mednafen_psx_hw   # install one libretro core from buildbot
./install-core.sh --help            # usage and notes
```

Both are called automatically by `convert-retrobat.sh` when it detects a system whose emulator wasn't installed during initial setup — you'll be prompted before any download begins.

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

## In-game controls

The bundle pre-configures two universal RetroArch shortcuts that work on any controller after autoconfig matches your pad. No setup required — they're ready as soon as you launch a game.

| Shortcut | Action |
|---|---|
| **L3 + R3** (click both analog sticks) | Open the RetroArch Quick Menu |
| **L1 + R1 + Start + Select** | Exit the game, return to ES-DE |
| **Escape** (keyboard) | Same as the L1+R1+Start+Select combo — exits to ES-DE |

The four-button combo is intentional — easy to remember (all four shoulder/center buttons at once), works on every pad including arcade sticks and 8BitDo retro pads that lack clickable analog sticks, and impossible to trigger accidentally during gameplay.

For **per-button hotkeys** (Save State, Load State, Fast Forward, Screenshot, Rewind, etc.), these need a one-time per-controller binding via the RetroArch menu, because RetroArch's `*_btn` hotkeys use physical button indices that vary per pad. To set them up:

1. Launch any game
2. Open the Quick Menu (L3 + R3, or L1+R1+Start+Select, or Escape)
3. Navigate to **Settings → Input → Hotkeys**
4. Bind **Hotkey Enable** to a button (usually Select), then bind each action — e.g. Save State → R1, Load State → L1, Fast Forward → R2
5. Bindings persist across all games for that controller

Once set, hotkeys work as **Hotkey Enable + action button** (e.g. Select + R1 = save state). Repeat once per controller.

**Non-RetroArch standalones** (Dolphin, PCSX2, RPCS3, melonDS, etc.) each have their own controller-configuration UIs accessed from within the emulator's own menus — usually under Options → Controllers, Input → Controller Setup, or similar.

---

## Updating

Run the included update script anytime to check for newer versions:

```bash
./update.sh
```

It checks every standalone emulator against its latest GitHub release, shows you what's changed, and asks (via whiptail) before downloading anything. RetroArch and RPCS3 are nightly builds — re-downloading always gets the latest. All 76 RetroArch cores can also be updated in one go from buildbot.libretro.com.

To update ES-DE itself, the update script will prompt you to re-download from es-de.org when a new version is detected.

---

## Themes

The following themes are available during setup:

| Theme | Description |
|---|---|
| [Art Book Next](https://github.com/anthonycaccese/art-book-next-es-de) | Coffee-table-book aesthetic, polished and image-rich (default) |
| [Carbon](https://github.com/lilbud/carbon-es-de) | Classic clean look (RetroPie heritage) |
| [IISU Interpreted](https://github.com/VictorUnlocked/iisu-interpreted-es-de) | Clean port of the upcoming iiSU UI |
| **Linear** | ES-DE's built-in default — no download needed |
| [Meringue](https://github.com/kthod861/meringue-es-de) | Soft, light pastel theme |
| [Slick Remixed](https://github.com/Weestuarty/slick-es-de) | Refined remake of the classic Slick theme |

Additional themes can be installed anytime via ES-DE's built-in Theme Downloader (ES-DE menu → UI Settings → Theme Downloader).

---

## First-run notes for specific emulators

Some emulators require one-time setup that can't be scripted due to legal/firmware constraints:

- **RPCS3** — requires PlayStation 3 firmware installed via `File → Install Firmware` on first launch
- **shadPS4** — requires PS4 firmware modules placed in `Emulators/config/shadps4/sys_modules/` dumped from your own PS4
- **xemu** — requires an Xbox HDD image and MCPX/BIOS files configured on first launch
- **86Box** — requires a Windows installation ISO and ROM set to create virtual machines
- **Azahar / Ryubing / Eden** — require Switch firmware and `prod.keys` / `title.keys` dumped from your own hardware
- **EKA2L1** — requires Symbian/N-Gage ROM dumps from your own hardware
- **3dSen** — commercial application, purchase on [Steam](https://store.steampowered.com/app/1147940/3dSen/) or [itch.io](https://geod.itch.io/3dsen)

---

## Compatibility

Tested on **Linux Mint** and **Ubuntu**. Should work on any distro with bash 4.0+, curl, python3, unzip, and whiptail (or one of the immutable-distro paths above).

---

## Credits

- [ES-DE](https://es-de.org/) — the frontend that makes this possible
- [RetroArch](https://www.retroarch.com/) and the [libretro](https://www.libretro.com/) core authors
- [pkgforge-dev](https://github.com/pkgforge-dev) — community AppImage builds for many of the bundled emulators
- [Abdess/retrobios](https://github.com/Abdess/retrobios) — source-verified BIOS hash database used by `verify-bios.sh`
- All the emulator teams whose work powers this bundle
- [Team Pixel Nostalgia](https://pixelnostalgia.github.io/) — [ES-DE - Convert RGS ROMpacks for use with ES-DE](https://www.youtube.com/watch?v=ee0j1yGnqwA)

---

## Legal

This script downloads open-source emulator software. It does not include, distribute, or facilitate downloading of any copyrighted game ROMs, BIOS files, or firmware. You are responsible for ensuring you have the legal right to use any game software you run with this bundle.

---

*Made with ❤️ for the Linux retro gaming community*
