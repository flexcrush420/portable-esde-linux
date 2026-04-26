#!/usr/bin/env bash
#=============================================================================
#  ____            _        _     _        _____ ____        ____  _____
# |  _ \ ___  _ __| |_ __ _| |__ | | ___  | ____/ ___|      |  _ \| ____|
# | |_) / _ \| '__| __/ _` | '_ \| |/ _ \ |  _| \___ \ _____| | | |  _|
# |  __/ (_) | |  | || (_| | |_) | |  __/ | |___ ___) |_____| |_| | |___
# |_|   \___/|_|   \__\__,_|_.__/|_|\___| |_____|____/      |____/|_____|
#
#  All-in-One Portable ES-DE Setup for Linux
#  https://github.com/flexcrush420/portable-esde-linux
#
#  Creates a fully self-contained ES-DE retro gaming bundle:
#    ✓ ES-DE frontend in portable mode
#    ✓ RetroArch + essential cores for every bundled system
#    ✓ Standalone emulators (PCSX2, RPCS3, Dolphin, etc.)
#    ✓ Pre-configured es_find_rules.xml with relative paths
#    ✓ Directory structure for ROMs, BIOS, saves, and media
#
#  Just add your ROMs and BIOS files, then ./launch.sh
#
#  Usage:  chmod +x setup-portable-esde.sh && ./setup-portable-esde.sh
#  Re-run: safely skips already-downloaded files
#=============================================================================
set -euo pipefail

VERSION="1.0.0"
ESDE_VERSION="3.4.1"

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "   ${GREEN}✓${NC} $1"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; }
info() { echo -e "   ${CYAN}→${NC} $1"; }

#=============================================================================
# INTERACTIVE INSTALL PATH
#=============================================================================
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Portable ES-DE Setup v${VERSION} (ES-DE ${ESDE_VERSION})          ║${NC}"
echo -e "${BOLD}║  A complete retro gaming bundle for Linux             ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

DEFAULT_PATH="$(pwd)/ES-DE-Portable"

echo -e "Where would you like to install the portable ES-DE bundle?"
echo -e "  Default: ${CYAN}${DEFAULT_PATH}${NC}"
echo ""
read -rp "Install path (press Enter for default): " USER_PATH

BASE="${USER_PATH:-$DEFAULT_PATH}"

# Expand ~ if used
BASE="${BASE/#\~/$HOME}"

# Make absolute
BASE="$(realpath -m "$BASE")"

echo ""
echo -e "Installing to: ${BOLD}${BASE}${NC}"
echo ""

# Check if directory exists and has content
if [[ -d "$BASE" ]] && [[ -n "$(ls -A "$BASE" 2>/dev/null)" ]]; then
    echo -e "${YELLOW}Directory already exists and is not empty.${NC}"
    echo "  Existing files will be preserved. Only missing items will be added."
    echo ""
    read -rp "Continue? (Y/n): " CONTINUE
    [[ "${CONTINUE,,}" == "n" ]] && echo "Aborted." && exit 0
    echo ""
fi

EMUS="$BASE/Emulators"
ROMS="$BASE/ROMs"
ESDE_DATA="$BASE/ES-DE"         # ES-DE --home puts all its data here

# ── Theme selection (ask upfront so user can walk away during downloads) ──
EXISTING_THEMES=0
if [[ -d "$ESDE_DATA/themes" ]]; then
    EXISTING_THEMES=$(find "$ESDE_DATA/themes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
fi
if ((EXISTING_THEMES > 0)); then
    THEME_NAME=""
    THEME_SKIP_REASON="already installed"
else
    echo "Choose a default theme (you can always change or add more later"
    echo "via ES-DE's built-in Theme Downloader):"
    echo ""
    echo -e "    ${BOLD}1)${NC} Epic Noir Next    — Dark cinematic, great for night gaming"
    echo -e "    ${BOLD}2)${NC} Carbon            — Classic clean look (RetroPie heritage)"
    echo -e "    ${BOLD}3)${NC} Iconic            — Modern with famous game characters"
    echo -e "    ${BOLD}4)${NC} Canvas            — Modern with easy wallpaper customization"
    echo -e "    ${BOLD}5)${NC} Slate (ES-DE default) — Skip download, use built-in theme"
    echo ""
    read -rp "  Theme [1-5] (default: 1): " THEME_CHOICE
    THEME_CHOICE="${THEME_CHOICE:-1}"

    case "$THEME_CHOICE" in
        1)
            THEME_NAME="epic-noir-next-es-de"
            THEME_REPO="https://github.com/anthonycaccese/epic-noir-next-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="Epic Noir Next"
            THEME_ZIPDIR="epic-noir-next-es-de-main"
            ;;
        2)
            THEME_NAME="carbon-es-de"
            THEME_REPO="https://github.com/lilbud/carbon-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="Carbon"
            THEME_ZIPDIR="carbon-es-de-main"
            ;;
        3)
            THEME_NAME="iconic-es-de"
            THEME_REPO="https://github.com/Siddy212/iconic-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="Iconic"
            THEME_ZIPDIR="iconic-es-de-main"
            ;;
        4)
            THEME_NAME="canvas-es-de"
            THEME_REPO="https://github.com/Siddy212/canvas-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="Canvas"
            THEME_ZIPDIR="canvas-es-de-main"
            ;;
        5|*)
            THEME_NAME=""
            THEME_LABEL="Slate (built-in)"
            ;;
    esac
    echo ""
fi

# ── RetroBat import prompt ──
RETROBAT_PATHS=()
RETROBAT_COPY_ROMS=""
echo "Import existing RetroBat collection(s)? (copies media, gamelists, optionally ROMs)"
echo "  Enter the path to any RetroBat folder containing a 'roms' subfolder."
echo "  You can add as many as you like. Leave blank when done."
echo ""

while true; do
    [[ ${#RETROBAT_PATHS[@]} -eq 0 ]] && PROMPT="Path" || PROMPT="Another path"
    read -rp "  $PROMPT (blank to continue): " RETROBAT_INPUT

    [[ -z "$RETROBAT_INPUT" ]] && break

    RETROBAT_INPUT="${RETROBAT_INPUT/#\~/$HOME}"
    RETROBAT_INPUT="$(realpath -m "$RETROBAT_INPUT")"

    if [[ -d "$RETROBAT_INPUT/roms" ]]; then
        RETROBAT_PATHS+=("$RETROBAT_INPUT")
        echo -e "   ${GREEN}✓${NC} Added: $RETROBAT_INPUT"
    else
        echo -e "   ${YELLOW}⚠${NC} No 'roms' folder found at $RETROBAT_INPUT — skipping"
    fi
done

if [[ ${#RETROBAT_PATHS[@]} -gt 0 ]]; then
    echo ""
    # ── Cut or copy? ──
    RETROBAT_MOVE=""
    echo "  How should files be transferred?"
    echo -e "    ${BOLD}C)${NC} Copy  — keep originals (safe, uses extra space)"
    echo -e "    ${BOLD}X)${NC} Cut   — move files as they're imported (no extra space needed)"
    echo ""
    read -rp "  [C/x]: " MOVE_CHOICE
    [[ "${MOVE_CHOICE,,}" == "x" ]] && RETROBAT_MOVE="yes"
    [[ "$RETROBAT_MOVE" == "yes" ]] \
        && echo -e "   ${GREEN}✓${NC} Cut mode — files will be moved, not copied" \
        || echo -e "   ${GREEN}✓${NC} Copy mode — originals will be kept"
    echo ""
fi
echo ""

# ── Internal resolution ──
echo "Emulator internal resolution (affects N64, GC/Wii, PS1, PS2, Wii U):"
echo "  Upscales the rendered image — higher = sharper but needs more GPU power."
echo ""
echo -e "    ${BOLD}1)${NC} Native    — original hardware resolution (fastest)"
echo -e "    ${BOLD}2)${NC} 1080p     — good for mid-range GPUs"
echo -e "    ${BOLD}3)${NC} 1440p/2K  — recommended for modern GPUs (default)"
echo -e "    ${BOLD}4)${NC} 4K        — very powerful GPU required"
echo ""
read -rp "  Resolution [1-4] (default: 3): " RES_CHOICE
RES_CHOICE="${RES_CHOICE:-3}"
case "$RES_CHOICE" in
    1) RES_SCALE=1; RES_LABEL="Native" ;;
    2) RES_SCALE=2; RES_LABEL="1080p" ;;
    4) RES_SCALE=6; RES_LABEL="4K" ;;
    *) RES_SCALE=4; RES_LABEL="1440p/2K" ;;
esac
echo -e "   ${GREEN}✓${NC} Resolution: $RES_LABEL"
echo ""

# ── Desktop shortcut ──
CREATE_SHORTCUT=""
echo "Create a desktop shortcut for ES-DE in your applications menu?"
read -rp "  [Y/n]: " SHORTCUT_CHOICE
[[ "${SHORTCUT_CHOICE,,}" != "n" ]] && CREATE_SHORTCUT="yes"
echo ""

# ── Preflight ──
for cmd in curl grep chmod unzip python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}ERROR: '$cmd' is required but not found.${NC}"
        exit 1
    fi
done

#=============================================================================
# DOWNLOAD HELPERS
#=============================================================================
github_appimage() {
    local repo="$1" pattern="$2" outfile="$3"
    if [[ -f "$outfile" ]]; then
        ok "$(basename "$outfile") already exists, skipping"
        return 0
    fi
    info "Querying GitHub: $repo ..."
    local url
    url=$(curl -sfL "https://api.github.com/repos/$repo/releases?per_page=10" \
        | grep -oP '"browser_download_url":\s*"\K[^"]*' \
        | grep -P "$pattern" \
        | head -1) || true
    if [[ -z "$url" ]]; then
        fail "No match for pattern in $repo releases"
        return 1
    fi
    info "Downloading $(basename "$url") ..."
    if curl -#fL -o "$outfile" "$url"; then
        chmod +x "$outfile"
        ok "$(basename "$outfile") downloaded"
    else
        fail "Download failed: $url"
        rm -f "$outfile"
        return 1
    fi
}

download_direct() {
    local url="$1" outfile="$2" label="$3"
    if [[ -f "$outfile" ]]; then
        ok "$label already exists, skipping"
        return 0
    fi
    info "Downloading $label ..."
    if curl -#fL -o "$outfile" "$url"; then
        chmod +x "$outfile"
        ok "$label downloaded"
    else
        fail "Download failed: $label"
        rm -f "$outfile"
        return 1
    fi
}

download_rpcs3() {
    local outdir="$1"
    if compgen -G "$outdir/rpcs3*.AppImage" > /dev/null 2>&1; then
        ok "RPCS3 already exists, skipping"
        return 0
    fi
    info "Downloading RPCS3 (latest nightly) ..."
    if (cd "$outdir" && curl -#fJLO "https://rpcs3.net/latest-linux-x64"); then
        chmod +x "$outdir"/rpcs3*.AppImage 2>/dev/null || true
        ok "RPCS3 downloaded"
    else
        fail "RPCS3 download failed"
        return 1
    fi
}

download_esde() {
    local outdir="$1"
    # Remove any leftover zip files from previous attempts
    rm -f "$outdir"/ES-DE*.zip

    # Already have the real AppImage?
    if compgen -G "$outdir/ES-DE*.AppImage" > /dev/null 2>&1; then
        local existing
        existing=$(find "$outdir" -maxdepth 1 -name 'ES-DE*.AppImage' -print -quit)
        if file "$existing" 2>/dev/null | grep -qi "ELF"; then
            ok "ES-DE already exists, skipping"
            return 0
        else
            warn "Removing non-AppImage file: $existing"
            rm -f "$existing"
        fi
    fi

    info "Fetching ES-DE download URL from GitLab ..."
    local api_url="https://gitlab.com/api/v4/projects/es-de%2Femulationstation-de/releases/permalink/latest"
    local dl_url
    # Extract the direct_asset_url for the x64 AppImage
    dl_url=$(curl -sfL "$api_url" | grep -oP '"direct_asset_url":"\K[^"]*' | head -1) || true

    if [[ -z "$dl_url" ]]; then
        warn "Could not auto-detect ES-DE AppImage URL from GitLab"
        warn "Download manually from https://es-de.org/"
        return 1
    fi

    info "Downloading ES-DE AppImage ..."
    if curl -#fL -o "$outdir/ES-DE_x64.AppImage" "$dl_url"; then
        chmod +x "$outdir/ES-DE_x64.AppImage"
        if file "$outdir/ES-DE_x64.AppImage" | grep -qi "ELF"; then
            ok "ES-DE downloaded and verified"
        else
            fail "Downloaded file is not an ELF AppImage – check URL"
            rm -f "$outdir/ES-DE_x64.AppImage"
            return 1
        fi
    else
        fail "ES-DE download failed"
        rm -f "$outdir/ES-DE_x64.AppImage"
        return 1
    fi
}

#=============================================================================
# RETROARCH CORE DOWNLOADER
#=============================================================================
CORE_BASE_URL="https://buildbot.libretro.com/nightly/linux/x86_64/latest"

download_core() {
    local core_name="$1"
    local core_dir="$2"
    local zip_name="${core_name}_libretro.so.zip"
    local so_name="${core_name}_libretro.so"

    if [[ -f "$core_dir/$so_name" ]]; then
        return 0  # Already have it
    fi

    if curl -sfL -o "/tmp/$zip_name" "$CORE_BASE_URL/$zip_name" 2>/dev/null; then
        if unzip -qo "/tmp/$zip_name" -d "$core_dir" 2>/dev/null; then
            rm -f "/tmp/$zip_name"
            return 0
        fi
    fi
    rm -f "/tmp/$zip_name"
    return 1
}

download_cores() {
    local core_dir="$1"

    # Map: core_name → systems it covers
    # These are the recommended/default cores ES-DE uses
    local -A CORES=(
        # Nintendo
        [fceumm]="NES / Famicom / FDS"
        [snes9x]="SNES / Super Famicom"
        [mgba]="GBA / GB / GBC"
        [gambatte]="GB / GBC (alt)"
        [mupen64plus_next]="N64"

        # Sega
        [genesis_plus_gx]="Genesis / Mega Drive / Master System / Game Gear / SG-1000 / Sega CD"
        [picodrive]="32X / Sega CD (alt)"
        [flycast]="Dreamcast"
        [mednafen_saturn]="Saturn"

        # Atari
        [stella]="Atari 2600"
        [a5200]="Atari 5200"
        [prosystem]="Atari 7800"
        [handy]="Atari Lynx"
        [hatari]="Atari ST"
        [virtualjaguar]="Atari Jaguar"

        # Other
        [fbneo]="Arcade / Neo Geo / Neo Geo CD"
        [mame2003_plus]="Arcade (MAME 2003+)"
        [mednafen_pce]="PC Engine / TG16 / SuperGrafx"
        [mednafen_pce_fast]="PC Engine CD / TG-CD"
        [mednafen_pcfx]="PC-FX"
        [mednafen_vb]="Virtual Boy"
        [mednafen_ngp]="Neo Geo Pocket / NGP Color"
        [mednafen_wswan]="WonderSwan / WonderSwan Color"
        [fuse]="ZX Spectrum"
        [81]="ZX81"
        [vice_x64]="Commodore 64"
        [vice_xvic]="VIC-20"
        [puae]="Amiga"
        [bluemsx]="MSX / MSX2"
        [o2em]="Odyssey2 / Videopac"
        [vecx]="Vectrex"
        [freechaf]="Channel F"
        [freeintv]="Intellivision"
        [pokemini]="Pokemon Mini"
        [uzem]="Uzebox"
        [opera]="3DO"
        [scummvm]="ScummVM"
        [dosbox_pure]="DOS"
        [cap32]="Amstrad CPC"
        [quasi88]="x68000 (alt)"
    )

    local total=${#CORES[@]}
    local downloaded=0
    local skipped=0
    local failed=0

    info "Downloading $total RetroArch cores from buildbot.libretro.com ..."
    echo ""

    # Sort core names safely (keys only, no spaces issue)
    local sorted_cores
    sorted_cores=$(printf '%s\n' "${!CORES[@]}" | sort)

    while IFS= read -r core_name; do
        [[ -z "$core_name" ]] && continue
        local desc="${CORES[$core_name]}"
        printf "   %-30s %s" "$core_name" "$desc"

        if [[ -f "$core_dir/${core_name}_libretro.so" ]]; then
            echo -e " ${GREEN}[exists]${NC}"
            skipped=$((skipped + 1))
        elif download_core "$core_name" "$core_dir"; then
            echo -e " ${GREEN}[ok]${NC}"
            downloaded=$((downloaded + 1))
        else
            echo -e " ${RED}[fail]${NC}"
            failed=$((failed + 1))
        fi
    done <<< "$sorted_cores"

    echo ""
    ok "Cores: $downloaded downloaded, $skipped already existed, $failed failed"
}

#=============================================================================
# STEP 1: DIRECTORY STRUCTURE
#=============================================================================
STEP=1
TOTAL_STEPS=16

echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Creating directory structure..."

mkdir -p "$BASE"
mkdir -p "$EMUS/retroarch-cores"
mkdir -p "$ESDE_DATA/custom_systems"
mkdir -p "$ESDE_DATA/settings"
mkdir -p "$ESDE_DATA/themes"
mkdir -p "$ESDE_DATA/gamelists"
mkdir -p "$BASE/downloaded_media"
mkdir -p "$BASE/Saves/files"
mkdir -p "$BASE/Saves/states"

ROM_DIRS=(
    3do amiga amigacd32 amstradcpc arcade atari2600 atari5200 atari7800
    atarijaguar atarilynx atarist c64 channelf colecovision daphne
    dos dreamcast famicom fba fds gamegear gb gba gbc gc genesis
    intellivision jaguar lynx mastersystem megacd megadrive msx
    msx2 n3ds n64 nds neogeo neogeocd nes ngp ngpc odyssey2
    pc pcengine pcenginecd pcfx pico8 pokemini ports ps2 ps3
    psp psx saturn sc-3000 scummvm sega32x segacd sg-1000 snes
    supergrafx tg-cd tg16 ti99 uzebox vectrex vic20 videopac
    virtualboy wii wiiu wonderswan wonderswancolor x68000
    xbox xbox360 zmachine zx81 zxspectrum
    triforce j2me openbor pcarcade type-x
    bios
)
for dir in "${ROM_DIRS[@]}"; do mkdir -p "$ROMS/$dir"; done
ok "Directory tree created"

#=============================================================================
# STEP 2: PORTABLE.TXT
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Creating portable.txt..."
touch "$BASE/portable.txt"
ok "portable.txt created"

#=============================================================================
# STEP 3: ES_FIND_RULES.XML
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing es_find_rules.xml..."

# Write find rules with absolute paths baked in at setup time.
# %ESPATH% cannot be used — it resolves to the AppImage's internal temp mount,
# not the bundle directory on disk.
python3 - "$ESDE_DATA/custom_systems/es_find_rules.xml" "$EMUS" << 'PYEOF'
import sys, os
out_path, emus = sys.argv[1], sys.argv[2]

def entry(path): return f'            <entry>{path}</entry>'
def emu(name, paths, syspaths=None):
    lines = [f'    <emulator name="{name}">', '        <rule type="staticpath">']
    for p in paths: lines.append(entry(p))
    lines.append('        </rule>')
    for s in (syspaths or []):
        lines += ['        <rule type="systempath">', entry(s), '        </rule>']
    lines.append('    </emulator>')
    return '\n'.join(lines)

fp = lambda *parts: os.path.join(emus, *parts)

xml = ['<?xml version="1.0"?>',
'<!-- Portable ES-DE find rules — absolute paths written at setup time -->',
'<!-- %ESPATH% resolves to the AppImage internal mount, not the bundle dir -->',
'<ruleList>', '',
emu('RETROARCH',
    [fp('RetroArch*.AppImage'), fp('retroarch')],
    ['retroarch']),
'',
'    <core name="RETROARCH">',
'        <rule type="corepath">',
entry(fp('retroarch-cores')),
entry('~/.config/retroarch/cores'),
entry('/usr/lib/libretro'),
entry('/usr/lib64/libretro'),
'        </rule>',
'    </core>',
'',
emu('DOLPHIN', [fp('dolphin*.AppImage'), fp('Dolphin*.AppImage'),
    '/var/lib/flatpak/exports/bin/org.DolphinEmu.dolphin-emu'], ['dolphin-emu']),
'',
emu('PCSX2', [fp('pcsx2*.AppImage'), fp('PCSX2*.AppImage'),
    '/var/lib/flatpak/exports/bin/net.pcsx2.PCSX2'], ['pcsx2-qt']),
'',
emu('RPCS3', [fp('rpcs3*.AppImage'), fp('RPCS3*.AppImage'),
    '/var/lib/flatpak/exports/bin/net.rpcs3.RPCS3'], ['rpcs3']),
'',
emu('DUCKSTATION', [fp('DuckStation*.AppImage'), fp('duckstation*.AppImage'),
    '/var/lib/flatpak/exports/bin/org.duckstation.DuckStation'], ['duckstation-qt']),
'',
emu('PPSSPP', [fp('PPSSPP*.AppImage'), fp('ppsspp*.AppImage'),
    '/var/lib/flatpak/exports/bin/org.ppsspp.PPSSPP'], ['PPSSPPQt']),
'',
emu('MELONDS', [fp('melonDS*.AppImage'),
    '/var/lib/flatpak/exports/bin/net.kuribo64.melonDS'], ['melonDS']),
'',
emu('MGBA', [fp('mGBA*.AppImage'), fp('mgba*')], ['mgba-qt']),
'',
emu('CEMU', [fp('Cemu*.AppImage'), fp('cemu*.AppImage'),
    '/var/lib/flatpak/exports/bin/info.cemu.Cemu'], ['cemu']),
'',
emu('RMG', [fp('RMG*.AppImage'),
    '/var/lib/flatpak/exports/bin/com.github.Rosalie241.RMG'], ['RMG']),
'',
emu('SCUMMVM', [fp('scummvm*.AppImage')], ['scummvm']),
'',
emu('MAME', [fp('mame*.AppImage')], ['mame']),
'',
emu('FLYCAST', [fp('flycast*.AppImage')], ['flycast']),
'',
emu('RYUBING', [fp('Ryubing*.AppImage'), fp('ryubing*')], ['Ryubing']),
'',
emu('EDEN', [fp('Eden*.AppImage'), fp('eden*.AppImage')], ['eden']),
'',
emu('XEMU', [fp('xemu*.AppImage'),
    '/var/lib/flatpak/exports/bin/app.xemu.xemu'], ['xemu']),
'',
emu('XENIA', [fp('xenia*.AppImage'), fp('xenia_canary')], ['xenia_canary']),
'',
emu('AZAHAR', [fp('azahar*.AppImage'), fp('Azahar*.AppImage')], ['azahar']),
'',
emu('GEARGRAFX', [fp('Geargrafx*.AppImage')], ['geargrafx']),
'',
emu('MESEN', [fp('Mesen*.AppImage')], ['Mesen']),
'',
'</ruleList>']

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w') as f:
    f.write('\n'.join(xml) + '\n')
print(f"Written: {out_path}")
PYEOF

ok "es_find_rules.xml written"

# ── Write custom es_systems.xml defining hack systems as separate ES-DE systems ──
# These use the parent system's theme + platform so they look correct in ES-DE
# and scrape against the right database, but appear as their own sidebar entry.
cat > "$ESDE_DATA/custom_systems/es_systems.xml" << 'CUSTOMSYSTEMS'
<?xml version="1.0"?>
<systemList>

  <system>
    <name>snesh</name>
    <fullname>Super Nintendo (Hacks &amp; Homebrew)</fullname>
    <path>%ROMPATH%/snesh</path>
    <extension>.sfc .smc .fig .swc .bs .st .zip .7z .SFC .SMC .ZIP .7Z</extension>
    <command label="Snes9x">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/snes9x_libretro.so %ROM%</command>
    <platform>snes</platform>
    <theme>snes</theme>
  </system>

  <system>
    <name>nesh</name>
    <fullname>Nintendo Entertainment System (Hacks &amp; Homebrew)</fullname>
    <path>%ROMPATH%/nesh</path>
    <extension>.nes .unf .unif .fds .zip .7z .NES .ZIP .7Z</extension>
    <command label="FCEUmm">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fceumm_libretro.so %ROM%</command>
    <platform>nes</platform>
    <theme>nes</theme>
  </system>

  <system>
    <name>gbh</name>
    <fullname>Game Boy (Hacks &amp; Homebrew)</fullname>
    <path>%ROMPATH%/gbh</path>
    <extension>.gb .gbc .zip .7z .GB .GBC .ZIP .7Z</extension>
    <command label="Gambatte">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/gambatte_libretro.so %ROM%</command>
    <platform>gb</platform>
    <theme>gb</theme>
  </system>

  <system>
    <name>gbch</name>
    <fullname>Game Boy Color (Hacks &amp; Homebrew)</fullname>
    <path>%ROMPATH%/gbch</path>
    <extension>.gb .gbc .zip .7z .GB .GBC .ZIP .7Z</extension>
    <command label="Gambatte">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/gambatte_libretro.so %ROM%</command>
    <platform>gbc</platform>
    <theme>gbc</theme>
  </system>

  <system>
    <name>gbah</name>
    <fullname>Game Boy Advance (Hacks &amp; Homebrew)</fullname>
    <path>%ROMPATH%/gbah</path>
    <extension>.gba .zip .7z .GBA .ZIP .7Z</extension>
    <command label="mGBA">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mgba_libretro.so %ROM%</command>
    <platform>gba</platform>
    <theme>gba</theme>
  </system>

  <system>
    <name>genh</name>
    <fullname>Sega Genesis (Hacks &amp; Homebrew)</fullname>
    <path>%ROMPATH%/genh</path>
    <extension>.md .bin .smd .gen .zip .7z .MD .BIN .ZIP .7Z</extension>
    <command label="Genesis Plus GX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/genesis_plus_gx_libretro.so %ROM%</command>
    <platform>genesis</platform>
    <theme>genesis</theme>
  </system>

  <system>
    <name>n64h</name>
    <fullname>Nintendo 64 (Hacks &amp; Homebrew)</fullname>
    <path>%ROMPATH%/n64h</path>
    <extension>.z64 .n64 .v64 .zip .7z .Z64 .N64 .V64 .ZIP .7Z</extension>
    <command label="Mupen64Plus-Next">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mupen64plus_next_libretro.so %ROM%</command>
    <platform>n64</platform>
    <theme>n64</theme>
  </system>

  <system>
    <name>ggh</name>
    <fullname>Game Gear (Hacks &amp; Homebrew)</fullname>
    <path>%ROMPATH%/ggh</path>
    <extension>.gg .zip .7z .GG .ZIP .7Z</extension>
    <command label="Genesis Plus GX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/genesis_plus_gx_libretro.so %ROM%</command>
    <platform>gamegear</platform>
    <theme>gamegear</theme>
  </system>

</systemList>
CUSTOMSYSTEMS
ok "custom es_systems.xml written (hack systems: snesh, nesh, gbh, gbch, gbah, genh, n64h, ggh)"

# Add these hack system ROM directories to the bundle
for HACK_SYS in snesh nesh gbh gbch gbah genh n64h ggh; do
    mkdir -p "$ROMS/$HACK_SYS"
done

#=============================================================================
# STEP 4: RETROARCH CONFIG
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing retroarch.cfg..."

# With HOME=$BASE set in launch.sh, RetroArch automatically reads from:
# $BASE/.config/retroarch/retroarch.cfg — no wrapper script needed
mkdir -p "$BASE/.config/retroarch"

# Detect audio driver before writing config
AUDIO_DRIVER="pulse"
if command -v pactl &>/dev/null; then
    pactl info 2>/dev/null | grep -qi pipewire && AUDIO_DRIVER="pipewire"
fi

cat > "$BASE/.config/retroarch/retroarch.cfg" << RACFG
# Portable RetroArch config — auto-generated by setup script
# HOME is set to the bundle root in launch.sh, so RetroArch finds this automatically.

# ── Paths ──
libretro_directory = "${EMUS}/retroarch-cores"
system_directory = "${ROMS}/bios"
savefile_directory = "${BASE}/Saves/files"
savestate_directory = "${BASE}/Saves/states"
screenshot_directory = "${BASE}/Saves/screenshots"
log_dir = "${BASE}/Saves/logs"
core_updater_buildbot_url = "https://buildbot.libretro.com/nightly/linux/x86_64/latest/"
core_updater_buildbot_assets_url = "https://buildbot.libretro.com/assets/"

# ── Video ──
video_fullscreen = "true"
video_fullscreen_x = "0"
video_fullscreen_y = "0"
video_vsync = "true"
video_max_swapchain_images = "3"
video_scale_integer = "false"
video_aspect_ratio_auto = "true"

# ── Audio ──
audio_driver = "${AUDIO_DRIVER}"
audio_latency = "64"

# ── Menu ──
menu_driver = "ozone"
menu_show_online_updater = "true"
menu_show_core_updater = "true"

# ── Input ──
input_autodetect_enable = "true"
input_menu_toggle_gamepad_combo = "2"

# ── Saving ──
savestate_auto_save = "false"
savestate_auto_load = "false"
sort_savefiles_enable = "true"
sort_savestates_enable = "true"
sort_savefiles_by_content_enable = "true"
sort_savestates_by_content_enable = "true"

# ── Rewind ──
rewind_enable = "false"

# ── Notifications ──
video_font_enable = "true"
RACFG

ok "retroarch.cfg written → $BASE/.config/retroarch/retroarch.cfg"
mkdir -p "${BASE}/Saves/screenshots"
mkdir -p "${BASE}/Saves/logs"

# ── Write RetroArch wrapper so it always uses our portable config ──
info "Writing RetroArch portable wrapper..."
cat > "$EMUS/retroarch-portable.sh" << 'RAWRAPPER'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RA=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'RetroArch*.AppImage' | head -1)
exec "$RA" --config "$SCRIPT_DIR/retroarch.cfg" "$@"
RAWRAPPER
chmod +x "$EMUS/retroarch-portable.sh"

# ── Dolphin — supports --config-path to redirect all config/data ──
cat > "$EMUS/dolphin-portable.sh" << 'DOLPHINWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOLPHIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'dolphin*.AppImage' -o -name 'Dolphin*.AppImage' | head -1)
mkdir -p "$SCRIPT_DIR/config/dolphin-emu"
exec "$DOLPHIN" --user="$SCRIPT_DIR/config/dolphin-emu" "$@"
DOLPHINWRAP
chmod +x "$EMUS/dolphin-portable.sh"

# ── DuckStation — supports --settings-dir ──
cat > "$EMUS/duckstation-portable.sh" << 'DUCKWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DUCK=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'DuckStation*.AppImage' -o -name 'duckstation*.AppImage' | head -1)
mkdir -p "$SCRIPT_DIR/config/duckstation"
exec "$DUCK" --settings-dir "$SCRIPT_DIR/config/duckstation" "$@"
DUCKWRAP
chmod +x "$EMUS/duckstation-portable.sh"

# ── PCSX2 — supports --inipath ──
cat > "$EMUS/pcsx2-portable.sh" << 'PCSX2WRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCSX2=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'pcsx2*.AppImage' -o -name 'PCSX2*.AppImage' | head -1)
mkdir -p "$SCRIPT_DIR/config/pcsx2"
exec "$PCSX2" --inipath "$SCRIPT_DIR/config/pcsx2" "$@"
PCSX2WRAP
chmod +x "$EMUS/pcsx2-portable.sh"

ok "Portable emulator wrappers written"

# ── XDG-based wrappers for emulators without specific portable flags ──
# Redirects XDG_CONFIG_HOME + XDG_DATA_HOME so all config/data stays
# inside the bundle instead of ~/.config/ and ~/.local/share/
info "Writing XDG portable wrappers..."

# RPCS3
cat > "$EMUS/rpcs3-portable.sh" << 'RPCS3WRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/data"
export XDG_CONFIG_HOME="$SCRIPT_DIR/config"
export XDG_DATA_HOME="$SCRIPT_DIR/data"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'rpcs3*.AppImage' -o -name 'RPCS3*.AppImage' | head -1)
exec "$BIN" "$@"
RPCS3WRAP
chmod +x "$EMUS/rpcs3-portable.sh"

# PPSSPP — has dedicated --memstick flag for its data dir
cat > "$EMUS/ppsspp-portable.sh" << 'PPSSPPWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/config/ppsspp"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'PPSSPP*.AppImage' -o -name 'ppsspp*.AppImage' | head -1)
exec "$BIN" --memstick "$SCRIPT_DIR/config/ppsspp" "$@"
PPSSPPWRAP
chmod +x "$EMUS/ppsspp-portable.sh"

# melonDS
cat > "$EMUS/melonds-portable.sh" << 'MELONDSWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/data"
export XDG_CONFIG_HOME="$SCRIPT_DIR/config"
export XDG_DATA_HOME="$SCRIPT_DIR/data"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'melonDS*.AppImage' | head -1)
exec "$BIN" "$@"
MELONDSWRAP
chmod +x "$EMUS/melonds-portable.sh"

# Azahar (3DS)
cat > "$EMUS/azahar-portable.sh" << 'AZAHARWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/data"
export XDG_CONFIG_HOME="$SCRIPT_DIR/config"
export XDG_DATA_HOME="$SCRIPT_DIR/data"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'azahar*.AppImage' -o -name 'Azahar*.AppImage' | head -1)
exec "$BIN" "$@"
AZAHARWRAP
chmod +x "$EMUS/azahar-portable.sh"

# Cemu
cat > "$EMUS/cemu-portable.sh" << 'CEMUWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/data"
export XDG_CONFIG_HOME="$SCRIPT_DIR/config"
export XDG_DATA_HOME="$SCRIPT_DIR/data"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'Cemu*.AppImage' -o -name 'cemu*.AppImage' | head -1)
exec "$BIN" "$@"
CEMUWRAP
chmod +x "$EMUS/cemu-portable.sh"

# xemu
cat > "$EMUS/xemu-portable.sh" << 'XEMUWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/data"
export XDG_CONFIG_HOME="$SCRIPT_DIR/config"
export XDG_DATA_HOME="$SCRIPT_DIR/data"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'xemu*.AppImage' | head -1)
exec "$BIN" "$@"
XEMUWRAP
chmod +x "$EMUS/xemu-portable.sh"

# Eden (Switch)
cat > "$EMUS/eden-portable.sh" << 'EDENWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/data"
export XDG_CONFIG_HOME="$SCRIPT_DIR/config"
export XDG_DATA_HOME="$SCRIPT_DIR/data"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'Eden*.AppImage' -o -name 'eden*.AppImage' | head -1)
exec "$BIN" "$@"
EDENWRAP
chmod +x "$EMUS/eden-portable.sh"

ok "XDG portable wrappers written"

# ── Pre-write emulator configs for native fullscreen + chosen resolution ──
info "Writing emulator default configs (resolution: $RES_LABEL)..."

# Dolphin — InternalResolution: 1=native,2=1.5x,3=2x(720p),4=2.5x,5=3x(1080p),6=4x(1440p)
# Map our 1/2/4/6 scale to Dolphin's 1/3/6/8 internal scale
case "$RES_SCALE" in
    1) DOLPHIN_RES=1 ;;
    2) DOLPHIN_RES=3 ;;
    4) DOLPHIN_RES=6 ;;
    6) DOLPHIN_RES=8 ;;
    *) DOLPHIN_RES=6 ;;
esac
mkdir -p "$BASE/.config/dolphin-emu/Config"
cat > "$BASE/.config/dolphin-emu/Config/Dolphin.ini" << DOLPHINCFG
[Display]
FullscreenResolution = Auto
Fullscreen = True
RenderToMain = False
[Interface]
ConfirmStop = False
DOLPHINCFG
cat > "$BASE/.config/dolphin-emu/Config/GFX.ini" << GFXCFG
[Settings]
InternalResolution = ${DOLPHIN_RES}
GFXCFG

# DuckStation — ResolutionScale: 1=native, 2=2x, 4=4x, 6=6x
mkdir -p "$BASE/.config/duckstation"
cat > "$BASE/.config/duckstation/settings.ini" << DUCKCFG
[Main]
FullscreenUI = true
[Display]
Fullscreen = true
[GPU]
ResolutionScale = ${RES_SCALE}
DUCKCFG

# PCSX2 — UpscaleMultiplier: 1=native, 2=2x, 4=4x, 6=6x
mkdir -p "$BASE/.config/PCSX2/inis"
cat > "$BASE/.config/PCSX2/inis/PCSX2.ini" << PCSX2CFG
[UI]
StartFullscreen = true
ConfirmShutdown = false
[EmuCore/GS]
AspectRatio = Auto 4:3/16:9
FMVAspectRatioSwitch = Off
upscale_multiplier = ${RES_SCALE}
PCSX2CFG

# Cemu — native fullscreen
mkdir -p "$BASE/.config/Cemu"
cat > "$BASE/.config/Cemu/settings.xml" << CEMUCFG
<?xml version="1.0" encoding="utf-8"?>
<content>
  <fullscreen>true</fullscreen>
  <use_discord_presence>false</use_discord_presence>
</content>
CEMUCFG

ok "Emulator configs written (fullscreen + $RES_LABEL resolution)"

#=============================================================================
# STEP 5: LAUNCH SCRIPT
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing launch.sh..."

cat > "$BASE/launch.sh" << 'LAUNCHER'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$SCRIPT_DIR"/*.AppImage 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/Emulators/*.AppImage 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/Emulators/*.sh 2>/dev/null || true

ESDE_BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'ES-DE*.AppImage' -o -name 'esde*.AppImage' | head -1)

if [[ -z "$ESDE_BIN" ]]; then
    echo "ERROR: No ES-DE AppImage found in $SCRIPT_DIR"
    echo "Download from https://es-de.org/ or re-run the setup script."
    exit 1
fi

echo "Launching: $(basename "$ESDE_BIN")"
echo "Portable mode: enabled"

if ! command -v fusermount &>/dev/null && ! [[ -f /usr/lib/libfuse.so.2 ]]; then
    echo ""
    echo "NOTE: libfuse2 not detected. If AppImages fail:"
    echo "  Ubuntu/Debian: sudo apt install libfuse2"
    echo "  Fedora:        sudo dnf install fuse-libs"
    echo "  Arch:          sudo pacman -S fuse2"
    echo ""
fi

cd "$SCRIPT_DIR"
export HOME="$SCRIPT_DIR"

# Apply desired theme before launch — ES-DE may overwrite settings on exit
# so we also re-apply after. Belt and suspenders.
SETTINGS="$SCRIPT_DIR/ES-DE/settings/es_settings.xml"
THEME_CACHE="$SCRIPT_DIR/ES-DE/.desired_theme"

apply_theme() {
    if [[ -f "$THEME_CACHE" && -f "$SETTINGS" ]]; then
        DESIRED_THEME=$(cat "$THEME_CACHE")
        if grep -q 'name="Theme"' "$SETTINGS"; then
            sed -i "s|name=\"Theme\" value=\"[^\"]*\"|name=\"Theme\" value=\"$DESIRED_THEME\"|" "$SETTINGS"
        fi
    fi
}

apply_paths() {
    if [[ -f "$SETTINGS" ]]; then
        sed -i "s|name=\"ROMDirectory\" value=\"[^\"]*\"|name=\"ROMDirectory\" value=\"$SCRIPT_DIR/ROMs\"|" "$SETTINGS"
        sed -i "s|name=\"MediaDirectory\" value=\"[^\"]*\"|name=\"MediaDirectory\" value=\"$SCRIPT_DIR/downloaded_media\"|" "$SETTINGS"
    fi
}

apply_theme
apply_paths

"$ESDE_BIN" --home "$SCRIPT_DIR" "$@"
EXIT_CODE=$?

apply_theme
apply_paths

exit $EXIT_CODE
LAUNCHER

chmod +x "$BASE/launch.sh"
ok "launch.sh written"

#=============================================================================
# STEP 6: BIOS + MAIN README
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing READMEs..."

cat > "$ROMS/bios/README-BIOS.md" << 'BIOSREADME'
# BIOS & Firmware Files — place in this directory

| System        | File(s)                          | Emulator    |
|---------------|----------------------------------|-------------|
| PS1 (psx)     | scph5501.bin (+ other regions)   | DuckStation |
| PS2 (ps2)     | BIOS files in PCSX2 bios dir     | PCSX2       |
| PS3 (ps3)     | PS3 firmware (PS3UPDAT.PUP)      | RPCS3       |
| Saturn        | saturn_bios.bin                  | RetroArch   |
| Dreamcast     | dc_boot.bin, dc_flash.bin        | RetroArch   |
| DS (nds)      | bios7.bin, bios9.bin, firmware   | melonDS     |
| GBA (gba)     | gba_bios.bin (optional for mGBA) | mGBA        |
| 3DS (n3ds)    | see Azahar docs                  | Azahar      |
| Xbox (xbox)   | mcpx_1.0.bin, Complex_4627.bin + HDD image | xemu |
| Lynx          | lynxboot.img                     | RetroArch   |
| PC Engine CD  | syscard3.pce                     | RetroArch   |
| Neo Geo       | neogeo.zip (in arcade/ or here)  | RetroArch   |

The portable retroarch.cfg points system_directory to this folder.
BIOS/firmware files are copyrighted — dump from hardware you own.
BIOSREADME

cat > "$BASE/README.md" << 'MAINREADME'
# Portable ES-DE for Linux

A fully self-contained retro gaming bundle. No system-level installation needed.

## Quick Start

```bash
# First time — run the setup script to download everything:
chmod +x setup-portable-esde.sh
./setup-portable-esde.sh

# Add your ROMs to ROMs/<system>/
# Add BIOS files to ROMs/bios/ (see ROMs/bios/README-BIOS.md)

# Play:
./launch.sh
```

## What's included

**Frontend:** ES-DE (portable mode via portable.txt)

**Standalone emulators (auto-downloaded):**
- RetroArch + 40+ cores (NES, SNES, Genesis, GB/A, N64, Arcade, etc.)
- PCSX2 (PS2) · RPCS3 (PS3) · DuckStation (PS1)
- Dolphin (GameCube/Wii) · Cemu (Wii U)
- PPSSPP (PSP) · melonDS (DS) · Azahar (3DS)
- xemu (Xbox) · Xenia Canary (Xbox 360)

**Pre-configured:** `es_find_rules.xml` with relative paths via `%ESPATH%`

## Updating emulators

Replace AppImage files — glob patterns handle version numbers.
Re-run the setup script to download new versions (existing files are skipped).

## FUSE note

Some AppImages need libfuse2:
- Ubuntu/Debian: `sudo apt install libfuse2`
- Fedora: `sudo dnf install fuse-libs`
- Arch: `sudo pacman -S fuse2`
MAINREADME

ok "READMEs written"

#=============================================================================
# STEP 7: DOWNLOAD ES-DE
#=============================================================================
STEP=$((STEP + 1))
echo ""
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading ES-DE..."
download_esde "$BASE" || true

#=============================================================================
# STEP 8: DOWNLOAD RETROARCH
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading RetroArch..."
download_direct \
    "https://github.com/hizzlekizzle/RetroArch-AppImage/releases/download/Linux_LTS_Nightlies/RetroArch-Linux-x86_64-Nightly.AppImage" \
    "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage" \
    "RetroArch" || true

#=============================================================================
# STEP 9: DOWNLOAD RETROARCH CORES
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading RetroArch cores..."
echo ""
download_cores "$EMUS/retroarch-cores"

#=============================================================================
# STEP 10: DOWNLOAD STANDALONE EMULATORS
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading standalone emulators..."
echo ""

DOWNLOAD_ERRORS=0

echo "   ── RPCS3 (PS3) ──"
download_rpcs3 "$EMUS" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
echo ""

echo "   ── PCSX2 (PS2) ──"
github_appimage "PCSX2/pcsx2" \
    "linux-appimage-x64.*\.AppImage$" \
    "$EMUS/pcsx2-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
echo ""

echo "   ── DuckStation (PS1) ──"
github_appimage "stenzek/duckstation" \
    "DuckStation.*x64.*\.AppImage$" \
    "$EMUS/DuckStation-x64.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
echo ""

echo "   ── PPSSPP (PSP) ──"
github_appimage "hrydgard/ppsspp" \
    "PPSSPP.*x86_64.*\.AppImage$" \
    "$EMUS/PPSSPP-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
echo ""

echo "   ── melonDS (DS) ──"
github_appimage "pkgforge-dev/melonDS-AppImage-Enhanced" \
    "melonDS.*x86_64.*\.AppImage$" \
    "$EMUS/melonDS-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
echo ""

echo "   ── Dolphin (GC/Wii) ──"
github_appimage "pkgforge-dev/Dolphin-emu-AppImage" \
    "Dolphin_Emulator.*x86_64.*\.AppImage$" \
    "$EMUS/dolphin-emu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
echo ""

echo "   ── Cemu (Wii U) ──"
github_appimage "cemu-project/Cemu" \
    "Cemu.*\.AppImage$" \
    "$EMUS/Cemu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
echo ""

echo "   ── Azahar (3DS) ──"
if compgen -G "$EMUS/azahar*.AppImage" > /dev/null 2>&1; then
    ok "Azahar already exists, skipping"
else
    AZAHAR_URL=$(curl -sfL "https://api.github.com/repos/azahar-emu/azahar/releases?per_page=5" \
        | grep -oP '"browser_download_url":\s*"\K[^"]*azahar\.AppImage(?!-)' \
        | head -1) || true
    if [[ -n "$AZAHAR_URL" ]]; then
        info "Downloading Azahar ..."
        if curl -#fL -o "$EMUS/azahar.AppImage" "$AZAHAR_URL"; then
            chmod +x "$EMUS/azahar.AppImage"
            ok "Azahar downloaded"
        else
            fail "Azahar download failed"
            rm -f "$EMUS/azahar.AppImage"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    else
        fail "Could not find Azahar AppImage"
        DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
    fi
fi
echo ""

echo "   ── xemu (Xbox) ──"
github_appimage "xemu-project/xemu" \
    "xemu-[0-9].*x86_64\.AppImage$" \
    "$EMUS/xemu-latest.AppImage" || {
        github_appimage "xemu-project/xemu" \
            "xemu.*x86_64\.AppImage$" \
            "$EMUS/xemu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
    } || true
echo ""

echo "   ── Xenia Canary (Xbox 360) ──"
if [[ -f "$EMUS/xenia_canary" ]]; then
    ok "Xenia Canary already exists, skipping"
else
    XENIA_URL="https://github.com/xenia-canary/xenia-canary-releases/releases/latest/download/xenia_canary_linux.tar.xz"
    info "Downloading Xenia Canary (official build) ..."
    XENIA_TMPDIR="$EMUS/xenia_tmp"
    mkdir -p "$XENIA_TMPDIR"
    if curl -#fL "$XENIA_URL" | tar -xJ -C "$XENIA_TMPDIR" 2>/dev/null; then
        # Locate the xenia_canary binary (usually deep inside build/...)
        XENIA_BIN=$(find "$XENIA_TMPDIR" -type f -name xenia_canary -executable 2>/dev/null | head -1)
        if [[ -n "$XENIA_BIN" ]]; then
            mv "$XENIA_BIN" "$EMUS/xenia_canary"
            chmod +x "$EMUS/xenia_canary"
            ok "Xenia Canary extracted"
        else
            fail "Could not find xenia_canary binary inside archive"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
        rm -rf "$XENIA_TMPDIR"
    else
        fail "Xenia Canary download failed"
        DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        rm -rf "$XENIA_TMPDIR"
    fi
fi

echo "   ── Eden (Nintendo Switch) ──"
github_appimage "eden-emulator/Releases" \
    "Eden-Linux.*x86_64.*\.AppImage$" \
    "$EMUS/Eden-latest.AppImage" || ((DOWNLOAD_ERRORS++)) || true
echo ""

#=============================================================================
# STEP 11: DOWNLOAD DEFAULT THEME + WRITE ES_SETTINGS.XML
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Installing theme..."

mkdir -p "$ESDE_DATA/settings"

if [[ -n "${THEME_SKIP_REASON:-}" ]]; then
    ok "Theme(s) ${THEME_SKIP_REASON}, skipping"
elif [[ -n "${THEME_NAME:-}" ]]; then
    THEME_DIR="$ESDE_DATA/themes/$THEME_NAME"
    if [[ -d "$THEME_DIR" ]]; then
        ok "$THEME_LABEL already installed, skipping"
    else
        info "Downloading $THEME_LABEL theme ..."
        if curl -#fL -o "/tmp/esde-theme.zip" "$THEME_REPO"; then
            unzip -qo "/tmp/esde-theme.zip" -d "/tmp/esde-theme-extract" 2>/dev/null
            mv "/tmp/esde-theme-extract/$THEME_ZIPDIR" "$THEME_DIR"
            rm -rf "/tmp/esde-theme.zip" "/tmp/esde-theme-extract"
            ok "$THEME_LABEL theme installed"
        else
            warn "Theme download failed — ES-DE will use its built-in Slate theme"
            rm -f "/tmp/esde-theme.zip"
            THEME_NAME=""
        fi
    fi

    # Write es_settings.xml so ES-DE activates the theme on first launch
    if [[ -n "$THEME_NAME" ]]; then
        # Store desired theme so launch.sh can re-apply it after ES-DE overwrites settings
        echo "$THEME_NAME" > "$ESDE_DATA/.desired_theme"
        ok "Theme preference saved (launch.sh will enforce it on each launch)"
    fi
else
    ok "Using ES-DE's built-in Slate theme"
fi

# ── Always write core ES-DE settings (paths, collections, UX defaults) ──
# These are written/updated regardless of theme choice.
SETTINGS_FILE="$ESDE_DATA/settings/es_settings.xml"
mkdir -p "$ESDE_DATA/settings"

# ES-DE's settings format: no root element wrapper, entries directly under <?xml?>
# Keys: "Theme" (not "ThemeSet"), standard ES-DE key names
# ES-DE will overwrite this on first run but preserves keys it recognises.
# The launch.sh apply_theme function patches Theme after each exit as backup.
cat > "$SETTINGS_FILE" << ESSETTINGS
<?xml version="1.0"?>
<bool name="FoldersOnTop" value="true" />
<bool name="FavoritesFirst" value="true" />
<bool name="ShowHiddenGames" value="false" />
<string name="CollectionSystemsAuto" value="favorites,recent,lastplayed" />
<string name="MediaDirectory" value="${BASE}/downloaded_media" />
<string name="ROMDirectory" value="${ROMS}" />
<string name="Scraper" value="screenscraper" />
<string name="Theme" value="${THEME_NAME:-linear-es-de}" />
ESSETTINGS
ok "es_settings.xml written (correct ES-DE format)"

# Also patch in launch.sh after any exit so theme sticks even if ES-DE rewrites
# (launch.sh apply_theme handles this — just need correct key name "Theme")
info "Browse more themes anytime: ES-DE menu → UI Settings → Theme Downloader"
echo ""

#=============================================================================
# STEP 12: RETROBAT IMPORT
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} RetroBat import..."

if [[ ${#RETROBAT_PATHS[@]} -eq 0 ]]; then
    ok "Skipped (no RetroBat path provided)"
else
    IMPORT_SYSTEMS=0
    IMPORT_ROMS=0
    IMPORT_MEDIA=0

    # Media folder mapping: RetroBat subfolder → ES-DE subfolder
    declare -A MEDIA_MAP=(
        [thumbnails]=3dboxes
        [box2d]=covers
        [fanarts]=fanart
        [marquee]=marquees
        [images]=screenshots
        [titles]=titlescreens
        [cartridges]=physicalmedia
        [videos]=videos
    )

    # System name mapping: ONLY where RetroBat name ≠ ES-DE name.
    # Hack systems (snesh, nesh, gbh, gbch, gbah, genh, n64h, ggh) are now
    # defined as their own ES-DE systems via custom_systems/es_systems.xml —
    # no mapping needed, they land in their own dedicated folders.
    declare -A SYS_MAP=(
        # SNES / Super Famicom (regional name difference, not a hack system)
        [sfc]=snes
        [snesna]=snes       # North America regional variant
        # NES regional
        [nes_aladdin]=nes   # Aladdin Deck Enhancer
        # Mega Drive / Genesis
        [nomad]=genesis     # Sega Nomad (handheld Genesis)
        [megadrivejp]=megadrive
        # N64
        [n64dd]=n64         # N64 Disk Drive
        # Sega name differences (hyphen, Japanese names)
        [sg1000]=sg-1000    # ES-DE uses hyphen
        [sc3000]=sg-1000    # SC-3000 shares SG-1000 hardware
        [markiii]=mastersystem
        # Amiga
        [amiga4000]=amiga
        # Other genuine renames
        [msx1]=msx
        [videopacplus]=videopac
        # Arcade hardware with no dedicated ES-DE system → arcade
        [fbneo]=arcade
        [cave]=arcade
        [gaelco]=arcade
        [igspgm]=arcade
        [aleck64]=arcade
    )

    for RETROBAT_PATH in "${RETROBAT_PATHS[@]}"; do
        echo ""
        info "Importing from: $RETROBAT_PATH"
        echo ""

        # Copy/cut BIOS files
        if [[ -d "$RETROBAT_PATH/bios" ]]; then
            echo -n "   BIOS files → ROMs/bios/              [${RETROBAT_MOVE:+cutting}${RETROBAT_MOVE:-copying}...]"
            if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                find "$RETROBAT_PATH/bios" -maxdepth 1 -type f -exec mv -n {} "$ROMS/bios/" \; 2>/dev/null || true
            else
                cp -rn "$RETROBAT_PATH/bios/." "$ROMS/bios/" 2>/dev/null || true
            fi
            echo -e " ${GREEN}done${NC}"
        fi

        # Process each system
        for SYS_DIR in "$RETROBAT_PATH/roms"/*/; do
            [[ -d "$SYS_DIR" ]] || continue
            RB_SYS=$(basename "$SYS_DIR")
            ESDE_SYS="${SYS_MAP[$RB_SYS]:-$RB_SYS}"
            ESDE_ROM_DIR="$ROMS/$ESDE_SYS"
            ESDE_MEDIA_DIR="$BASE/downloaded_media/$ESDE_SYS"
            ESDE_GAMELIST_DIR="$ESDE_DATA/gamelists/$ESDE_SYS"

            # Always create the destination — if ES-DE doesn't know the system
            # it simply won't show up; harmless to have the folder
            mkdir -p "$ESDE_ROM_DIR"

            echo -e "   ${CYAN}$RB_SYS${NC}$([ "$RB_SYS" != "$ESDE_SYS" ] && echo " → $ESDE_SYS")"
            IMPORT_SYSTEMS=$((IMPORT_SYSTEMS + 1))

            # Copy media — print before AND after each type so it's clear what's happening
            MEDIA_DIR="$SYS_DIR/media"
            if [[ -d "$MEDIA_DIR" ]]; then
                mkdir -p "$ESDE_MEDIA_DIR"
                for RB_TYPE in "${!MEDIA_MAP[@]}"; do
                    ESDE_TYPE="${MEDIA_MAP[$RB_TYPE]}"
                    SRC="$MEDIA_DIR/$RB_TYPE"
                    DST="$ESDE_MEDIA_DIR/$ESDE_TYPE"
                    if [[ -d "$SRC" ]]; then
                        mkdir -p "$DST"
                        TRANSFER_LABEL="${RETROBAT_MOVE:+cutting}${RETROBAT_MOVE:-copying}"
                        [[ "$RB_TYPE" == "videos" ]] \
                            && echo "      videos → videos            [$TRANSFER_LABEL — large sets take time...]" \
                            || echo -n "      $(printf '%-14s' "$RB_TYPE") → $(printf '%-14s' "$ESDE_TYPE") [$TRANSFER_LABEL...]"
                        if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                            find "$SRC" -maxdepth 1 -type f -exec mv -n {} "$DST/" \; 2>/dev/null || true
                        else
                            cp -rn "$SRC/." "$DST/" 2>/dev/null || true
                        fi
                        [[ "$RB_TYPE" == "videos" ]] \
                            && echo -e "      ${GREEN}✓${NC} videos done" \
                            || echo -e " ${GREEN}done${NC}"
                        IMPORT_MEDIA=$((IMPORT_MEDIA + 1))
                    fi
                done
            fi

            # Gamelist — clean, flatten paths for category-folder systems, merge with existing
            GAMELIST_SRC="$SYS_DIR/gamelist.xml"
            if [[ -f "$GAMELIST_SRC" ]]; then
                printf "      gamelist.xml   → cleaning...\n"
                mkdir -p "$ESDE_GAMELIST_DIR"
                python3 - "$GAMELIST_SRC" "$ESDE_GAMELIST_DIR/gamelist.xml" "$ESDE_SYS" 2>/dev/null << 'GLFIX' || warn "gamelist skipped for $RB_SYS (will still copy ROMs)"
import sys, re, os

src, dst, system = sys.argv[1], sys.argv[2], sys.argv[3]

# Systems where ROMs are in category subfolders — strip the subdir from paths
FLAT_SYSTEMS = {
    'c64','amiga','amigacd32','msx','msx2','vic20','atarist',
    'zxspectrum','zx81','dos','atari800','pc'
}
flatten = system in FLAT_SYSTEMS

tags = ['image','thumbnail','marquee','video','fanart',
        'boxart','titleshot','cartridge','mix',
        'wheel','sortname','genreid','arcadesystemname',
        'hash','crc32','md5','region','languages']
tag_re = re.compile(
    r'\s*<(?:' + '|'.join(tags) + r')>[^<]*</(?:' + '|'.join(tags) + r')>')
# Flatten subdir paths: ./subdir/game.ext → ./game.ext
path_re = re.compile(r'(<path>\./)[^/]+/(.+</path>)')

# Read existing destination gamelist paths to avoid duplicates on merge
existing_paths = set()
if os.path.exists(dst):
    with open(dst, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            m = re.search(r'<path>([^<]+)</path>', line)
            if m:
                existing_paths.add(m.group(1).strip())

# Process source gamelist
new_games = []
current_game = []
in_game = False
for line in open(src, 'r', encoding='utf-8', errors='replace'):
    cleaned = tag_re.sub('', line)
    if flatten:
        cleaned = path_re.sub(r'\1\2', cleaned)
    if '<game' in cleaned and not '</game' in cleaned:
        in_game = True
        current_game = [cleaned]
    elif '</game>' in cleaned and in_game:
        current_game.append(cleaned)
        block = ''.join(current_game)
        # Check if path already exists in destination
        m = re.search(r'<path>([^<]+)</path>', block)
        if m and m.group(1).strip() not in existing_paths:
            new_games.append(block)
        in_game = False
        current_game = []
    elif in_game:
        if cleaned.strip():
            current_game.append(cleaned)

if not new_games:
    sys.exit(0)

if os.path.exists(dst) and existing_paths:
    # Merge: insert new games before </gameList>
    with open(dst, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    insert = '\n'.join(new_games)
    content = content.replace('</gameList>', insert + '\n</gameList>')
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(content)
else:
    # Fresh write
    with open(dst, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0"?>\n<gameList>\n')
        f.writelines(new_games)
        f.write('</gameList>\n')
GLFIX
            fi

            # ROMs — detect category-folder systems and flatten, or preserve disc-game folders
            # Category systems (C64, Amiga, etc.) organise ROMs in subfolders like 1-hit/, 2-best/
            # Disc systems (PS2, PS3, GC, etc.) have per-game folders that must be preserved
            FLAT_ROM_SYSTEMS=(c64 amiga amigacd32 msx msx2 msx1 vic20 atarist
                              zxspectrum zx81 dos atari800 pc)
            IS_FLAT=false
            for FS in "${FLAT_ROM_SYSTEMS[@]}"; do
                [[ "$ESDE_SYS" == "$FS" || "$RB_SYS" == "$FS" ]] && IS_FLAT=true && break
            done

            TRANSFER_LABEL="${RETROBAT_MOVE:+cutting}${RETROBAT_MOVE:-copying}"
            echo -n "      ROMs                              [$TRANSFER_LABEL...]"
            COPIED=0

            if [[ "$IS_FLAT" == "true" ]]; then
                while IFS= read -r -d '' ROM; do
                    BASENAME=$(basename "$ROM")
                    [[ "$BASENAME" == _* ]] && continue
                    [[ "$BASENAME" == "gamelist"* ]] && continue
                    [[ "$BASENAME" == *.txt ]] && continue
                    [[ "$BASENAME" == *.xml ]] && continue
                    if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                        mv -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                    else
                        cp -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                    fi
                done < <(find "$SYS_DIR" -not -path "*/media/*" -type f -print0)
            else
                while IFS= read -r -d '' SUBDIR; do
                    DIRNAME=$(basename "$SUBDIR")
                    [[ "$DIRNAME" == "media" ]] && continue
                    echo ""
                    echo -n "        $DIRNAME [$TRANSFER_LABEL...]"
                    if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                        mv -n "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || cp -rn "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || true
                    else
                        cp -rn "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || true
                    fi
                    echo -e " ${GREEN}done${NC}"
                    COPIED=$((COPIED + 1))
                done < <(find "$SYS_DIR" -maxdepth 1 -mindepth 1 -type d -print0)
                while IFS= read -r -d '' ROM; do
                    BASENAME=$(basename "$ROM")
                    [[ "$BASENAME" == _* ]] && continue
                    [[ "$BASENAME" == "gamelist"* ]] && continue
                    [[ "$BASENAME" == *.txt ]] && continue
                    if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                        mv -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                    else
                        cp -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                    fi
                done < <(find "$SYS_DIR" -maxdepth 1 -type f -print0)
            fi
            [[ $COPIED -gt 0 ]] && echo -e " ${GREEN}done ($COPIED items)${NC}" || echo ""
            IMPORT_ROMS=$((IMPORT_ROMS + COPIED))

            echo -e "      ${GREEN}✓ done${NC}"
            echo ""
        done
    done

    ok "Import complete: $IMPORT_SYSTEMS systems, $IMPORT_MEDIA media types, $IMPORT_ROMS ROM items"
    echo ""
fi

#=============================================================================
# STEP 13: WRITE CONVERSION SCRIPT TO BUNDLE
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing convert-retrobat.sh to bundle..."

cat > "$BASE/convert-retrobat.sh" << 'CONVSCRIPT'
#!/usr/bin/env bash
#=============================================================================
# Portable ES-DE — RetroBat Collection Converter
# Run this anytime to import additional RetroBat collections.
# Usage: ./convert-retrobat.sh
#=============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
ROMS="$BASE/ROMs"
ESDE_DATA="$BASE/ES-DE"
MEDIA_BASE="$BASE/downloaded_media"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "   ${GREEN}✓${NC} $1"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; }
info() { echo -e "   ${CYAN}→${NC} $1"; }

echo ""
echo -e "${CYAN}RetroBat → ES-DE Converter${NC}"
echo ""

RETROBAT_PATHS=()
while true; do
    [[ ${#RETROBAT_PATHS[@]} -eq 0 ]] && PROMPT="Path" || PROMPT="Another path"
    read -rp "  $PROMPT (blank to continue): " INPUT
    [[ -z "$INPUT" ]] && break
    INPUT="${INPUT/#\~/$HOME}"
    INPUT="$(realpath -m "$INPUT")"
    if [[ -d "$INPUT/roms" ]]; then
        RETROBAT_PATHS+=("$INPUT")
        echo -e "   ${GREEN}✓${NC} Added: $INPUT"
    else
        echo -e "   ${YELLOW}⚠${NC} No 'roms' folder at $INPUT — skipping"
    fi
done

[[ ${#RETROBAT_PATHS[@]} -eq 0 ]] && echo "Nothing to import." && exit 0

RETROBAT_MOVE=""
echo "  How should files be transferred?"
echo -e "    C) Copy  — keep originals (safe, uses extra space)"
echo -e "    X) Cut   — move files as they're imported (no extra space needed)"
echo ""
read -rp "  [C/x]: " MOVE_CHOICE
[[ "${MOVE_CHOICE,,}" == "x" ]] && RETROBAT_MOVE="yes"
echo ""

declare -A MEDIA_MAP=(
    [thumbnails]=3dboxes [box2d]=covers [fanarts]=fanart [marquee]=marquees
    [images]=screenshots [titles]=titlescreens [cartridges]=physicalmedia [videos]=videos
)
declare -A SYS_MAP=(
    [sfc]=snes [snesna]=snes [nes_aladdin]=nes [nomad]=genesis [megadrivejp]=megadrive
    [n64dd]=n64 [sg1000]=sg-1000 [sc3000]=sg-1000 [markiii]=mastersystem
    [amiga4000]=amiga [msx1]=msx [videopacplus]=videopac
    [fbneo]=arcade [cave]=arcade [gaelco]=arcade [igspgm]=arcade [aleck64]=arcade
)
FLAT_ROM_SYSTEMS=(c64 amiga amigacd32 msx msx2 msx1 vic20 atarist zxspectrum zx81 dos atari800 pc)

IMPORT_SYSTEMS=0; IMPORT_MEDIA=0; IMPORT_ROMS=0

for RETROBAT_PATH in "${RETROBAT_PATHS[@]}"; do
    info "Importing from: $RETROBAT_PATH"
    if [[ -d "$RETROBAT_PATH/bios" ]]; then
        echo -n "   BIOS files → ROMs/bios/ [copying...]"
        cp -rn "$RETROBAT_PATH/bios/." "$ROMS/bios/" 2>/dev/null || true
        echo -e " ${GREEN}done${NC}"
    fi
    for SYS_DIR in "$RETROBAT_PATH/roms"/*/; do
        [[ -d "$SYS_DIR" ]] || continue
        RB_SYS=$(basename "$SYS_DIR")
        ESDE_SYS="${SYS_MAP[$RB_SYS]:-$RB_SYS}"
        ESDE_ROM_DIR="$ROMS/$ESDE_SYS"
        ESDE_MEDIA_DIR="$MEDIA_BASE/$ESDE_SYS"
        ESDE_GAMELIST_DIR="$ESDE_DATA/gamelists/$ESDE_SYS"
        mkdir -p "$ESDE_ROM_DIR"
        echo -e "   ${CYAN}$RB_SYS${NC}$([ "$RB_SYS" != "$ESDE_SYS" ] && echo " → $ESDE_SYS")"
        IMPORT_SYSTEMS=$((IMPORT_SYSTEMS + 1))
        MEDIA_DIR="$SYS_DIR/media"
        if [[ -d "$MEDIA_DIR" ]]; then
            mkdir -p "$ESDE_MEDIA_DIR"
            for RB_TYPE in "${!MEDIA_MAP[@]}"; do
                ESDE_TYPE="${MEDIA_MAP[$RB_TYPE]}"
                SRC="$MEDIA_DIR/$RB_TYPE"; DST="$ESDE_MEDIA_DIR/$ESDE_TYPE"
                if [[ -d "$SRC" ]]; then
                    mkdir -p "$DST"
                    [[ "$RB_TYPE" == "videos" ]] \
                        && echo "      videos → videos [copying — large sets take time...]" \
                        || echo -n "      $(printf '%-14s' "$RB_TYPE") → $(printf '%-14s' "$ESDE_TYPE") [copying...]"
                    cp -rn "$SRC/." "$DST/" 2>/dev/null || true
                    [[ "$RB_TYPE" == "videos" ]] \
                        && echo -e "      ${GREEN}✓${NC} videos done" \
                        || echo -e " ${GREEN}done${NC}"
                    IMPORT_MEDIA=$((IMPORT_MEDIA + 1))
                fi
            done
        fi
        GAMELIST_SRC="$SYS_DIR/gamelist.xml"
        if [[ -f "$GAMELIST_SRC" ]]; then
            printf "      gamelist.xml → cleaning...\n"
            mkdir -p "$ESDE_GAMELIST_DIR"
            python3 - "$GAMELIST_SRC" "$ESDE_GAMELIST_DIR/gamelist.xml" "$ESDE_SYS" 2>/dev/null << 'GLFIX' || warn "gamelist skipped"
import sys, re, os
src, dst, system = sys.argv[1], sys.argv[2], sys.argv[3]
FLAT_SYSTEMS = {'c64','amiga','amigacd32','msx','msx2','vic20','atarist','zxspectrum','zx81','dos','atari800','pc'}
flatten = system in FLAT_SYSTEMS
tags = ['image','thumbnail','marquee','video','fanart','boxart','titleshot','cartridge','mix','wheel','sortname','genreid','arcadesystemname','hash','crc32','md5','region','languages']
tag_re = re.compile(r'\s*<(?:' + '|'.join(tags) + r')>[^<]*</(?:' + '|'.join(tags) + r')>')
path_re = re.compile(r'(<path>\./)[^/]+/(.+</path>)')
existing_paths = set()
if os.path.exists(dst):
    with open(dst,'r',encoding='utf-8',errors='replace') as f:
        for line in f:
            m = re.search(r'<path>([^<]+)</path>', line)
            if m: existing_paths.add(m.group(1).strip())
new_games = []; current_game = []; in_game = False
for line in open(src,'r',encoding='utf-8',errors='replace'):
    cleaned = tag_re.sub('', line)
    if flatten: cleaned = path_re.sub(r'\1\2', cleaned)
    if '<game' in cleaned and '</game' not in cleaned:
        in_game = True; current_game = [cleaned]
    elif '</game>' in cleaned and in_game:
        current_game.append(cleaned); block = ''.join(current_game)
        m = re.search(r'<path>([^<]+)</path>', block)
        if m and m.group(1).strip() not in existing_paths: new_games.append(block)
        in_game = False; current_game = []
    elif in_game and cleaned.strip():
        current_game.append(cleaned)
if not new_games: sys.exit(0)
if os.path.exists(dst) and existing_paths:
    with open(dst,'r',encoding='utf-8',errors='replace') as f: content = f.read()
    content = content.replace('</gameList>', '\n'.join(new_games) + '\n</gameList>')
    with open(dst,'w',encoding='utf-8') as f: f.write(content)
else:
    with open(dst,'w',encoding='utf-8') as f:
        f.write('<?xml version="1.0"?>\n<gameList>\n')
        f.writelines(new_games)
        f.write('</gameList>\n')
GLFIX
        fi
        IS_FLAT=false
        for FS in "${FLAT_ROM_SYSTEMS[@]}"; do
            [[ "$ESDE_SYS" == "$FS" || "$RB_SYS" == "$FS" ]] && IS_FLAT=true && break
        done
        echo -n "      ROMs [copying...]"
        COPIED=0
        if [[ "$IS_FLAT" == "true" ]]; then
            while IFS= read -r -d '' ROM; do
                BASENAME=$(basename "$ROM")
                [[ "$BASENAME" == _* || "$BASENAME" == "gamelist"* || "$BASENAME" == *.txt || "$BASENAME" == *.xml ]] && continue
                cp -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED+1)) || true
            done < <(find "$SYS_DIR" -not -path "*/media/*" -type f -print0)
        else
            while IFS= read -r -d '' SUBDIR; do
                DIRNAME=$(basename "$SUBDIR"); [[ "$DIRNAME" == "media" ]] && continue
                echo ""; echo -n "        $DIRNAME [copying...]"
                cp -rn "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || true
                echo -e " ${GREEN}done${NC}"; COPIED=$((COPIED+1))
            done < <(find "$SYS_DIR" -maxdepth 1 -mindepth 1 -type d -print0)
            while IFS= read -r -d '' ROM; do
                BASENAME=$(basename "$ROM")
                [[ "$BASENAME" == _* || "$BASENAME" == "gamelist"* || "$BASENAME" == *.txt ]] && continue
                cp -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED+1)) || true
            done < <(find "$SYS_DIR" -maxdepth 1 -type f -print0)
        fi
        [[ $COPIED -gt 0 ]] && echo -e " ${GREEN}done ($COPIED items)${NC}" || echo ""
        IMPORT_ROMS=$((IMPORT_ROMS + COPIED))
        echo -e "      ${GREEN}✓ done${NC}"; echo ""
    done
    if [[ "$RETROBAT_MOVE" == "yes" ]]; then
        rm -rf "$RETROBAT_PATH/roms" "$RETROBAT_PATH/bios" 2>/dev/null || true
        ok "Removed source files from $RETROBAT_PATH"
    fi
done
echo ""
ok "Import complete: $IMPORT_SYSTEMS systems, $IMPORT_MEDIA media types, $IMPORT_ROMS items"
CONVSCRIPT

chmod +x "$BASE/convert-retrobat.sh"
ok "convert-retrobat.sh written to bundle"

#=============================================================================
# STEP 14: WRITE UPDATE SCRIPT TO BUNDLE
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing update.sh to bundle..."

cat > "$BASE/update.sh" << 'UPDATESCRIPT'
#!/usr/bin/env bash
#=============================================================================
# Portable ES-DE — Emulator Update Script
# Checks for newer versions of all installed emulators and updates them.
# Usage: ./update.sh
#=============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMUS="$SCRIPT_DIR/Emulators"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "   ${GREEN}✓${NC} $1"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $1"; }
info() { echo -e "   ${CYAN}→${NC} $1"; }

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Portable ES-DE — Emulator Updater        ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════╝${NC}"
echo ""

github_latest_url() {
    local repo="$1" pattern="$2"
    curl -sfL "https://api.github.com/repos/$repo/releases?per_page=5" \
        | grep -oP '"browser_download_url":\s*"\K[^"]*' \
        | grep -P "$pattern" \
        | head -1
}

check_and_update() {
    local label="$1" current_glob="$2" latest_url="$3" new_name="$4"
    local current_file
    current_file=$(find "$EMUS" -maxdepth 1 -name "$current_glob" 2>/dev/null | head -1)
    [[ -z "$current_file" ]] && { warn "$label — not installed"; return; }

    local current_name latest_name
    current_name=$(basename "$current_file")
    latest_name=$(basename "$latest_url")
    printf "   %-32s" "$label"

    if [[ -z "$latest_url" ]]; then
        echo -e " ${YELLOW}[could not check]${NC}"; return
    fi
    if [[ "$current_name" == "$latest_name" ]]; then
        echo -e " ${GREEN}[up to date]${NC}  $current_name"; return
    fi

    echo -e " ${YELLOW}[update available]${NC}"
    echo -e "      Current: $current_name"
    echo -e "      Latest:  $latest_name"
    read -rp "      Update? [y/N]: " CONFIRM
    if [[ "${CONFIRM,,}" == "y" ]]; then
        info "Downloading $latest_name ..."
        if curl -#fL -o "$EMUS/$new_name.tmp" "$latest_url"; then
            mv "$EMUS/$new_name.tmp" "$EMUS/$latest_name"
            chmod +x "$EMUS/$latest_name"
            [[ "$current_file" != "$EMUS/$latest_name" ]] && rm -f "$current_file"
            ok "Updated to $latest_name"
        else
            warn "Download failed — keeping current version"
            rm -f "$EMUS/$new_name.tmp"
        fi
    else
        info "Skipped"
    fi
    echo ""
}

# ── ES-DE ──
echo -e "${CYAN}ES-DE Frontend:${NC}"
ESDE_CURRENT=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'ES-DE*.AppImage' | head -1)
if [[ -n "$ESDE_CURRENT" ]]; then
    printf "   %-32s" "ES-DE"
    ESDE_URL=$(curl -sfL "https://es-de.org/" \
        | grep -oP 'https?://gitlab\.com/es-de/emulationstation-de/-/package_files/[0-9]+/download' \
        | head -1) || true
    if [[ -n "$ESDE_URL" ]]; then
        echo -e " ${CYAN}[visit https://es-de.org/ to check version]${NC}"
        echo -e "      Installed: $(basename "$ESDE_CURRENT")"
        read -rp "      Re-download latest ES-DE? [y/N]: " ESDE_CONFIRM
        if [[ "${ESDE_CONFIRM,,}" == "y" ]]; then
            if curl -#fL -o "$SCRIPT_DIR/ES-DE_x64.AppImage.tmp" "$ESDE_URL"; then
                mv "$SCRIPT_DIR/ES-DE_x64.AppImage.tmp" "$SCRIPT_DIR/ES-DE_x64.AppImage"
                chmod +x "$SCRIPT_DIR/ES-DE_x64.AppImage"
                [[ "$ESDE_CURRENT" != "$SCRIPT_DIR/ES-DE_x64.AppImage" ]] && rm -f "$ESDE_CURRENT"
                ok "ES-DE updated"
            else
                warn "Download failed"; rm -f "$SCRIPT_DIR/ES-DE_x64.AppImage.tmp"
            fi
        fi
    else
        echo -e " ${YELLOW}[could not check]${NC}"
    fi
fi
echo ""

# ── Standalone emulators ──
echo -e "${CYAN}Standalone Emulators:${NC}"
echo ""

# RPCS3 (uses redirect URL, always latest)
RPCS3_CURRENT=$(find "$EMUS" -maxdepth 1 -name 'rpcs3*.AppImage' | head -1)
if [[ -n "$RPCS3_CURRENT" ]]; then
    printf "   %-32s" "RPCS3 (PS3)"
    echo -e " ${CYAN}[nightly — always latest when re-downloaded]${NC}"
    read -rp "      Re-download latest? [y/N]: " RPCS3_CONFIRM
    if [[ "${RPCS3_CONFIRM,,}" == "y" ]]; then
        if (cd "$EMUS" && curl -#fJLO "https://rpcs3.net/latest-linux-x64"); then
            RPCS3_NEW=$(find "$EMUS" -maxdepth 1 -name 'rpcs3*.AppImage' | sort -r | head -1)
            [[ "$RPCS3_NEW" != "$RPCS3_CURRENT" ]] && chmod +x "$RPCS3_NEW" && rm -f "$RPCS3_CURRENT"
            ok "RPCS3 updated"
        else
            warn "Download failed"
        fi
    fi
    echo ""
fi

# RetroArch (nightly)
RA_CURRENT=$(find "$EMUS" -maxdepth 1 -name 'RetroArch*.AppImage' | head -1)
if [[ -n "$RA_CURRENT" ]]; then
    printf "   %-32s" "RetroArch"
    echo -e " ${CYAN}[nightly — always latest when re-downloaded]${NC}"
    read -rp "      Re-download latest nightly? [y/N]: " RA_CONFIRM
    if [[ "${RA_CONFIRM,,}" == "y" ]]; then
        RA_URL="https://github.com/hizzlekizzle/RetroArch-AppImage/releases/download/Linux_LTS_Nightlies/RetroArch-Linux-x86_64-Nightly.AppImage"
        if curl -#fL -o "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage.tmp" "$RA_URL"; then
            mv "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage.tmp" "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage"
            chmod +x "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage"
            ok "RetroArch updated"
        else
            warn "Download failed"; rm -f "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage.tmp"
        fi
    fi
    echo ""
fi

check_and_update "PCSX2 (PS2)" "pcsx2*.AppImage" \
    "$(github_latest_url PCSX2/pcsx2 'linux-appimage-x64.*\.AppImage$')" "pcsx2-latest"

check_and_update "DuckStation (PS1)" "DuckStation*.AppImage" \
    "$(github_latest_url stenzek/duckstation 'DuckStation.*x64.*\.AppImage$')" "DuckStation-x64"

check_and_update "PPSSPP (PSP)" "PPSSPP*.AppImage" \
    "$(github_latest_url hrydgard/ppsspp 'PPSSPP.*x86_64.*\.AppImage$')" "PPSSPP-latest"

check_and_update "melonDS (DS)" "melonDS*.AppImage" \
    "$(github_latest_url pkgforge-dev/melonDS-AppImage-Enhanced 'melonDS.*x86_64.*\.AppImage$')" "melonDS-latest"

check_and_update "Dolphin (GC/Wii)" "dolphin*.AppImage" \
    "$(github_latest_url pkgforge-dev/Dolphin-emu-AppImage 'Dolphin_Emulator.*x86_64.*\.AppImage$')" "dolphin-emu-latest"

check_and_update "Cemu (Wii U)" "Cemu*.AppImage" \
    "$(github_latest_url cemu-project/Cemu 'Cemu.*\.AppImage$')" "Cemu-latest"

AZAHAR_URL=$(curl -sfL "https://api.github.com/repos/azahar-emu/azahar/releases?per_page=5" \
    | grep -oP '"browser_download_url":\s*"\K[^"]*azahar\.AppImage(?!-)' | head -1) || true
check_and_update "Azahar (3DS)" "azahar*.AppImage" "$AZAHAR_URL" "azahar"

check_and_update "xemu (Xbox)" "xemu*.AppImage" \
    "$(github_latest_url xemu-project/xemu 'xemu.*x86_64\.AppImage$')" "xemu-latest"

check_and_update "Eden (Switch)" "Eden*.AppImage" \
    "$(github_latest_url eden-emulator/Releases 'Eden-Linux.*x86_64.*\.AppImage$')" "Eden-latest"

# ── RetroArch Cores ──
echo ""
echo -e "${CYAN}RetroArch Cores:${NC}"
read -rp "   Update all cores from buildbot.libretro.com? [y/N]: " CORES_CONFIRM
if [[ "${CORES_CONFIRM,,}" == "y" ]]; then
    CORE_DIR="$EMUS/retroarch-cores"
    CORE_URL="https://buildbot.libretro.com/nightly/linux/x86_64/latest"
    UPDATED=0; FAILED=0
    for SO in "$CORE_DIR"/*.so; do
        [[ -f "$SO" ]] || continue
        CORE_NAME=$(basename "$SO" _libretro.so)
        ZIP="${CORE_NAME}_libretro.so.zip"
        printf "   %-35s" "$CORE_NAME"
        if curl -sfL -o "/tmp/$ZIP" "$CORE_URL/$ZIP" 2>/dev/null && \
           unzip -qo "/tmp/$ZIP" -d "$CORE_DIR" 2>/dev/null; then
            echo -e " ${GREEN}[ok]${NC}"
            UPDATED=$((UPDATED + 1))
        else
            echo -e " ${YELLOW}[skipped]${NC}"
        fi
        rm -f "/tmp/$ZIP"
    done
    echo ""
    ok "Cores: $UPDATED updated, $FAILED failed"
fi

echo ""
echo -e "${BOLD}Update check complete.${NC}"
echo ""
UPDATESCRIPT

chmod +x "$BASE/update.sh"
ok "update.sh written to bundle"

#=============================================================================
# STEP 15: DESKTOP SHORTCUT
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Desktop shortcut..."

if [[ "$CREATE_SHORTCUT" == "yes" ]]; then
    DESKTOP_DIR="$HOME/.local/share/applications"
    mkdir -p "$DESKTOP_DIR"

    # Extract ES-DE icon from AppImage if present
    ESDE_APPIMAGE=$(find "$BASE" -maxdepth 1 -name 'ES-DE*.AppImage' | head -1)
    ICON_PATH="$BASE/ES-DE/es-de.png"
    if [[ -n "$ESDE_APPIMAGE" && ! -f "$ICON_PATH" ]]; then
        info "Extracting ES-DE icon..."
        (cd /tmp && "$ESDE_APPIMAGE" --appimage-extract usr/bin/es-de.png 2>/dev/null || true)
        [[ -f /tmp/squashfs-root/usr/bin/es-de.png ]] && \
            cp /tmp/squashfs-root/usr/bin/es-de.png "$ICON_PATH" && \
            rm -rf /tmp/squashfs-root
    fi
    [[ ! -f "$ICON_PATH" ]] && ICON_PATH="applications-games"

    cat > "$DESKTOP_DIR/es-de-portable.desktop" << DESKTOPFILE
[Desktop Entry]
Version=1.0
Type=Application
Name=ES-DE (Portable)
Comment=Retro gaming frontend — portable bundle
Exec=${BASE}/launch.sh
Icon=${ICON_PATH}
Terminal=false
Categories=Game;Emulator;
Keywords=retro;emulator;gaming;
StartupNotify=true
DESKTOPFILE

    # Refresh application menu (works for GNOME, KDE, XFCE, Cinnamon, MATE)
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    # KDE-specific refresh
    if command -v kbuildsycoca6 &>/dev/null; then
        kbuildsycoca6 2>/dev/null || true
    elif command -v kbuildsycoca5 &>/dev/null; then
        kbuildsycoca5 2>/dev/null || true
    fi

    ok "Shortcut created: $DESKTOP_DIR/es-de-portable.desktop"
    ok "ES-DE should appear in your Games/Emulators application menu"
else
    ok "Skipped"
fi

#=============================================================================
# STEP 16: SUMMARY
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Summary"
echo ""

# Count what we got
APPIMAGE_COUNT=0
for f in "$BASE"/*.AppImage "$EMUS"/*.AppImage; do
    [[ -f "$f" ]] && APPIMAGE_COUNT=$((APPIMAGE_COUNT + 1))
done
CORE_COUNT=0
[[ -d "$EMUS/retroarch-cores" ]] && CORE_COUNT=$(find "$EMUS/retroarch-cores" -name '*.so' 2>/dev/null | wc -l)

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Setup complete!                                         ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo -e "║  ${GREEN}$APPIMAGE_COUNT AppImages${NC} downloaded                            ║"
echo -e "║  ${GREEN}$CORE_COUNT RetroArch cores${NC} installed                        ║"

if ((DOWNLOAD_ERRORS > 0)); then
    echo -e "║  ${YELLOW}$DOWNLOAD_ERRORS download(s) need manual attention${NC}              ║"
fi

echo "║                                                          ║"
echo "║  Downloaded emulators:                                   ║"
for f in "$BASE"/*.AppImage "$EMUS"/*.AppImage "$EMUS"/xenia_canary; do
    [[ -f "$f" ]] && echo -e "║    ${GREEN}✓${NC} $(basename "$f")"
done

echo "║                                                          ║"
echo "║  To start playing:                                       ║"
echo "║    1. Add ROMs → ROMs/<system>/                          ║"
echo "║    2. Add BIOS files → ROMs/bios/                        ║"
echo "║    3. Run: ./launch.sh                                   ║"
echo "║                                                          ║"
echo -e "║  Bundle location: ${CYAN}${BASE}${NC}"
echo "║                                                          ║"
echo "║  Re-run this script anytime to retry failed downloads    ║"
echo "║  or to update after a new ES-DE release.                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
