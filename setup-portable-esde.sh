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

# ── Whiptail theme ──
# Dark background with cyan borders/accents so the TUI matches the script's
# terminal output palette (cyan headers, green ok, red errors). Eliminates
# the jarring blue-default whiptail popup look.
export NEWT_COLORS='
root=,black
window=white,black
shadow=black,black
title=brightcyan,black
border=cyan,black
textbox=white,black
button=black,cyan
actbutton=black,brightcyan
compactbutton=cyan,black
checkbox=white,black
actcheckbox=black,cyan
entry=white,black
actentry=black,brightcyan
disentry=gray,black
label=white,black
listbox=white,black
actlistbox=black,cyan
sellistbox=brightgreen,black
actsellistbox=black,brightgreen
menu=white,black
actmenu=black,cyan
emptyscale=black,black
fullscale=,cyan
helpline=brightcyan,black
roottext=cyan,black
'

ok()   { echo -e "   ${GREEN}✓${NC} $1"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; }
info() { echo -e "   ${CYAN}→${NC} $1"; }

#=============================================================================
# Whiptail UI helpers — used for ALL interactive prompts in the setup script.
# The one exception is the bootstrap "install whiptail?" prompt below, which
# necessarily uses bash read since whiptail isn't available yet at that point.
#=============================================================================

# Auto-size dialogs to fit any terminal — computed once at startup.
# Cols floor 60 (very narrow), cap 100 (avoid stretched look on wide monitors).
# Lines floor 14 (minimum for menus), cap 30 (avoid huge boxes on tall terminals).
_term_cols=$(tput cols 2>/dev/null || echo 80)
_term_lines=$(tput lines 2>/dev/null || echo 24)
WT_W=$(( _term_cols - 4 ))
(( WT_W > 100 )) && WT_W=100
(( WT_W < 60 ))  && WT_W=60
WT_H=$(( _term_lines - 4 ))
(( WT_H > 30 )) && WT_H=30
(( WT_H < 14 )) && WT_H=14
# Tall variant for menus/checklists with many items
WT_H_TALL=$(( _term_lines - 4 ))
(( WT_H_TALL > 40 )) && WT_H_TALL=40
(( WT_H_TALL < 18 )) && WT_H_TALL=18
unset _term_cols _term_lines

wt_input() {
    # wt_input "title" "prompt" "default" → echoes user input; nonzero exit on Cancel
    whiptail --title "$1" --inputbox "$2" "$WT_H" "$WT_W" "$3" 3>&1 1>&2 2>&3
}
wt_yesno() {
    # wt_yesno "title" "prompt" → returns 0 (yes) or 1 (no/Cancel/Esc)
    whiptail --title "$1" --yesno "$2" "$WT_H" "$WT_W"
}
wt_menu() {
    # wt_menu "title" "prompt" tag1 item1 tag2 item2 ... → echoes selected tag
    local title="$1" prompt="$2"; shift 2
    local menu_h=$(( WT_H_TALL > 22 ? 22 : WT_H_TALL ))
    whiptail --title "$title" --menu "$prompt" "$menu_h" "$WT_W" 12 "$@" 3>&1 1>&2 2>&3
}
wt_msg() {
    # wt_msg "title" "message" → informational dialog
    whiptail --title "$1" --msgbox "$2" "$WT_H" "$WT_W"
}

#=============================================================================
# detect_pkg_manager / ensure_whiptail
# Run BEFORE any user-facing prompt so the rest of setup can use whiptail.
#=============================================================================
detect_pkg_manager() {
    PKG_INSTALL_CMD=()
    PKG_MANUAL_HINT=""
    if [[ -e /run/ostree-booted ]] && command -v rpm-ostree >/dev/null 2>&1; then
        PKG_MANUAL_HINT="Your system is immutable (rpm-ostree — e.g. Bazzite, Silverblue, Kinoite).
   Install with:
     ${CYAN}sudo rpm-ostree install newt${NC}
   Then reboot and re-run this installer."
        return
    fi
    if [[ -f /etc/os-release ]] && grep -qiE '^ID=.*steamos' /etc/os-release; then
        PKG_MANUAL_HINT="SteamOS has a read-only /usr. Disable it first:
     ${CYAN}sudo steamos-readonly disable${NC}
     ${CYAN}sudo pacman -Sy libnewt${NC}
     ${CYAN}sudo steamos-readonly enable${NC}
   Then re-run this installer."
        return
    fi
    if command -v apt-get >/dev/null 2>&1; then
        PKG_INSTALL_CMD=(sudo apt-get install -y whiptail)
    elif command -v dnf >/dev/null 2>&1; then
        PKG_INSTALL_CMD=(sudo dnf install -y newt)
    elif command -v pacman >/dev/null 2>&1; then
        PKG_INSTALL_CMD=(sudo pacman -S --noconfirm libnewt)
    elif command -v zypper >/dev/null 2>&1; then
        PKG_INSTALL_CMD=(sudo zypper install -y newt)
    fi
}

ensure_whiptail() {
    # Called once at script start, before any prompt. Bootstrap: if whiptail
    # isn't installed, this is the ONLY allowed bash `read` in the whole flow
    # (chicken-and-egg — can't use whiptail to ask whether to install whiptail).
    command -v whiptail >/dev/null 2>&1 && return 0
    detect_pkg_manager
    echo ""
    echo -e "   ${YELLOW}!${NC} ${BOLD}whiptail${NC} is required by this installer (used for all prompts) but is not installed."
    echo ""
    if (( ${#PKG_INSTALL_CMD[@]} > 0 )); then
        echo -e "   Install command:  ${CYAN}${PKG_INSTALL_CMD[*]}${NC}"
        echo ""
        read -r -p "   Install whiptail now and continue setup? [Y/n]: " ans
        if [[ "${ans,,}" == "n" ]]; then
            echo ""
            echo "   Aborted. Install whiptail manually and re-run when ready."
            exit 0
        fi
        echo ""
        info "Installing whiptail (you may be prompted for your sudo password)..."
        if "${PKG_INSTALL_CMD[@]}"; then
            if ! command -v whiptail >/dev/null 2>&1; then
                fail "Install reported success but whiptail still isn't in PATH."
                echo "   Please install manually and re-run."
                exit 1
            fi
            ok "whiptail installed — continuing setup"
            echo ""
        else
            fail "Install failed."
            echo -e "   Try manually:  ${CYAN}${PKG_INSTALL_CMD[*]}${NC}"
            echo "   Then re-run this installer."
            exit 1
        fi
    elif [[ -n "$PKG_MANUAL_HINT" ]]; then
        echo -e "   $PKG_MANUAL_HINT"
        echo ""
        exit 1
    else
        echo "   Couldn't detect your package manager. Install manually with one of:"
        echo -e "     ${CYAN}sudo apt install whiptail${NC}     (Debian/Ubuntu/Mint/Pop!_OS)"
        echo -e "     ${CYAN}sudo dnf install newt${NC}         (Fedora/Nobara)"
        echo -e "     ${CYAN}sudo pacman -S libnewt${NC}        (Arch/Manjaro)"
        echo -e "     ${CYAN}sudo zypper install newt${NC}      (openSUSE)"
        echo "   Then re-run this installer."
        echo ""
        exit 1
    fi
}

# Bootstrap whiptail before any other prompt
ensure_whiptail

#=============================================================================
# INTERACTIVE INSTALL PATH
#=============================================================================
DEFAULT_PATH="$(pwd)/ES-DE-Portable"

USER_PATH=$(wt_input "Portable ES-DE Setup v${VERSION}" \
"A complete retro gaming bundle for Linux.

Where would you like to install the bundle?

Press Enter (or OK) to accept the default below, or edit to a different path. You can use ~ for your home directory." \
"$DEFAULT_PATH") || { echo "Cancelled."; exit 0; }

BASE="${USER_PATH:-$DEFAULT_PATH}"

# Expand ~ if used
BASE="${BASE/#\~/$HOME}"

# Make absolute
BASE="$(realpath -m "$BASE")"

# Check if directory exists and has content
if [[ -d "$BASE" ]] && [[ -n "$(ls -A "$BASE" 2>/dev/null)" ]]; then
    if ! wt_yesno "Directory not empty" \
"The target directory already exists and is not empty:

  $BASE

Existing files will be preserved — only missing items will be added.

Continue?"; then
        echo "Aborted."
        exit 0
    fi
fi

EMUS="$BASE/Emulators"
ROMS="$BASE/ROMs"
ESDE_DATA="$BASE/ES-DE"         # ES-DE --home puts all its data here

#=============================================================================
# COMPONENT SELECTION TUI
#=============================================================================
# Lets users skip emulators/cores they don't need. Decision flow:
#   1. No TTY (piped / CI) → skip TUI entirely → full install.
#   2. Prompt: Full vs Custom.
#   3. Custom: whiptail checklist for emulators, then cores. Selections
#      cached to .setup-selections.cfg in the bundle root for sticky re-runs.
# State lives in two associative arrays:
#   SELECTED_EMULATORS[<key>] = 1 (install) | 0 (skip)
#   SELECTED_CORES[<key>]     = 1 (install) | 0 (skip)
# Each download block checks ${SELECTED_*[<key>]:-1} — absent keys default to
# install, so a non-TUI run reproduces today's behavior exactly.

declare -A SELECTED_EMULATORS=()
declare -A SELECTED_CORES=()

EMULATOR_CHECKLIST=(
    "retroarch|RetroArch — libretro frontend (needed for cores)"
    "dolphin|Dolphin — GameCube / Wii"
    "cemu|Cemu — Wii U"
    "rpcs3|RPCS3 — PlayStation 3"
    "pcsx2|PCSX2 — PlayStation 2"
    "duckstation|DuckStation — PlayStation 1"
    "ppsspp|PPSSPP — PlayStation Portable"
    "shadps4|shadPS4 — PlayStation 4"
    "ryujinx|Ryubing — Nintendo Switch (Ryujinx fork)"
    "eden|Eden — Nintendo Switch (alt fork)"
    "azahar|Azahar — Nintendo 3DS"
    "melonds|melonDS — Nintendo DS"
    "xemu|xemu — Original Xbox"
    "xenia|Xenia Canary — Xbox 360"
    "mame|MAME (standalone) — arcade + fallback"
    "supermodel|Supermodel — Sega Model 3"
    "dosbox_x|DOSBox-X — DOS / x86 PC"
    "_86box|86Box — Windows 9x / retro PC"
    "vpinball|Visual Pinball — virtual pinball tables"
    "solarus|Solarus — Zelda-like RPGs"
    "ruffle|Ruffle — Adobe Flash games"
    "simcoupe|SimCoupé — SAM Coupé"
    "eka2l1|EKA2L1 — Symbian / N-Gage"
)

# Section divider tags used in CORE_CHECKLIST to group cores visually.
# Detected and skipped at install time (they're labels, not installable items).
declare -A IS_SECTION_HEADER=(
    [Nintendo]=1 [Sega]=1 [Sony]=1 [Atari]=1 [NEC]=1 [SNK]=1
    [Arcade]=1 [Portable]=1 [Computers]=1 [Consoles]=1 [Fantasy]=1 [Other]=1
)

CORE_CHECKLIST=(
    "Nintendo|─── Nintendo ───"
    "fceumm|FCEUmm — NES / Famicom / FDS"
    "mesen|Mesen — NES/Famicom (high accuracy, alt)"
    "snes9x|Snes9x — Super Nintendo / Super Famicom"
    "mesen-s|Mesen-S — SGB/SNES (high accuracy)"
    "mgba|mGBA — Game Boy Advance / GB / GBC"
    "gambatte|Gambatte — Game Boy / Game Boy Color (alt)"
    "mupen64plus_next|Mupen64Plus-Next — Nintendo 64"
    "pokemini|PokéMini — Pokémon Mini"
    "gw|GW — Game & Watch (alt to MAME)"
    "Sega|─── Sega ───"
    "genesis_plus_gx|Genesis Plus GX — Genesis/MD/MS/GG/SG-1000/CD"
    "picodrive|Picodrive — 32X / Sega CD (alt)"
    "flycast|Flycast — Dreamcast"
    "mednafen_saturn|Beetle Saturn — Sega Saturn"
    "kronos|Kronos — Saturn (high accuracy, alt)"
    "Sony|─── Sony ───"
    "mednafen_psx|Beetle PSX — PS1 (high accuracy)"
    "mednafen_psx_hw|Beetle PSX HW — PS1 (hardware renderer)"
    "Atari|─── Atari ───"
    "stella|Stella — Atari 2600"
    "a5200|a5200 — Atari 5200"
    "atari800|Atari800 — 800/5200/XEGS"
    "prosystem|ProSystem — Atari 7800"
    "handy|Handy — Atari Lynx"
    "hatari|Hatari — Atari ST"
    "virtualjaguar|Virtual Jaguar — Atari Jaguar"
    "NEC|─── NEC ───"
    "mednafen_pce|Beetle PCE — PCE/TG-16/SuperGrafx"
    "mednafen_pce_fast|Beetle PCE Fast — PCE CD/TG-CD"
    "mednafen_pcfx|Beetle PC-FX — PC-FX"
    "mednafen_supergrafx|Beetle SuperGrafx"
    "np2kai|Neko Project II Kai — NEC PC-9800"
    "SNK|─── SNK ───"
    "mednafen_ngp|Beetle NeoPop — NGP/NGPC"
    "fbneo|FinalBurn Neo — Arcade/Neo Geo/Neo Geo CD"
    "neocd|NeoCD — Neo Geo CD (dedicated)"
    "Arcade|─── Arcade / MAME ───"
    "mame|MAME — current (Archimedes, Model2/3, LCDs, etc.)"
    "mame2003_plus|MAME 2003-Plus — arcade (post-2003 sets)"
    "mame2010|MAME 2010 — v0.139 (deeper BIOS fallback)"
    "Portable|─── Other handhelds / portables ───"
    "mednafen_vb|Beetle VB — Virtual Boy"
    "mednafen_wswan|Beetle WonderSwan — WS/WSC"
    "potator|Potator — Watara Supervision"
    "sameduck|SameDuck — Mega Duck"
    "arduous|Arduous — Arduboy"
    "Computers|─── Home computers ───"
    "fuse|Fuse — ZX Spectrum"
    "81|EightyOne — ZX81"
    "vice_x64|VICE x64 — Commodore 64"
    "vice_x64sc|VICE x64sc — C64 (high accuracy, alt)"
    "vice_xvic|VICE xvic — VIC-20"
    "vice_xplus4|VICE xplus4 — Commodore Plus/4"
    "puae|PUAE — Commodore Amiga"
    "bluemsx|blueMSX — MSX/MSX2/Turbo R/Spectravideo/Coleco"
    "cap32|Caprice32 — Amstrad CPC / GX4000"
    "quasi88|Quasi88 — NEC PC-88 (alt)"
    "x1|X1 — Sharp X1"
    "px68k|PX68k — Sharp X68000"
    "b2|B2 — BBC Micro / BBC Master"
    "Consoles|─── Other consoles ───"
    "o2em|O2EM — Odyssey²/Videopac"
    "vecx|VecX — GCE Vectrex"
    "freechaf|FreeChaF — Fairchild Channel F"
    "freeintv|FreeIntv — Mattel Intellivision"
    "uzem|Uzem — Uzebox"
    "opera|Opera — 3DO Interactive Multiplayer"
    "amiarcadia|Amiarcadia — Emerson Arcadia 2001"
    "jollycv|JollyCV — VTech CreatiVision"
    "Fantasy|─── Fantasy consoles / engines ───"
    "retro8|Retro8 — PICO-8-compatible"
    "tic80|TIC-80 — fantasy console"
    "wasm4|WASM-4 — fantasy console"
    "lowresnx|LowRes NX — fantasy console"
    "lutro|Lutro — Lua game engine"
    "easyrpg|EasyRPG — RPG Maker 2000/2003"
    "Other|─── Other ───"
    "scummvm|ScummVM — point-and-click adventures"
    "dosbox_pure|DOSBox Pure — DOS (libretro fallback)"
)

SELECTIONS_CACHE="$BASE/.setup-selections.cfg"

detect_tui_tool() {
    if command -v whiptail >/dev/null 2>&1; then
        TUI_TOOL="whiptail"
    else
        TUI_TOOL=""
    fi
}

# Detect package manager for auto-installing whiptail when missing.
# Sets PKG_INSTALL_CMD (array — runnable command) on mutable distros,
# or PKG_MANUAL_HINT (string) on immutable distros where auto-install
# isn't safe (rpm-ostree systems, SteamOS with read-only /usr).
detect_pkg_manager() {
    PKG_INSTALL_CMD=()
    PKG_MANUAL_HINT=""

    # Immutable systems first — these need manual handling
    if [[ -e /run/ostree-booted ]] && command -v rpm-ostree >/dev/null 2>&1; then
        PKG_MANUAL_HINT="Your system is immutable (rpm-ostree — e.g. Bazzite, Silverblue, Kinoite).
   Install with:
     ${CYAN}sudo rpm-ostree install newt${NC}
   Then reboot and re-run this installer."
        return
    fi
    if [[ -f /etc/os-release ]] && grep -qiE '^ID=.*steamos' /etc/os-release; then
        PKG_MANUAL_HINT="SteamOS has a read-only /usr. Disable it first:
     ${CYAN}sudo steamos-readonly disable${NC}
     ${CYAN}sudo pacman -Sy libnewt${NC}
     ${CYAN}sudo steamos-readonly enable${NC}
   Then re-run this installer."
        return
    fi

    # Mutable systems — pick the package manager
    if command -v apt-get >/dev/null 2>&1; then
        PKG_INSTALL_CMD=(sudo apt-get install -y whiptail)
    elif command -v dnf >/dev/null 2>&1; then
        PKG_INSTALL_CMD=(sudo dnf install -y newt)
    elif command -v pacman >/dev/null 2>&1; then
        PKG_INSTALL_CMD=(sudo pacman -S --noconfirm libnewt)
    elif command -v zypper >/dev/null 2>&1; then
        PKG_INSTALL_CMD=(sudo zypper install -y newt)
    fi
}

load_selections_cache() {
    [[ -f "$SELECTIONS_CACHE" ]] || return 0
    local key val
    while IFS='=' read -r key val; do
        [[ -z "$key" || "$key" == "#"* ]] && continue
        case "$key" in
            EMU_*) SELECTED_EMULATORS["${key#EMU_}"]="$val" ;;
            CORE_*) SELECTED_CORES["${key#CORE_}"]="$val" ;;
        esac
    done < "$SELECTIONS_CACHE"
}

save_selections_cache() {
    # Ensure $BASE exists — TUI runs before STEP 1's mkdir, so on a fresh install
    # the directory hasn't been created yet
    mkdir -p "$BASE" 2>/dev/null || true
    {
        echo "# Portable-ES-DE component selections"
        echo "# Format: EMU_<key>=0|1 or CORE_<key>=0|1"
        local k
        for k in "${!SELECTED_EMULATORS[@]}"; do echo "EMU_${k}=${SELECTED_EMULATORS[$k]}"; done
        for k in "${!SELECTED_CORES[@]}"; do echo "CORE_${k}=${SELECTED_CORES[$k]}"; done
    } > "$SELECTIONS_CACHE"
}

tui_checklist() {
    local title="$1" backtitle="$2"; shift 2
    local listheight=$(( WT_H_TALL - 8 ))
    local args=("--title" "$title" "--backtitle" "$backtitle" "--separate-output"
                "--checklist" "SPACE = toggle, TAB = buttons, ENTER = confirm."
                "$WT_H_TALL" "$WT_W" "$listheight" "$@")
    "$TUI_TOOL" "${args[@]}" 3>&1 1>&2 2>&3
}

tui_menu_full_or_custom() {
    "$TUI_TOOL" --title "Portable ES-DE for Linux — Component Selection" \
            --backtitle "Setup will download emulators and libretro cores." \
            --menu "Choose installation mode:" "$WT_H" "$WT_W" 4 \
            "1" "Full install (recommended) — every emulator + core, ~3 GB" \
            "2" "Custom — pick which emulators and cores to install" \
            3>&1 1>&2 2>&3
}

tui_select_components() {
    if [[ ! -t 0 || ! -t 1 ]]; then return 0; fi
    # whiptail is guaranteed present by ensure_whiptail bootstrap at script start
    TUI_TOOL="whiptail"
    load_selections_cache
    local choice
    choice=$(tui_menu_full_or_custom) || { echo "Aborted."; exit 0; }
    if [[ "$choice" != "2" ]]; then
        rm -f "$SELECTIONS_CACHE"
        SELECTED_EMULATORS=()
        SELECTED_CORES=()
        return 0
    fi
    local args=() entry key desc state selections
    for entry in "${EMULATOR_CHECKLIST[@]}"; do
        key="${entry%%|*}"; desc="${entry#*|}"
        state="ON"
        [[ "${SELECTED_EMULATORS[$key]:-1}" == "0" ]] && state="OFF"
        args+=("$key" "$desc" "$state")
    done
    selections=$(tui_checklist "Standalone Emulators" "Custom — Screen 1 of 2" "${args[@]}") \
        || { echo "Aborted."; exit 0; }
    SELECTED_EMULATORS=()
    for entry in "${EMULATOR_CHECKLIST[@]}"; do SELECTED_EMULATORS["${entry%%|*}"]=0; done
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        SELECTED_EMULATORS["$key"]=1
    done <<< "$selections"

    # If RetroArch was deselected, no libretro cores can run — skip core picker entirely
    if [[ "${SELECTED_EMULATORS[retroarch]:-0}" != "1" ]]; then
        SELECTED_CORES=()
        for entry in "${CORE_CHECKLIST[@]}"; do
            key="${entry%%|*}"
            [[ -n "${IS_SECTION_HEADER[$key]:-}" ]] && continue
            SELECTED_CORES["$key"]=0
        done
        wt_msg "RetroArch deselected" \
"RetroArch was not selected on the previous screen.

Skipping the libretro cores picker — no cores will be installed (they all require RetroArch to run)."
        save_selections_cache
        return 0
    fi

    args=()
    for entry in "${CORE_CHECKLIST[@]}"; do
        key="${entry%%|*}"; desc="${entry#*|}"
        if [[ -n "${IS_SECTION_HEADER[$key]:-}" ]]; then
            args+=("$key" "$desc" "OFF")
        else
            state="ON"
            [[ "${SELECTED_CORES[$key]:-1}" == "0" ]] && state="OFF"
            args+=("$key" "$desc" "$state")
        fi
    done
    selections=$(tui_checklist "RetroArch Libretro Cores" "Custom — Screen 2 of 2 — ↑/↓ to scroll, SPACE to toggle" "${args[@]}") \
        || { echo "Aborted."; exit 0; }
    SELECTED_CORES=()
    for entry in "${CORE_CHECKLIST[@]}"; do
        key="${entry%%|*}"
        [[ -n "${IS_SECTION_HEADER[$key]:-}" ]] && continue
        SELECTED_CORES["$key"]=0
    done
    while IFS= read -r key; do
        [[ -z "$key" || -n "${IS_SECTION_HEADER[$key]:-}" ]] && continue
        SELECTED_CORES["$key"]=1
    done <<< "$selections"

    local any_core=0
    for key in "${!SELECTED_CORES[@]}"; do
        [[ "${SELECTED_CORES[$key]}" == "1" ]] && { any_core=1; break; }
    done
    if (( any_core == 1 )) && [[ "${SELECTED_EMULATORS[retroarch]:-1}" == "0" ]]; then
        "$TUI_TOOL" --title "Notice" --msgbox \
            "RetroArch was deselected but libretro cores were kept. Re-enabling RetroArch — cores require it." 10 70
        SELECTED_EMULATORS[retroarch]=1
    fi
    save_selections_cache
    local emu_on=0 core_on=0
    for key in "${!SELECTED_EMULATORS[@]}"; do
        [[ "${SELECTED_EMULATORS[$key]}" == "1" ]] && emu_on=$((emu_on + 1))
    done
    for key in "${!SELECTED_CORES[@]}"; do
        [[ "${SELECTED_CORES[$key]}" == "1" ]] && core_on=$((core_on + 1))
    done
    echo ""
    echo -e "${CYAN}Selection:${NC} $emu_on standalone emulators + $core_on libretro cores."
    echo -e "${CYAN}Cached at:${NC} $SELECTIONS_CACHE (delete to reset)"
    echo ""
}

emu_selected() { [[ "${SELECTED_EMULATORS[$1]:-1}" == "1" ]]; }
core_selected() { [[ "${SELECTED_CORES[$1]:-1}" == "1" ]]; }

tui_select_components

# ── Theme selection (ask upfront so user can walk away during downloads) ──
EXISTING_THEMES=0
if [[ -d "$ESDE_DATA/themes" ]]; then
    EXISTING_THEMES=$(find "$ESDE_DATA/themes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
fi
if ((EXISTING_THEMES > 0)); then
    THEME_NAME=""
    THEME_SKIP_REASON="already installed"
else
    THEME_CHOICE=$(wt_menu "Default Theme" \
"Choose a default theme.

You can always change or add more later via ES-DE's built-in Theme Downloader." \
        "1" "Art Book Next     — Coffee-table-book style, polished" \
        "2" "Carbon            — Classic clean look (RetroPie heritage)" \
        "3" "IISU Interpreted  — Clean port of the upcoming iiSU UI" \
        "4" "Linear            — ES-DE built-in, no download" \
        "5" "Meringue          — Soft, light pastel theme" \
        "6" "Slick Remixed     — Refined Slick remake (Weestuarty)") || THEME_CHOICE="1"
    THEME_CHOICE="${THEME_CHOICE:-1}"

    case "$THEME_CHOICE" in
        1|*)
            THEME_NAME="art-book-next-es-de"
            THEME_REPO="https://github.com/anthonycaccese/art-book-next-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="Art Book Next"
            THEME_ZIPDIR="art-book-next-es-de-main"
            ;;
        2)
            THEME_NAME="carbon-es-de"
            THEME_REPO="https://github.com/lilbud/carbon-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="Carbon"
            THEME_ZIPDIR="carbon-es-de-main"
            ;;
        3)
            THEME_NAME="iisu-interpreted-es-de"
            THEME_REPO="https://github.com/VictorUnlocked/iisu-interpreted-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="IISU Interpreted"
            THEME_ZIPDIR="iisu-interpreted-es-de-main"
            ;;
        4)
            # Linear is ES-DE's built-in default theme — no download needed
            THEME_NAME=""
            THEME_LABEL="Linear (ES-DE default, built-in)"
            ;;
        5)
            THEME_NAME="meringue-es-de"
            THEME_REPO="https://github.com/kthod861/meringue-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="Meringue"
            THEME_ZIPDIR="meringue-es-de-main"
            ;;
        6)
            # Weestuarty's slick-es-de is the maintained "Slick Remixed" port
            THEME_NAME="slick-es-de"
            THEME_REPO="https://github.com/Weestuarty/slick-es-de/archive/refs/heads/main.zip"
            THEME_LABEL="Slick Remixed"
            THEME_ZIPDIR="slick-es-de-main"
            ;;
    esac
    echo ""
fi

# ── RetroBat import prompt ──
RETROBAT_PATHS=()
RETROBAT_REAL_PATHS=()
RETROBAT_SYNTH_DIRS=()
echo "Import existing RetroBat collection(s)?"
echo "  Accepts either a full RetroBat folder (containing a 'roms' subfolder)"
echo "  or a standalone ROM pack folder (e.g. a single system folder like 'dreamcast/')."
echo "  You can add as many as you like. Leave blank when done."
echo ""

while true; do
    [[ ${#RETROBAT_PATHS[@]} -eq 0 ]] && PROMPT_LABEL="Path" || PROMPT_LABEL="Another path"
    RETROBAT_INPUT=$(wt_input "Import RetroBat / ROM Pack" \
"$PROMPT_LABEL to import (leave blank to continue past this prompt).

Accepts either:
 • a full RetroBat folder (containing 'roms' subfolder)
 • a standalone ROM pack folder (e.g. a single system folder like 'dreamcast/')

You can add as many paths as you like, one at a time." \
        "") || RETROBAT_INPUT=""

    [[ -z "$RETROBAT_INPUT" ]] && break

    RETROBAT_INPUT="${RETROBAT_INPUT/#\~/$HOME}"
    RETROBAT_INPUT="$(realpath -m "$RETROBAT_INPUT")"

    if [[ ! -d "$RETROBAT_INPUT" ]]; then
        wt_msg "Path not found" "Directory not found:\n\n$RETROBAT_INPUT\n\nSkipping this entry."
    elif [[ -d "$RETROBAT_INPUT/roms" ]]; then
        # Full RetroBat install — roms subfolder exists
        RETROBAT_PATHS+=("$RETROBAT_INPUT")
        RETROBAT_REAL_PATHS+=("$RETROBAT_INPUT")
        echo -e "   ${GREEN}✓${NC} Added (full RetroBat install): $RETROBAT_INPUT"
    else
        # Standalone folder — could be a collection (contains system subdirs)
        # or a single system folder (IS the system dir itself)
        SUBDIR_COUNT=$(find "$RETROBAT_INPUT" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        SYNTH_PARENT=$(mktemp -d)
        if [[ $SUBDIR_COUNT -gt 0 ]]; then
            # Has subdirectories — treat as collection, wrap normally
            ln -s "$RETROBAT_INPUT" "$SYNTH_PARENT/roms"
            echo -e "   ${GREEN}✓${NC} Added (ROM collection folder): $RETROBAT_INPUT"
        else
            # No subdirectories — this IS a system folder, infer system name from dirname
            SYS_NAME=$(basename "$RETROBAT_INPUT")
            mkdir -p "$SYNTH_PARENT/roms/$SYS_NAME"
            # Symlink contents into a named system subfolder
            while IFS= read -r -d '' ITEM; do
                ln -s "$ITEM" "$SYNTH_PARENT/roms/$SYS_NAME/$(basename "$ITEM")" 2>/dev/null || true
            done < <(find "$RETROBAT_INPUT" -maxdepth 1 -mindepth 1 -print0)
            echo -e "   ${GREEN}✓${NC} Added (single system folder '$SYS_NAME'): $RETROBAT_INPUT"
        fi
        RETROBAT_PATHS+=("$SYNTH_PARENT")
        RETROBAT_REAL_PATHS+=("$RETROBAT_INPUT")
        RETROBAT_SYNTH_DIRS+=("$SYNTH_PARENT")
    fi
done

if [[ ${#RETROBAT_PATHS[@]} -gt 0 ]]; then
    # ── Cut or copy? ──
    RETROBAT_MOVE=""
    MOVE_CHOICE=$(wt_menu "Transfer mode" \
"How should files be transferred from the source(s) to the bundle?" \
        "copy" "Keep originals (safe, uses extra disk space)" \
        "cut"  "Move files as they're imported (no extra space needed)") || MOVE_CHOICE="copy"
    [[ "$MOVE_CHOICE" == "cut" ]] && RETROBAT_MOVE="yes"
    [[ "$RETROBAT_MOVE" == "yes" ]] \
        && echo -e "   ${GREEN}✓${NC} Cut mode — files will be moved, not copied" \
        || echo -e "   ${GREEN}✓${NC} Copy mode — originals will be kept"
    echo ""
fi
echo ""

# ── Internal resolution ──
RES_CHOICE=$(wt_menu "Emulator Internal Resolution" \
"Upscales the rendered image for N64, GameCube/Wii, PS1, PS2, and Wii U.

Higher = sharper but needs more GPU power." \
    "1" "Native    — original hardware resolution (fastest)" \
    "2" "1080p     — good for mid-range GPUs" \
    "3" "1440p/2K  — recommended for modern GPUs (default)" \
    "4" "4K        — very powerful GPU required") || RES_CHOICE="3"
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
if wt_yesno "Desktop Shortcut" \
"Create a desktop shortcut for ES-DE in your applications menu?

The shortcut will launch the portable ES-DE installed in this bundle."; then
    CREATE_SHORTCUT="yes"
fi
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
        [dosbox_pure]="DOS (fallback)"
        [cap32]="Amstrad CPC"
        [quasi88]="PC-88 (alt)"

        # MAME — two versions because BIOS romsets are MAME-version-locked.
        # Only mame, mame2003_plus, and mame2010 exist on the libretro buildbot
        # for Linux x86_64 (mame2014/2015/2016 were dropped or never built).
        # current MAME = the modern default, used as the primary command for
        # all systems below. mame2010 = MAME 0.139, deeper fallback for very
        # old BIOS packs (selectable via ES-DE's alt-emu menu).
        [mame]="MAME (Archimedes/ADAM/Dragon32/FM7/TI99/Model2/LCD/G&W/Gamate/PV1000/SCV/SuperACan/GameMaster/Game.com/VSmile)"
        [mame2010]="MAME 2010 (MAME 0.139 — deeper BIOS fallback)"

        # Nintendo
        [mesen]="NES / Famicom (high accuracy)"
        [mesen-s]="Super Game Boy (Mesen-S)"
        [gw]="Game & Watch (alt to MAME)"

        # Sega
        [kronos]="Saturn / Saturn JP (high accuracy)"

        # Sony
        [mednafen_psx]="PS1 (high accuracy)"
        [mednafen_psx_hw]="PS1 HW renderer"
        [mednafen_supergrafx]="NEC SuperGrafx"

        # NEC
        [np2kai]="PC-9800"

        # Sharp
        [x1]="Sharp X1"
        [px68k]="Sharp X68000"

        # Commodore
        [vice_x64sc]="C64 (high accuracy, replaces vice_x64)"
        [vice_xplus4]="Commodore Plus/4"

        # Misc missing cores
        [arduous]="Arduboy"
        [atari800]="Atari 800 / 5200 / XEGS"
        [bluemsx]="MSX / MSX2 / Turbo R / Spectravideo / Colecovision"
        [sameduck]="Mega Duck"
        [easyrpg]="EasyRPG"
        [amiarcadia]="Arcadia 2001"
        [lowresnx]="LowRes NX"
        [lutro]="Lutro"
        [neocd]="Neo Geo CD"
        [tic80]="TIC-80"
        [jollycv]="Creativision"
        [wasm4]="WASM-4"
        [potator]="Watara Supervision"
        [b2]="BBC Micro / BBC Master"
        [retro8]="PICO-8 (retro8 - free PICO-8-compatible core)"
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
        if ! core_selected "$core_name"; then
            skipped=$((skipped + 1))
            continue
        fi
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
TOTAL_STEPS=21

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
    atarijaguar atarijaguarcd atarilynx atarist c64 channelf colecovision
    cps1 cps2 cps3 daphne dos dreamcast famicom fds gamegear
    gb gba gbc gc genesis intellivision mastersystem megacd megadrive
    msx msx2 n3ds n64 nds neogeo neogeocd nes ngp ngpc odyssey2
    pc pcengine pcenginecd pcfx pico8 pokemini ports ps2 ps3
    psp psx saturn sc-3000 scummvm sega32x segacd sg-1000 snes
    supergrafx switch tg-cd tg16 ti99 uzebox vectrex vic20 videopac
    virtualboy wii wiiu wonderswan wonderswancolor x68000
    xbox xbox360 zmachine zx81 zxspectrum
    triforce j2me openbor pcarcade type-x
    ps4 windows9x windows3x
    sfc n64dd wiiware megadrivejp saturnjp amiga500 amiga1200 videopacplus vpinball
    archimedes adam dragon32 fm7 supracan bbcmicro apple2 fbneo
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
emu('RYUBING', [fp('Ryubing*.AppImage'), fp('ryubing*.AppImage'), fp('ryujinx*.AppImage')], ['Ryubing']),
'',
emu('EDEN', [fp('Eden*.AppImage'), fp('eden*.AppImage')], ['eden']),
'',
emu('SHADPS4',
    [fp('shadps4-portable.sh'), fp('shadps4')],
    ['shadps4']),
'',
emu('86BOX',
    [fp('86box-portable.sh'), fp('86Box*.AppImage'), fp('86box*.AppImage')],
    ['86Box', '86box']),
'',
# 3dSen is a commercial app (buy on Steam/itch.io) — find rules for if user has it
emu('3DSEN',
    [fp('3dSen*.AppImage'), '~/.local/share/Steam/steamapps/common/3dSen/3dSen',
     '~/.local/share/applications/3dSen'],
    ['3dSen']),
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
# MESEN: handled via mesen_libretro core in RetroArch — no standalone needed
'',
emu('DOSBOX_X', [fp('dosbox-x-portable.sh'), fp('dosbox-x*.AppImage'), fp('dosbox-x')], ['dosbox-x']),
'',
emu('SIMCOUPE', [fp('simcoupe-portable.sh'), fp('SimCoupe*.AppImage'), fp('simcoupe')], ['simcoupe', 'SimCoupe']),
'',
emu('SUPERMODEL', [fp('supermodel-portable.sh'), fp('supermodel*.AppImage'), fp('Supermodel*.AppImage'), fp('supermodel')], ['supermodel']),
'',
emu('SOLARUS', [fp('solarus-run*.AppImage'), fp('solarus-portable.sh'), fp('solarus-run')], ['solarus-run']),
'',
emu('RUFFLE', [fp('ruffle-portable.sh'), fp('ruffle*.AppImage'), fp('ruffle')], ['ruffle']),
'',
emu('EKA2L1', [fp('eka2l1-portable.sh'), fp('eka2l1*.AppImage'), fp('eka2l1')], ['eka2l1']),
'',
emu('VPINBALL',
    [fp('vpinball-portable.sh'), fp('VPinballX_BGFX'), fp('VPinballX_GL')],
    ['vpinball-portable.sh', 'VPinballX_BGFX', 'VPinballX_GL']),
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


  <system>
    <name>ps3</name>
    <fullname>Sony PlayStation 3</fullname>
    <path>%ROMPATH%/ps3</path>
    <extension>.squashfs .SQUASHFS .psn .PSN .pkg .PKG .iso .ISO .zip .ZIP</extension>
    <command label="RPCS3">%EMULATOR_RPCS3% %ROM%</command>
    <platform>ps3</platform>
    <theme>ps3</theme>
  </system>

  <system>
    <name>ps3psn</name>
    <fullname>PlayStation 3 (PSN / Digital)</fullname>
    <path>%ROMPATH%/ps3psn</path>
    <extension>.lnk .LNK .pkg .PKG .psn .PSN .rap .RAP</extension>
    <command label="RPCS3">%EMULATOR_RPCS3% %ROM%</command>
    <platform>ps3</platform>
    <theme>ps3</theme>
  </system>

  <system>
    <name>ps4</name>
    <fullname>Sony PlayStation 4</fullname>
    <path>%ROMPATH%/ps4</path>
    <extension>.7z .7Z .pkg .PKG .iso .ISO</extension>
    <command label="shadPS4">%EMULATOR_SHADPS4% %ROM%</command>
    <platform>ps4</platform>
    <theme>ps4</theme>
  </system>

  <system>
    <name>xbox360</name>
    <fullname>Microsoft Xbox 360</fullname>
    <path>%ROMPATH%/xbox360</path>
    <extension>.xbox360 .XBOX360 .squashfs .SQUASHFS .m3u .M3U .iso .ISO .xex .XEX .zip .ZIP</extension>
    <command label="Xenia Canary">%EMULATOR_XENIA% %ROM%</command>
    <platform>xbox360</platform>
    <theme>xbox360</theme>
  </system>

  <system>
    <name>xbla</name>
    <fullname>Xbox Live Arcade</fullname>
    <path>%ROMPATH%/xbla</path>
    <extension>.xbox360 .XBOX360 .xex .XEX .iso .ISO .xcp .XCP .zip .ZIP .squashfs .SQUASHFS</extension>
    <command label="Xenia Canary">%EMULATOR_XENIA% %ROM%</command>
    <platform>xbox360</platform>
    <theme>xbox360</theme>
  </system>

  <system>
    <name>sfc</name>
    <fullname>Super Famicom</fullname>
    <path>%ROMPATH%/sfc</path>
    <extension>.sfc .smc .fig .swc .bs .st .zip .7z .SFC .SMC .ZIP .7Z</extension>
    <command label="Snes9x">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/snes9x_libretro.so %ROM%</command>
    <platform>snes</platform>
    <theme>sfc</theme>
  </system>

  <system>
    <name>n64dd</name>
    <fullname>Nintendo 64DD</fullname>
    <path>%ROMPATH%/n64dd</path>
    <extension>.ndd .zip .7z .NDD .ZIP .7Z</extension>
    <command label="Mupen64Plus-Next">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mupen64plus_next_libretro.so %ROM%</command>
    <platform>n64</platform>
    <theme>n64dd</theme>
  </system>

  <system>
    <name>wiiware</name>
    <fullname>WiiWare</fullname>
    <path>%ROMPATH%/wiiware</path>
    <extension>.wad .WAD .zip .ZIP</extension>
    <command label="Dolphin">%EMULATOR_DOLPHIN% %ROM%</command>
    <platform>wii</platform>
    <theme>wii</theme>
  </system>

  <system>
    <name>megadrivejp</name>
    <fullname>Sega Mega Drive (Japan)</fullname>
    <path>%ROMPATH%/megadrivejp</path>
    <extension>.md .bin .smd .gen .zip .7z .MD .BIN .ZIP .7Z</extension>
    <command label="Genesis Plus GX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/genesis_plus_gx_libretro.so %ROM%</command>
    <platform>megadrive</platform>
    <theme>megadrivejp</theme>
  </system>

  <system>
    <name>saturnjp</name>
    <fullname>Sega Saturn (Japan)</fullname>
    <path>%ROMPATH%/saturnjp</path>
    <extension>.bin .cue .iso .mdf .chd .zip .7z .BIN .CUE .ISO .ZIP .7Z</extension>
    <command label="Kronos">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/kronos_libretro.so %ROM%</command>
    <platform>saturn</platform>
    <theme>saturnjp</theme>
  </system>

  <system>
    <name>amiga500</name>
    <fullname>Commodore Amiga 500</fullname>
    <path>%ROMPATH%/amiga500</path>
    <extension>.adf .adz .dms .fdi .ipf .hdf .hdz .lha .zip .7z .ADF .ZIP .7Z</extension>
    <command label="PUAE">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/puae_libretro.so %ROM%</command>
    <platform>amiga</platform>
    <theme>amiga</theme>
  </system>

  <system>
    <name>amiga1200</name>
    <fullname>Commodore Amiga 1200</fullname>
    <path>%ROMPATH%/amiga1200</path>
    <extension>.adf .adz .dms .fdi .ipf .hdf .hdz .lha .zip .7z .ADF .ZIP .7Z</extension>
    <command label="PUAE">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/puae_libretro.so %ROM%</command>
    <platform>amiga</platform>
    <theme>amiga1200</theme>
  </system>

  <system>
    <name>videopacplus</name>
    <fullname>Philips Videopac+ G7400</fullname>
    <path>%ROMPATH%/videopacplus</path>
    <extension>.bin .zip .7z .BIN .ZIP .7Z</extension>
    <command label="O2EM">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/o2em_libretro.so %ROM%</command>
    <platform>videopac</platform>
    <theme>videopac</theme>
  </system>

  <system>
    <name>vpinball</name>
    <fullname>Visual Pinball</fullname>
    <path>%ROMPATH%/vpinball</path>
    <extension>.vpx .VPX</extension>
    <command label="VPinballX">%EMULATOR_VPINBALL% -play %ROM%</command>
    <platform>vpinball</platform>
    <theme>vpinball</theme>
  </system>


  <!-- Built-in system overrides — portable emulators/cores take priority -->

  <system>
    <name>nes</name>
    <fullname>Nintendo Entertainment System</fullname>
    <path>%ROMPATH%/nes</path>
    <extension>.nes .unf .unif .fds .zip .7z .NES .ZIP .7Z</extension>
    <command label="Mesen">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mesen_libretro.so %ROM%</command>
    <command label="FCEUmm">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fceumm_libretro.so %ROM%</command>
    <platform>nes</platform>
    <theme>nes</theme>
  </system>

  <system>
    <name>famicom</name>
    <fullname>Nintendo Famicom</fullname>
    <path>%ROMPATH%/famicom</path>
    <extension>.nes .unf .unif .fds .zip .7z .NES .ZIP .7Z</extension>
    <command label="Mesen">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mesen_libretro.so %ROM%</command>
    <command label="FCEUmm">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fceumm_libretro.so %ROM%</command>
    <platform>nes</platform>
    <theme>famicom</theme>
  </system>

  <system>
    <name>gc</name>
    <fullname>Nintendo GameCube</fullname>
    <path>%ROMPATH%/gc</path>
    <extension>.iso .ISO .gcm .GCM .gcz .GCZ .chd .CHD .rvz .RVZ .wbfs .WBFS .ciso .CISO .zip .ZIP</extension>
    <command label="Dolphin">%EMULATOR_DOLPHIN% %ROM%</command>
    <platform>gc</platform>
    <theme>gc</theme>
  </system>

  <system>
    <name>wii</name>
    <fullname>Nintendo Wii</fullname>
    <path>%ROMPATH%/wii</path>
    <extension>.iso .ISO .gcm .GCM .gcz .GCZ .chd .CHD .rvz .RVZ .wbfs .WBFS .ciso .CISO .wad .WAD .zip .ZIP</extension>
    <command label="Dolphin">%EMULATOR_DOLPHIN% %ROM%</command>
    <platform>wii</platform>
    <theme>wii</theme>
  </system>

  <system>
    <name>nds</name>
    <fullname>Nintendo DS</fullname>
    <path>%ROMPATH%/nds</path>
    <extension>.nds .NDS .zip .ZIP .7z .7Z</extension>
    <command label="melonDS">%EMULATOR_MELONDS% %ROM%</command>
    <platform>nds</platform>
    <theme>nds</theme>
  </system>

  <system>
    <name>ps2</name>
    <fullname>Sony PlayStation 2</fullname>
    <path>%ROMPATH%/ps2</path>
    <extension>.iso .ISO .bin .BIN .chd .CHD .cso .CSO .mdf .MDF .gz .GZ .img .IMG .zip .ZIP</extension>
    <command label="PCSX2">%EMULATOR_PCSX2% %ROM%</command>
    <platform>ps2</platform>
    <theme>ps2</theme>
  </system>

  <system>
    <name>psx</name>
    <fullname>Sony PlayStation</fullname>
    <path>%ROMPATH%/psx</path>
    <extension>.bin .BIN .cue .CUE .iso .ISO .img .IMG .chd .CHD .pbp .PBP .toc .TOC .mdf .MDF .m3u .M3U .zip .ZIP</extension>
    <command label="DuckStation">%EMULATOR_DUCKSTATION% %ROM%</command>
    <command label="Mednafen PSX HW">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mednafen_psx_hw_libretro.so %ROM%</command>
    <command label="Mednafen PSX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mednafen_psx_libretro.so %ROM%</command>
    <platform>psx</platform>
    <theme>psx</theme>
  </system>

  <system>
    <name>dos</name>
    <fullname>DOS</fullname>
    <path>%ROMPATH%/dos</path>
    <extension>.exe .EXE .com .COM .bat .BAT .conf .CONF .zip .ZIP</extension>
    <command label="DOSBox-X">%EMULATOR_DOSBOX_X% %ROM%</command>
    <command label="DOSBox Pure">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/dosbox_pure_libretro.so %ROM%</command>
    <platform>dos</platform>
    <theme>dos</theme>
  </system>

  <system>
    <name>win98</name>
    <fullname>Microsoft Windows 9x</fullname>
    <path>%ROMPATH%/win98</path>
    <extension>.exe .EXE .bat .BAT .conf .CONF .zip .ZIP</extension>
    <command label="86Box">%EMULATOR_86BOX% %ROM%</command>
    <platform>pc</platform>
    <theme>win98</theme>
  </system>

  <system>
    <name>windows</name>
    <fullname>Microsoft Windows</fullname>
    <path>%ROMPATH%/windows</path>
    <extension>.exe .EXE .bat .BAT .lnk .LNK .zip .ZIP</extension>
    <command label="86Box">%EMULATOR_86BOX% %ROM%</command>
    <platform>pc</platform>
    <theme>windows</theme>
  </system>

  <system>
    <name>samcoupe</name>
    <fullname>MGT SAM Coupé</fullname>
    <path>%ROMPATH%/samcoupe</path>
    <extension>.mgt .MGT .sad .SAD .dsk .DSK .sdf .SDF .zip .ZIP</extension>
    <command label="SimCoupe">%EMULATOR_SIMCOUPE% %ROM%</command>
    <platform>samcoupe</platform>
    <theme>samcoupe</theme>
  </system>

  <system>
    <name>cps1</name>
    <fullname>Capcom Play System I</fullname>
    <path>%ROMPATH%/cps1</path><extension>.zip .ZIP .7z .7Z</extension>
    <command label="FBNeo">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fbneo_libretro.so %ROM%</command>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so %ROM%</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so %ROM%</command>
    <platform>arcade</platform>
    <theme>cps1</theme>
  </system>

  <system>
    <name>cps2</name>
    <fullname>Capcom Play System II</fullname>
    <path>%ROMPATH%/cps2</path><extension>.zip .ZIP .7z .7Z</extension>
    <command label="FBNeo">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fbneo_libretro.so %ROM%</command>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so %ROM%</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so %ROM%</command>
    <platform>arcade</platform>
    <theme>cps2</theme>
  </system>

  <system>
    <name>cps3</name>
    <fullname>Capcom Play System III</fullname>
    <path>%ROMPATH%/cps3</path><extension>.zip .ZIP .7z .7Z</extension>
    <command label="FBNeo">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fbneo_libretro.so %ROM%</command>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so %ROM%</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so %ROM%</command>
    <platform>arcade</platform>
    <theme>cps3</theme>
  </system>

  <system>
    <name>atomiswave</name>
    <fullname>Sammy Atomiswave</fullname>
    <path>%ROMPATH%/atomiswave</path><extension>.zip .ZIP .7z .7Z .chd .CHD</extension>
    <command label="Flycast">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/flycast_libretro.so %ROM%</command>
    <platform>arcade</platform>
    <theme>atomiswave</theme>
  </system>

  <system>
    <name>naomi</name>
    <fullname>Sega NAOMI</fullname>
    <path>%ROMPATH%/naomi</path><extension>.zip .ZIP .7z .7Z .chd .CHD</extension>
    <command label="Flycast">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/flycast_libretro.so %ROM%</command>
    <platform>arcade</platform>
    <theme>naomi</theme>
  </system>

  <system>
    <name>naomi2</name>
    <fullname>Sega NAOMI 2</fullname>
    <path>%ROMPATH%/naomi2</path><extension>.zip .ZIP .7z .7Z .chd .CHD</extension>
    <command label="Flycast">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/flycast_libretro.so %ROM%</command>
    <platform>arcade</platform>
    <theme>naomi2</theme>
  </system>

  <system>
    <name>model2</name>
    <fullname>Sega Model 2</fullname>
    <path>%ROMPATH%/model2</path>
    <extension>.zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "%BASENAME% -rompath \"%GAMEDIRRAW%;%ROMPATH%/model2;%ROMPATH%/bios\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "%BASENAME% -rompath \"%GAMEDIRRAW%;%ROMPATH%/model2;%ROMPATH%/bios\""</command>
    <platform>arcade</platform>
    <theme>model2</theme>
  </system>

  <system>
    <name>model3</name>
    <fullname>Sega Model 3</fullname>
    <path>%ROMPATH%/model3</path><extension>.zip .ZIP .7z .7Z</extension>
    <command label="Supermodel">%EMULATOR_SUPERMODEL% -fullscreen %ROM%</command>
    <platform>arcade</platform>
    <theme>model3</theme>
  </system>

  <system>
    <name>flash</name>
    <fullname>Adobe Flash</fullname>
    <path>%ROMPATH%/flash</path><extension>.swf .SWF .zip .ZIP</extension>
    <command label="Ruffle">%EMULATOR_RUFFLE% %ROM%</command>
    <platform>flash</platform>
    <theme>flash</theme>
  </system>

  <system>
    <name>pico8</name>
    <fullname>PICO-8</fullname>
    <path>%ROMPATH%/pico8</path><extension>.png .PNG .p8 .P8</extension>
    <command label="retro8">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/retro8_libretro.so %ROM%</command>
    <command label="fake-08">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fake08_libretro.so %ROM%</command>
    <platform>pico8</platform>
    <theme>pico8</theme>
  </system>

  <system>
    <name>solarus</name>
    <fullname>Solarus</fullname>
    <path>%ROMPATH%/solarus</path><extension>.solarus .SOLARUS .zip .ZIP</extension>
    <command label="Solarus">%EMULATOR_SOLARUS% %ROM%</command>
    <platform>solarus</platform>
    <theme>solarus</theme>
  </system>

  <system>
    <name>neogeocd</name>
    <fullname>SNK Neo Geo CD</fullname>
    <path>%ROMPATH%/neogeocd</path>
    <extension>.chd .CHD .cue .CUE .iso .ISO .zip .ZIP</extension>
    <command label="NeoCD">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/neocd_libretro.so %ROM%</command>
    <command label="FBNeo">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fbneo_libretro.so %ROM%</command>
    <platform>neogeocd</platform>
    <theme>neogeocd</theme>
  </system>

  <system>
    <name>supergrafx</name>
    <fullname>NEC SuperGrafx</fullname>
    <path>%ROMPATH%/supergrafx</path>
    <extension>.pce .PCE .sgx .SGX .zip .ZIP .7z .7Z</extension>
    <command label="Mednafen SuperGrafx">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mednafen_supergrafx_libretro.so %ROM%</command>
    <command label="Mednafen PCE">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mednafen_pce_libretro.so %ROM%</command>
    <platform>pcengine</platform>
    <theme>supergrafx</theme>
  </system>

  <system>
    <name>sgb</name>
    <fullname>Nintendo Super Game Boy</fullname>
    <path>%ROMPATH%/sgb</path>
    <extension>.gb .GB .gbc .GBC .zip .ZIP .7z .7Z</extension>
    <command label="Mesen-S">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mesen-s_libretro.so %ROM%</command>
    <platform>gb</platform>
    <theme>sgb</theme>
  </system>

  <system>
    <name>spectravideo</name>
    <fullname>Spectravideo</fullname>
    <path>%ROMPATH%/spectravideo</path>
    <extension>.rom .ROM .cas .CAS .zip .ZIP .7z .7Z</extension>
    <command label="blueMSX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/bluemsx_libretro.so %ROM%</command>
    <platform>spectravideo</platform>
    <theme>spectravideo</theme>
  </system>

  <system>
    <name>colecovision</name>
    <fullname>ColecoVision</fullname>
    <path>%ROMPATH%/colecovision</path>
    <extension>.col .COL .rom .ROM .zip .ZIP .7z .7Z</extension>
    <command label="blueMSX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/bluemsx_libretro.so %ROM%</command>
    <platform>colecovision</platform>
    <theme>colecovision</theme>
  </system>

  <system>
    <name>ti99</name>
    <fullname>Texas Instruments TI-99/4A</fullname>
    <path>%ROMPATH%/ti99</path>
    <extension>.rpk .RPK .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "ti99_4a -rompath \"%GAMEDIRRAW%;%ROMPATH%/ti99;%ROMPATH%/bios\" -ioport peb -ioport:peb:slot8 speechadapter -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "ti99_4a -rompath \"%GAMEDIRRAW%;%ROMPATH%/ti99;%ROMPATH%/bios\" -ioport peb -ioport:peb:slot8 speechadapter -cart \"%ROMRAW%\""</command>
    <command label="MAME [Software list]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "ti99_4a -rompath \"%GAMEDIRRAW%;%ROMPATH%/ti99;%ROMPATH%/bios\" -ioport peb -ioport:peb:slot8 speechadapter %BASENAME%"</command>
    <command label="MAME [Software list] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "ti99_4a -rompath \"%GAMEDIRRAW%;%ROMPATH%/ti99;%ROMPATH%/bios\" -ioport peb -ioport:peb:slot8 speechadapter %BASENAME%"</command>
    <platform>ti99</platform>
    <theme>ti99</theme>
  </system>

  <system>
    <name>msx</name>
    <fullname>MSX</fullname>
    <path>%ROMPATH%/msx</path>
    <extension>.rom .ROM .mx1 .MX1 .cas .CAS .dsk .DSK .zip .ZIP .7z .7Z</extension>
    <command label="blueMSX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/bluemsx_libretro.so %ROM%</command>
    <platform>msx</platform>
    <theme>msx</theme>
  </system>

  <system>
    <name>msx2</name>
    <fullname>MSX2</fullname>
    <path>%ROMPATH%/msx2</path>
    <extension>.rom .ROM .mx2 .MX2 .cas .CAS .dsk .DSK .zip .ZIP .7z .7Z</extension>
    <command label="blueMSX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/bluemsx_libretro.so %ROM%</command>
    <platform>msx</platform>
    <theme>msx2</theme>
  </system>

  <system>
    <name>msxturbor</name>
    <fullname>MSX Turbo R</fullname>
    <path>%ROMPATH%/msxturbor</path>
    <extension>.rom .ROM .cas .CAS .dsk .DSK .zip .ZIP .7z .7Z</extension>
    <command label="blueMSX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/bluemsx_libretro.so %ROM%</command>
    <platform>msx</platform>
    <theme>msx</theme>
  </system>

  <system>
    <name>c64</name>
    <fullname>Commodore 64</fullname>
    <path>%ROMPATH%/c64</path>
    <extension>.d64 .D64 .t64 .T64 .g64 .G64 .prg .PRG .crt .CRT .tap .TAP .x64 .X64 .zip .ZIP .7z .7Z</extension>
    <command label="VICE x64sc">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/vice_x64sc_libretro.so %ROM%</command>
    <command label="VICE x64">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/vice_x64_libretro.so %ROM%</command>
    <platform>c64</platform>
    <theme>c64</theme>
  </system>

  <system>
    <name>plus4</name>
    <fullname>Commodore Plus/4</fullname>
    <path>%ROMPATH%/plus4</path>
    <extension>.d64 .D64 .t64 .T64 .prg .PRG .tap .TAP .zip .ZIP .7z .7Z</extension>
    <command label="VICE xplus4">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/vice_xplus4_libretro.so %ROM%</command>
    <platform>c64</platform>
    <theme>plus4</theme>
  </system>

  <system>
    <name>x68000</name>
    <fullname>Sharp X68000</fullname>
    <path>%ROMPATH%/x68000</path>
    <extension>.dim .DIM .img .IMG .d88 .D88 .88d .88D .hdm .HDM .xdf .XDF .hdf .HDF .zip .ZIP .7z .7Z</extension>
    <command label="PX68k">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/px68k_libretro.so %ROM%</command>
    <platform>x68000</platform>
    <theme>x68000</theme>
  </system>

  <system>
    <name>x1</name>
    <fullname>Sharp X1</fullname>
    <path>%ROMPATH%/x1</path>
    <extension>.dx1 .DX1 .zip .ZIP .2d .2D .2hd .2HD .tfd .TFD .d88 .D88 .88d .88D .hdm .HDM .xdf .XDF .hdf .HDF .cmd .CMD</extension>
    <command label="X1">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/x1_libretro.so %ROM%</command>
    <platform>x1</platform>
    <theme>x1</theme>
  </system>

  <system>
    <name>pc98</name>
    <fullname>NEC PC-9800</fullname>
    <path>%ROMPATH%/pc98</path>
    <extension>.d98 .D98 .zip .ZIP .fdi .FDI .fdd .FDD .2hd .2HD .tfd .TFD .d88 .D88 .88d .88D .hdm .HDM .xdf .XDF .hdf .HDF .hdi .HDI .nhd .NHD .hdd .HDD</extension>
    <command label="Neko Project II kai">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/np2kai_libretro.so %ROM%</command>
    <platform>pc98</platform>
    <theme>pc98</theme>
  </system>

  <system>
    <name>megadrive</name>
    <fullname>Sega Mega Drive</fullname>
    <path>%ROMPATH%/megadrive</path>
    <extension>.md .MD .bin .BIN .smd .SMD .gen .GEN .68k .68K .chd .CHD .zip .ZIP .7z .7Z</extension>
    <command label="Genesis Plus GX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/genesis_plus_gx_libretro.so %ROM%</command>
    <command label="PicoDrive">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/picodrive_libretro.so %ROM%</command>
    <platform>megadrive</platform>
    <theme>megadrive</theme>
  </system>

  <system>
    <name>snes</name>
    <fullname>Super Nintendo Entertainment System</fullname>
    <path>%ROMPATH%/snes</path>
    <extension>.sfc .SFC .smc .SMC .fig .FIG .swc .SWC .bs .BS .st .ST .zip .ZIP .7z .7Z</extension>
    <command label="Snes9x">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/snes9x_libretro.so %ROM%</command>
    <platform>snes</platform>
    <theme>snes</theme>
  </system>

  <!-- ── MAME-only systems routed through mame_libretro core ──
       ES-DE 3.4.1 still defaults these to standalone MAME (%EMULATOR_MAME%),
       but this bundle ships mame_libretro.so as a RetroArch core, not
       standalone MAME. Without these overrides, launching a game from any
       of these systems fails with "Couldn't launch game, emulator not found".
       Each system needs its specific MAME machine name and media flag —
       a generic "-L mame_libretro.so %ROM%" won't work because mame_libretro
       behaves like standalone MAME and requires the machine + flop/cart args.
       Format follows ES-DE's own libretro MAME entries for pv1000, scv, etc. -->

  <system>
    <name>archimedes</name>
    <fullname>Acorn Archimedes</fullname>
    <path>%ROMPATH%/archimedes</path>
    <extension>.1dd .1DD .360 .adf .ADF .adl .ADL .adm .ADM .ads .ADS .apd .APD .bbc .BBC .chd .CHD .cqi .CQI .cqm .CQM .d77 .D77 .d88 .D88 .dfi .DFI .dsd .DSD .dsk .DSK .hfe .HFE .ima .IMA .imd .IMD .img .IMG .ipf .IPF .jfd .JFD .mfi .MFI .mfm .MFM .msa .MSA .ssd .SSD .st .ST .td0 .TD0 .ufi .UFI .7z .7Z .zip .ZIP</extension>
    <command label="MAME [Model A440/1]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "aa4401 -rompath \"%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Model A440/1] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "aa4401 -rompath \"%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Model A440/1] (Standalone)">%EMULATOR_MAME% aa4401 -rompath "%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <command label="MAME [Model A3000]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "aa3000 -rompath \"%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Model A3000] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "aa3000 -rompath \"%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Model A3000] (Standalone)">%EMULATOR_MAME% aa3000 -rompath "%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <command label="MAME [Model A310]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "aa310 -rompath \"%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Model A310] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "aa310 -rompath \"%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Model A310] (Standalone)">%EMULATOR_MAME% aa310 -rompath "%GAMEDIRRAW%;%ROMPATH%/archimedes;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <platform>archimedes</platform>
    <theme>archimedes</theme>
  </system>

  <system>
    <name>adam</name>
    <fullname>Coleco Adam</fullname>
    <path>%ROMPATH%/adam</path>
    <extension>.1dd .1DD .bin .BIN .col .COL .cqi .CQI .cqm .CQM .d77 .D77 .d88 .D88 .ddp .DDP .dfi .DFI .dsk .DSK .hfe .HFE .imd .IMD .mfi .MFI .mfm .MFM .rom .ROM .td0 .TD0 .wav .WAV .7z .7Z .zip .ZIP</extension>
    <command label="MAME [Diskette]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "adam -rompath \"%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Diskette] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "adam -rompath \"%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Diskette] (Standalone)">%EMULATOR_MAME% adam -rompath "%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "adam -rompath \"%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios\" -cart1 \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "adam -rompath \"%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios\" -cart1 \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (Standalone)">%EMULATOR_MAME% adam -rompath "%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios" -cart1 "%ROMRAW%"</command>
    <command label="MAME [Tape]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "adam -rompath \"%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios\" -cass1 \"%ROMRAW%\""</command>
    <command label="MAME [Tape] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "adam -rompath \"%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios\" -cass1 \"%ROMRAW%\""</command>
    <command label="MAME [Tape] (Standalone)">%EMULATOR_MAME% adam -rompath "%GAMEDIRRAW%;%ROMPATH%/adam;%ROMPATH%/bios" -cass1 "%ROMRAW%"</command>
    <platform>adam</platform>
    <theme>adam</theme>
  </system>

  <system>
    <name>dragon32</name>
    <fullname>Dragon Data Dragon 32</fullname>
    <path>%ROMPATH%/dragon32</path>
    <extension>.bas .BAS .bin .BIN .ccc .CCC .cas .CAS .dmk .DMK .dsk .DSK .fdi .FDI .hfe .HFE .imd .IMD .jvc .JVC .mfi .MFI .os9 .OS9 .rom .ROM .td0 .TD0 .vdk .VDK .wav .WAV .7z .7Z .zip .ZIP</extension>
    <command label="MAME [Dragon 32 Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "dragon32 -rompath \"%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Dragon 32 Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "dragon32 -rompath \"%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Dragon 32 Cartridge] (Standalone)">%EMULATOR_MAME% dragon32 -rompath "%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <command label="MAME [Dragon 32 Tape]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "dragon32 -rompath \"%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios\" -autoboot_delay \"4\" -autoboot_command \"cloadm:exec\\n\" -cass \"%ROMRAW%\""</command>
    <command label="MAME [Dragon 32 Tape] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "dragon32 -rompath \"%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios\" -autoboot_delay \"4\" -autoboot_command \"cloadm:exec\\n\" -cass \"%ROMRAW%\""</command>
    <command label="MAME [Dragon 32 Tape] (Standalone)">%EMULATOR_MAME% dragon32 -rompath "%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios" -autoboot_delay "4" -autoboot_command "cloadm:exec\\n" -cass "%ROMRAW%"</command>
    <command label="MAME [Dragon 64 Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "dragon64 -rompath \"%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Dragon 64 Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "dragon64 -rompath \"%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Dragon 64 Cartridge] (Standalone)">%EMULATOR_MAME% dragon64 -rompath "%GAMEDIRRAW%;%ROMPATH%/dragon32;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <platform>dragon32</platform>
    <theme>dragon32</theme>
  </system>

  <system>
    <name>fm7</name>
    <fullname>Fujitsu FM-7</fullname>
    <path>%ROMPATH%/fm7</path>
    <extension>.1dd .1DD .77 .cas .CAS .d77 .D77 .d88 .D88 .dfi .DFI .hfe .HFE .imd .IMD .mfi .MFI .mfm .MFM .t77 .T77 .td0 .TD0 .wav .WAV .7z .7Z .zip .ZIP</extension>
    <command label="MAME [FM-7 Diskette]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "fm7 -rompath \"%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [FM-7 Diskette] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "fm7 -rompath \"%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [FM-7 Diskette] (Standalone)">%EMULATOR_MAME% fm7 -rompath "%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <command label="MAME [FM-7 Tape]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "fm7 -rompath \"%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios\" -autoboot_delay \"5\" -autoboot_command \"load\\n\\n\\nrun\\n\" -cass1 \"%ROMRAW%\""</command>
    <command label="MAME [FM-7 Tape] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "fm7 -rompath \"%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios\" -autoboot_delay \"5\" -autoboot_command \"load\\n\\n\\nrun\\n\" -cass1 \"%ROMRAW%\""</command>
    <command label="MAME [FM-7 Tape] (Standalone)">%EMULATOR_MAME% fm7 -rompath "%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios" -autoboot_delay "5" -autoboot_command "load\\n\\n\\nrun\\n" -cass1 "%ROMRAW%"</command>
    <command label="MAME [FM-7 Software list]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "fm7 -rompath \"%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios\" %BASENAME%"</command>
    <command label="MAME [FM-7 Software list] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "fm7 -rompath \"%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios\" %BASENAME%"</command>
    <command label="MAME [FM-7 Software list] (Standalone)">%EMULATOR_MAME% fm7 -rompath "%GAMEDIRRAW%;%ROMPATH%/fm7;%ROMPATH%/bios" %BASENAME%</command>
    <platform>fm7</platform>
    <theme>fm7</theme>
  </system>

  <system>
    <name>supracan</name>
    <fullname>Funtech Super A'Can</fullname>
    <path>%ROMPATH%/supracan</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "supracan -rompath \"%GAMEDIRRAW%;%ROMPATH%/supracan;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "supracan -rompath \"%GAMEDIRRAW%;%ROMPATH%/supracan;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (Standalone)">%EMULATOR_MAME% supracan -rompath "%GAMEDIRRAW%;%ROMPATH%/supracan;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <platform>supracan</platform>
    <theme>supracan</theme>
  </system>

  <!-- ── More systems where ES-DE defaults to an unbundled emulator ──
       bbcmicro defaults to standalone MAME; we route through b2_libretro.
       apple2 defaults to LinApple standalone; we route through mame_libretro
       (apple2e machine — needs apple2e BIOS in ROMs/bios). -->

  <system>
    <name>bbcmicro</name>
    <fullname>Acorn Computers BBC Micro</fullname>
    <path>%ROMPATH%/bbcmicro</path>
    <extension>.dsd .DSD .img .IMG .ssd .SSD .7z .7Z .zip .ZIP</extension>
    <command label="b2">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/b2_libretro.so %ROM%</command>
    <platform>bbcmicro</platform>
    <theme>bbcmicro</theme>
  </system>

  <system>
    <name>apple2</name>
    <fullname>Apple II</fullname>
    <path>%ROMPATH%/apple2</path>
    <extension>.do .DO .dsk .DSK .nib .NIB .po .PO .woz .WOZ .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "apple2e -rompath \"%GAMEDIRRAW%;%ROMPATH%/apple2;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "apple2e -rompath \"%GAMEDIRRAW%;%ROMPATH%/apple2;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <platform>apple2</platform>
    <theme>apple2</theme>
  </system>

  <!-- Apple IIgs uses MAME's apple2gs driver. ES-DE's built-in routes to
       mame_libretro but its rompath omits %ROMPATH%/bios so the BIOS zip
       isn't found even when imported. Override forces correct rompath. -->
  <system>
    <name>apple2gs</name>
    <fullname>Apple IIGS</fullname>
    <path>%ROMPATH%/apple2gs</path>
    <extension>.2mg .2MG .do .DO .dsk .DSK .nib .NIB .po .PO .woz .WOZ .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "apple2gs -rompath \"%GAMEDIRRAW%;%ROMPATH%/apple2gs;%ROMPATH%/bios\" -gameio joy -flop3 \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "apple2gs -rompath \"%GAMEDIRRAW%;%ROMPATH%/apple2gs;%ROMPATH%/bios\" -gameio joy -flop3 \"%ROMRAW%\""</command>
    <command label="MAME (Standalone)">%EMULATOR_MAME% apple2gs -rompath "%GAMEDIRRAW%;%ROMPATH%/apple2gs;%ROMPATH%/bios" -gameio joy -flop3 "%ROMRAW%"</command>
    <command label="MAME [ROM01]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "apple2gsr1 -rompath \"%GAMEDIRRAW%;%ROMPATH%/apple2gs;%ROMPATH%/bios\" -gameio joy -flop3 \"%ROMRAW%\""</command>
    <command label="MAME [ROM01] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "apple2gsr1 -rompath \"%GAMEDIRRAW%;%ROMPATH%/apple2gs;%ROMPATH%/bios\" -gameio joy -flop3 \"%ROMRAW%\""</command>
    <command label="MAME [ROM01] (Standalone)">%EMULATOR_MAME% apple2gsr1 -rompath "%GAMEDIRRAW%;%ROMPATH%/apple2gs;%ROMPATH%/bios" -gameio joy -flop3 "%ROMRAW%"</command>
    <platform>apple2gs</platform>
    <theme>apple2gs</theme>
  </system>

  <!-- ── Systems where ES-DE's built-in already routes to mame_libretro,
       but its rompath omits %ROMPATH%/bios. Override to add the bios path
       so MAME finds the BIOS zips imported from RetroBat. -->

  <system>
    <name>gamate</name>
    <fullname>Bit Corporation Gamate</fullname>
    <path>%ROMPATH%/gamate</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "gamate -rompath \"%GAMEDIRRAW%;%ROMPATH%/gamate;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "gamate -rompath \"%GAMEDIRRAW%;%ROMPATH%/gamate;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>gamate</platform>
    <theme>gamate</theme>
  </system>

  <system>
    <name>pv1000</name>
    <fullname>Casio PV-1000</fullname>
    <path>%ROMPATH%/pv1000</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "pv1000 -rompath \"%GAMEDIRRAW%;%ROMPATH%/pv1000;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "pv1000 -rompath \"%GAMEDIRRAW%;%ROMPATH%/pv1000;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>pv1000</platform>
    <theme>pv1000</theme>
  </system>

  <system>
    <name>scv</name>
    <fullname>Epoch Super Cassette Vision</fullname>
    <path>%ROMPATH%/scv</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "scv -rompath \"%GAMEDIRRAW%;%ROMPATH%/scv;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "scv -rompath \"%GAMEDIRRAW%;%ROMPATH%/scv;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (Standalone)">%EMULATOR_MAME% scv -rompath "%GAMEDIRRAW%;%ROMPATH%/scv;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <platform>scv</platform>
    <theme>scv</theme>
  </system>

  <system>
    <name>vsmile</name>
    <fullname>VTech V.Smile</fullname>
    <path>%ROMPATH%/vsmile</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "vsmile -rompath \"%GAMEDIRRAW%;%ROMPATH%/vsmile;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "vsmile -rompath \"%GAMEDIRRAW%;%ROMPATH%/vsmile;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>vsmile</platform>
    <theme>vsmile</theme>
  </system>

  <system>
    <name>gmaster</name>
    <fullname>Hartung Game Master</fullname>
    <path>%ROMPATH%/gmaster</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "gmaster -rompath \"%GAMEDIRRAW%;%ROMPATH%/gmaster;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "gmaster -rompath \"%GAMEDIRRAW%;%ROMPATH%/gmaster;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>gmaster</platform>
    <theme>gmaster</theme>
  </system>

  <system>
    <name>gamecom</name>
    <fullname>Tiger Game.com</fullname>
    <path>%ROMPATH%/gamecom</path>
    <extension>.bin .BIN .tgc .TGC .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "gamecom -rompath \"%GAMEDIRRAW%;%ROMPATH%/gamecom;%ROMPATH%/bios\" -cart1 \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "gamecom -rompath \"%GAMEDIRRAW%;%ROMPATH%/gamecom;%ROMPATH%/bios\" -cart1 \"%ROMRAW%\""</command>
    <platform>gamecom</platform>
    <theme>gamecom</theme>
  </system>

  <!-- Arcade also benefits from %ROMPATH%/bios — many MAME parent BIOS sets
       (qsound_hle.zip, neogeo.zip etc.) live in ROMs/bios. Without this,
       parent-set BIOS lookup fails on games like 19xx, cps2 etc.
       FBNeo is the default — its romset expectations are looser and more
       forgiving with modern BIOS packs than MAME, so common arcade games
       (Capcom CPS1/2/3, Neo Geo, Sega System 16, fighters, shmups) tend
       to launch cleanly without curated BIOS. MAME (current and 2010)
       remain as alt-emu choices for the games FBNeo doesn't cover. -->
  <system>
    <name>arcade</name>
    <fullname>Arcade</fullname>
    <path>%ROMPATH%/arcade</path>
    <extension>.zip .ZIP .7z .7Z .chd .CHD</extension>
    <command label="FB Neo">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fbneo_libretro.so %ROM%</command>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "%BASENAME% -rompath \"%GAMEDIRRAW%;%ROMPATH%/arcade;%ROMPATH%/bios\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "%BASENAME% -rompath \"%GAMEDIRRAW%;%ROMPATH%/arcade;%ROMPATH%/bios\""</command>
    <platform>arcade</platform>
    <theme>arcade</theme>
  </system>

  <system>
    <name>mame</name>
    <fullname>MAME</fullname>
    <path>%ROMPATH%/mame</path>
    <extension>.zip .ZIP .7z .7Z .chd .CHD</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "%BASENAME% -rompath \"%GAMEDIRRAW%;%ROMPATH%/mame;%ROMPATH%/bios\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "%BASENAME% -rompath \"%GAMEDIRRAW%;%ROMPATH%/mame;%ROMPATH%/bios\""</command>
    <command label="FB Neo">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fbneo_libretro.so %ROM%</command>
    <platform>arcade</platform>
    <theme>mame</theme>
  </system>

</systemList>
CUSTOMSYSTEMS
ok "custom es_systems.xml written (hack systems + ps3psn + xbla)"

# Add ROM directories for all custom systems
for CUSTOM_SYS in snesh nesh gbh gbch gbah genh n64h ggh ps3psn xbla \
    sfc n64dd wiiware megadrivejp saturnjp amiga500 amiga1200 videopacplus vpinball; do
    mkdir -p "$ROMS/$CUSTOM_SYS"
done

#=============================================================================
# STEP 4: RETROARCH CONFIG
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing retroarch.cfg..."

# With HOME=$BASE set in launch.sh, RetroArch automatically reads from:
# $BASE/.config/retroarch/retroarch.cfg — no wrapper script needed
mkdir -p "$BASE/.config/retroarch"

# RetroArch audio driver. Always "pulse" — even on systems where PipeWire is
# the actual server, the pipewire-pulse compatibility layer exposes a
# pulseaudio-compatible socket. The libretro RetroArch AppImage (hizzlekizzle
# nightly) is NOT compiled with native pipewire support, so setting
# audio_driver = "pipewire" produces "Couldn't find any audio driver named
# pipewire" on every launch and falls back to ALSA. "pulse" works on both
# stacks and avoids the noise.
AUDIO_DRIVER="pulse"

# RetroArch video context driver. RA defaults to trying Wayland first
# regardless of session, which produces "[ERROR] [Wayland]: Failed to connect
# to Wayland server" on every X11 session before falling back to GLX. Pin it
# explicitly to match the actual session type. XDG_SESSION_TYPE is the systemd
# standard; WAYLAND_DISPLAY is the env-var fallback.
VIDEO_CONTEXT="x11"
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    VIDEO_CONTEXT="wayland"
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
cheat_database_path = "${BASE}/.config/retroarch/cheats"

# ── Video ──
video_fullscreen = "true"
video_fullscreen_x = "0"
video_fullscreen_y = "0"
video_vsync = "true"
video_max_swapchain_images = "3"
video_scale_integer = "false"
video_aspect_ratio_auto = "true"

# Video context driver — set explicitly to match the user's session so RA
# doesn't waste a startup cycle attempting Wayland on X11 (or vice versa)
# and printing "Failed to connect to Wayland server" before falling back.
# Detected at setup time from \$XDG_SESSION_TYPE / \$WAYLAND_DISPLAY.
video_context_driver = "${VIDEO_CONTEXT}"

# Shaders disabled by default — silences the "[ERROR] [GL]: none shader not
# supported, falling back to stock GLSL" + "[WARN] [GL]: Stock GLSL shaders
# will be used" pair that fires whenever video_shader is unset. Users who
# want CRT/scanline shaders can enable per-core via the RA Quick Menu;
# global default off keeps clean output and lowest latency.
video_shader_enable = "false"
video_shader = ""

# ── Audio ──
audio_driver = "${AUDIO_DRIVER}"
audio_latency = "64"

# ── Menu ──
menu_driver = "ozone"
menu_show_online_updater = "true"
menu_show_core_updater = "true"

# ── Input ──
# SDL2 driver for keyboard AND joypad. Three reasons this is the right choice
# for a portable bundle over the udev driver:
#
# 1. Keyboard works without group membership. The udev driver opens
#    /dev/input/event* directly and needs the user to be in the "input" group
#    on most distros (logged in the RA log as "Couldn't open any keyboard,
#    mouse or touchpad. Are permissions set correctly for /dev/input/event*").
#    SDL2 uses XInput / Wayland protocols for keyboard, which require no
#    elevated permissions — exactly why ES-DE (SDL2-based) has always worked
#    even when RetroArch (udev) doesn't.
#
# 2. Clone gamepads match via GUID, not name. SDL2 ships with
#    SDL_GameControllerDB, a GUID-indexed database that maps VID:PID:rev to a
#    standardized gamepad layout. A "Guangzhou Chicken Run Network Technology
#    Co., Ltd. Wireless Controller" (DS4 clone) is matched by its GUID
#    (03000000<vid><pid>...), not by its kernel name. This sidesteps the
#    entire name-matching mess that udev's libretro autoconfig has with
#    non-OEM controllers.
#
# 3. Hot-plug is robust. SDL2 handles SDL_CONTROLLERDEVICEADDED/REMOVED
#    events; pads can be plugged after RA launches and still map correctly.
#
# Tradeoff: rumble/force-feedback on niche pads is slightly less reliable than
# udev's direct ioctl path. For any standard DS4/DualSense/Xbox/8BitDo, FF
# works fine via SDL2.
#
# NOTE: setting name is "input_joypad_driver" — NOT "joypad_driver". RA
# silently drops the latter on cfg rewrite (verified against libretro stock).
input_driver = "sdl2"
input_joypad_driver = "sdl2"
input_autodetect_enable = "true"

# Joypad autoconfig dir for SDL2. The libretro repo has only ~6 sdl2 profiles
# (most pads work via SDL_GameControllerDB without needing one), but we still
# point at the right place so any that exist are honored. The ":" prefix is
# RetroArch's "relative to retroarch.cfg's directory" — resolves to
# \$BASE/.config/retroarch/autoconfig/sdl2/. STEP 4b populates this.
joypad_autoconfig_dir = ":/autoconfig/sdl2"

# Map first plugged joypad to player 1
input_player1_joypad_index = "0"

# ── Hotkey combos (universal — work across every pad after autoconfig) ──
# These are RetroArch's built-in preset combos, hardcoded to RetroPad logical
# buttons. Unlike "_btn" hotkey bindings (which need per-pad physical indices),
# combo presets just work everywhere. Per-button hotkeys for save state, fast
# forward, etc. require per-pad mapping via the RA quick menu — not solvable
# globally without losing cross-pad portability.
#
# Combo values (universal RA presets, older + stable across builds):
#   0=disabled  1=Down+Y+L1+R1  2=L3+R3  3=L1+R1+Start+Select  4=Hold Start 2s
input_menu_toggle_gamepad_combo = "2"   # L3 + R3                  → open Quick Menu
input_quit_gamepad_combo        = "3"   # L1+R1+Start+Select       → exit to ES-DE

# ── Keyboard exit (explicit, in case RA auto-cleared it) ──
input_exit_emulator = "escape"

# ── Logging ──
# Logging ON by default — non-negotiable for a portable bundle where users will
# hit issues with cores/pads/audio across diverse hardware. Without these, the
# user has no way to diagnose what RA was doing at launch (esp. autoconfig
# matching, which writes its decision to the log and nowhere else — bindings
# applied via autoconfig are runtime-only and don't get persisted to cfg, so
# input_player1_*_btn = "nul" in retroarch.cfg is normal and NOT a signal that
# autoconfig failed). The log lives at ~/.config/retroarch/logs/retroarch.log
# (with HOME=\$BASE in launch.sh, that resolves to inside the bundle).
log_verbosity = "true"
log_to_file = "true"
log_to_file_timestamp = "false"   # single rotating file; launch.sh rotation snippet appends to retroarch-history.log
frontend_log_level = "1"          # 0=debug 1=info 2=warn 3=error — 1 is the right default

# ── Saving ──
savestate_auto_save = "false"
savestate_auto_load = "false"
sort_savefiles_enable = "true"
sort_savestates_enable = "true"
sort_savefiles_by_content_enable = "true"
sort_savestates_by_content_enable = "true"

# ── Rewind ──
rewind_enable = "false"

# ── Core options ──
# Enable per-game .opt overrides so users can dial back specific games that
# misbehave on a non-default core setting (e.g. CPC titles unhappy with
# cap32_model = "6128+") via the RA quick-menu "Save Game Overrides" path.
game_specific_options = "true"

# ── Notifications ──
video_font_enable = "true"
RACFG

ok "retroarch.cfg written → $BASE/.config/retroarch/retroarch.cfg"
mkdir -p "${BASE}/Saves/screenshots"
mkdir -p "${BASE}/Saves/logs"

# ── Per-core option defaults ──
# Caprice32 (Amstrad CPC + GX4000): default the emulated machine to CPC6128+
# so .cpr cartridges (the Amstrad GX4000 / Plus-range carts) actually boot.
# The cap32 core refuses to load a cartridge unless its model is set to
# "6128+" — without this override every Plus-cart launch dies with
# "Cartridge ERROR: Please select CPC6128+".
#
# The 6128+ machine is firmware-compatible with the standard 6128 (same
# OS 3.1 / BASIC 1.1) so nearly all CPC disc games run identically. The
# rare titles that misbehave on Plus firmware can be fixed per-game via
# the RetroArch quick-menu → Options → Save Game Overrides path (enabled
# by game_specific_options = "true" above).
mkdir -p "$BASE/.config/retroarch/config/Caprice32"
CAPRICE32_OPT="$BASE/.config/retroarch/config/Caprice32/Caprice32.opt"
# Only write if absent — preserve user customisations on re-runs.
if [[ ! -f "$CAPRICE32_OPT" ]]; then
    cat > "$CAPRICE32_OPT" <<'CAP32OPT'
cap32_model = "6128+"
cap32_ram = "128"
CAP32OPT
    ok "Caprice32.opt written → cap32_model = \"6128+\" for GX4000/.cpr support"
fi

# FinalBurn Neo: enable patched romsets (decrypted CPS3 / Capcom sets common in
# community packs) and hiscore saving. The default-off patched-romsets check
# rejects ROMs whose CRC doesn't match the canonical set, which catches the
# decrypted versions that ship in most retro arcade packs — turning the flag on
# is the difference between "every CPS3 game errors out" and "they just work".
# Per-game tweaks (region, controls, dipswitches) can still be set in the
# RA quick-menu Options → Save Game Overrides path.
mkdir -p "$BASE/.config/retroarch/config/FinalBurn Neo"
FBNEO_OPT="$BASE/.config/retroarch/config/FinalBurn Neo/FinalBurn Neo.opt"
if [[ ! -f "$FBNEO_OPT" ]]; then
    cat > "$FBNEO_OPT" <<'FBNEOOPT'
fbneo-allow-patched-romsets = "enabled"
fbneo-hiscores = "enabled"
FBNEOOPT
    ok "FinalBurn Neo.opt written → patched-romsets + hiscores enabled"
fi

ok "Portable emulator wrappers written (HOME=$BASE handles config routing)"

# ── XDG-based wrappers for emulators without specific portable flags ──
# Redirects XDG_CONFIG_HOME + XDG_DATA_HOME so all config/data stays
# inside the bundle instead of ~/.config/ and ~/.local/share/
info "Writing XDG portable wrappers..."

# XDG wrappers — all redirect to $BASE/.config/ and $BASE/.local/share/
# This is consistent with HOME=$BASE set in launch.sh, so config location
# is the same whether emulator is launched from ES-DE or directly.

# RPCS3 — XDG wrapper ensures it uses $BASE/.config/rpcs3/ for dev_hdd0 etc.
cat > "$EMUS/rpcs3-portable.sh" << 'RPCS3WRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'rpcs3*.AppImage' -o -name 'RPCS3*.AppImage' | head -1)
exec "$BIN" "$@"
RPCS3WRAP
chmod +x "$EMUS/rpcs3-portable.sh"

# PPSSPP — memstick flag, pointing to $BASE/.config/ppsspp/
# (PSP saves imported here, emulator reads from here)
cat > "$EMUS/ppsspp-portable.sh" << 'PPSSPPWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
mkdir -p "$BASE_DIR/.config/ppsspp"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'PPSSPP*.AppImage' -o -name 'ppsspp*.AppImage' | head -1)
exec "$BIN" --memstick "$BASE_DIR/.config/ppsspp" "$@"
PPSSPPWRAP
chmod +x "$EMUS/ppsspp-portable.sh"

# melonDS
cat > "$EMUS/melonds-portable.sh" << 'MELONDSWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'melonDS*.AppImage' | head -1)
exec "$BIN" "$@"
MELONDSWRAP
chmod +x "$EMUS/melonds-portable.sh"

# Azahar (3DS)
cat > "$EMUS/azahar-portable.sh" << 'AZAHARWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'azahar*.AppImage' -o -name 'Azahar*.AppImage' | head -1)
exec "$BIN" "$@"
AZAHARWRAP
chmod +x "$EMUS/azahar-portable.sh"

# Cemu
cat > "$EMUS/cemu-portable.sh" << 'CEMUWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'Cemu*.AppImage' -o -name 'cemu*.AppImage' | head -1)
exec "$BIN" "$@"
CEMUWRAP
chmod +x "$EMUS/cemu-portable.sh"

# xemu — eeprom.bin and hdd image found in $BASE/.config/xemu/
cat > "$EMUS/xemu-portable.sh" << 'XEMUWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'xemu*.AppImage' | head -1)
exec "$BIN" "$@"
XEMUWRAP
chmod +x "$EMUS/xemu-portable.sh"

# Eden (Switch) — NAND/keys read from $BASE/.local/share/eden/
cat > "$EMUS/eden-portable.sh" << 'EDENWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'Eden*.AppImage' -o -name 'eden*.AppImage' | head -1)
exec "$BIN" "$@"
EDENWRAP
chmod +x "$EMUS/eden-portable.sh"

# shadPS4 — config in $BASE/.config/shadps4/
cat > "$EMUS/shadps4-portable.sh" << 'SHADWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
exec "$SCRIPT_DIR/shadps4" "$@"
SHADWRAP
chmod +x "$EMUS/shadps4-portable.sh"

# 86Box — vmpath for VM configs (separate from XDG)
cat > "$EMUS/86box-portable.sh" << 'BOXWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
mkdir -p "$BASE_DIR/.config/86box"
BOX=$(find "$SCRIPT_DIR" -maxdepth 1 -name '86Box*.AppImage' -o -name '86box*.AppImage' | head -1)
exec "$BOX" --vmpath "$BASE_DIR/.config/86box" "$@"
BOXWRAP
chmod +x "$EMUS/86box-portable.sh"

# VPinball — uses XDG_DATA_HOME for tables/config
# TABLES_PATH tells VPinball where to look for .vpx table files and their
# companion folders (music/, PinMAME ROMs next to the table, etc.)
cat > "$EMUS/vpinball-portable.sh" << 'VPINWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
# Point VPinball at the bundle's vpinball ROM folder so it finds tables,
# backglass files (.directb2s), music, and PinMAME ROMs automatically.
export TABLES_PATH="$BASE_DIR/ROMs/vpinball"
# VPinball ships its own libbgfx.so, libSDL3.so.0, libSDL3_image.so.0,
# libSDL3_ttf.so.0 and libfreeimage.so — SDL3 isn't system-wide on any
# distro yet, so these MUST resolve from the bundle. The installer drops
# them next to the binary; point the loader at this directory.
export LD_LIBRARY_PATH="$SCRIPT_DIR:${LD_LIBRARY_PATH:-}"
# Prefer BGFX (modern renderer), fall back to GL
BIN="$SCRIPT_DIR/VPinballX_BGFX"
[[ ! -f "$BIN" ]] && BIN="$SCRIPT_DIR/VPinballX_GL"
[[ ! -f "$BIN" ]] && BIN="$SCRIPT_DIR/VPinballX"
exec "$BIN" "$@"
VPINWRAP
chmod +x "$EMUS/vpinball-portable.sh"

ok "XDG portable wrappers written (all pointing to \$BASE/.config/ and \$BASE/.local/share/)"

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
# STEP 4b: DOWNLOAD JOYPAD AUTOCONFIG PROFILES
# The RetroArch AppImage doesn't reliably extract bundled controller profiles
# into the portable HOME, leaving .config/retroarch/autoconfig/ empty and
# pads detected-but-unmapped (every input_player1_*_btn = "nul"). Pull the
# canonical profile bundle from libretro/retroarch-joypad-autoconfig as a
# safety net so any common pad just works on first launch.
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading joypad autoconfig profiles..."

if emu_selected retroarch; then
    AUTOCONFIG_DIR="$BASE/.config/retroarch/autoconfig"
    mkdir -p "$AUTOCONFIG_DIR/udev"   # ensure udev/ exists so the find below doesn't error
    # Idempotent: skip if udev/ already populated from a prior run.
    # The `|| echo 0` guards against pipefail aborting on transient find errors.
    EXISTING_UDEV=$(find "$AUTOCONFIG_DIR/udev" -maxdepth 1 -name '*.cfg' 2>/dev/null | wc -l || echo 0)
    if (( EXISTING_UDEV > 50 )); then
        ok "Joypad autoconfig profiles already present ($EXISTING_UDEV udev profiles), skipping"
    else
        AUTOCONFIG_TMP=$(mktemp -d)
        AUTOCONFIG_URL="https://github.com/libretro/retroarch-joypad-autoconfig/archive/refs/heads/master.tar.gz"
        EXTRACT_DIR=""

        # Try curl + tar first (fastest, no git dependency). Errors print to console for diagnostics.
        info "Fetching profiles from libretro/retroarch-joypad-autoconfig (~2 MB)..."
        if curl -fL --connect-timeout 15 --max-time 120 \
                -o "$AUTOCONFIG_TMP/autoconfig.tar.gz" "$AUTOCONFIG_URL"; then
            if tar -xzf "$AUTOCONFIG_TMP/autoconfig.tar.gz" -C "$AUTOCONFIG_TMP"; then
                EXTRACT_DIR=$(find "$AUTOCONFIG_TMP" -maxdepth 1 -type d \
                              -name 'retroarch-joypad-autoconfig*' 2>/dev/null | head -1 || true)
            else
                warn "tar extraction failed"
            fi
        else
            warn "curl download failed (exit $?)"
        fi

        # Fallback: try git clone if curl/tar path didn't yield a usable extract dir
        if [[ -z "$EXTRACT_DIR" || ! -d "$EXTRACT_DIR/udev" ]] && command -v git >/dev/null 2>&1; then
            info "Falling back to git clone..."
            rm -rf "$AUTOCONFIG_TMP"
            AUTOCONFIG_TMP=$(mktemp -d)
            if git clone --depth 1 \
                 https://github.com/libretro/retroarch-joypad-autoconfig.git \
                 "$AUTOCONFIG_TMP/autoconfig"; then
                EXTRACT_DIR="$AUTOCONFIG_TMP/autoconfig"
            else
                warn "git clone also failed (exit $?)"
            fi
        fi

        # Did we end up with a valid extract dir?
        if [[ -n "$EXTRACT_DIR" && -d "$EXTRACT_DIR/udev" ]]; then
            # Copy each driver subdir (udev/, sdl2/, dinput/, xinput/, etc.) into autoconfig dir.
            # Disable pipefail locally so a missing-glob doesn't abort the whole step.
            set +o pipefail
            shopt -s dotglob nullglob
            for driver_dir in "$EXTRACT_DIR"/*/; do
                [[ -d "$driver_dir" ]] || continue
                driver_name=$(basename "$driver_dir")
                [[ "$driver_name" == ".git" ]] && continue
                cfg_count=$(find "$driver_dir" -maxdepth 1 -name '*.cfg' 2>/dev/null | wc -l || echo 0)
                (( cfg_count == 0 )) && continue
                mkdir -p "$AUTOCONFIG_DIR/$driver_name"
                cp -n "$driver_dir"*.cfg "$AUTOCONFIG_DIR/$driver_name/" 2>/dev/null || true
            done
            shopt -u dotglob nullglob
            set -o pipefail

            NEW_UDEV=$(find "$AUTOCONFIG_DIR/udev" -maxdepth 1 -name '*.cfg' 2>/dev/null | wc -l || echo 0)
            if (( NEW_UDEV > 0 )); then
                ok "Installed $NEW_UDEV udev joypad profiles (plus sdl2/dinput/xinput fallbacks)"
            else
                fail "Extraction yielded no profiles — check $AUTOCONFIG_DIR/udev/ contents"
            fi
        else
            fail "Could not download or clone autoconfig profiles"
            info "Manual fix — run this in the bundle root:"
            info "  curl -fL https://github.com/libretro/retroarch-joypad-autoconfig/archive/refs/heads/master.tar.gz \\"
            info "    -o /tmp/ac.tar.gz && tar xzf /tmp/ac.tar.gz -C /tmp/ \\"
            info "    && cp -r /tmp/retroarch-joypad-autoconfig-master/* .config/retroarch/autoconfig/"
            info "Or use git:"
            info "  git clone --depth 1 https://github.com/libretro/retroarch-joypad-autoconfig.git \\"
            info "    /tmp/ac && cp -r /tmp/ac/* .config/retroarch/autoconfig/ && rm -rf /tmp/ac"
        fi
        rm -rf "$AUTOCONFIG_TMP"
    fi
else
    info "Skipped (retroarch deselected — no joypad profiles needed)"
fi

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

The portable retroarch.cfg points `system_directory` here. BIOS/firmware
files are copyrighted — dump from hardware you own.

## How BIOS-missing failures look in practice

When a BIOS file is missing, the emulator typically launches, opens its
window briefly, then closes — no error dialog, no obvious failure. To
diagnose, run `./launch.sh` from a terminal and check the logs:

- **ES-DE log**: `ES-DE/logs/es_log.txt`
- **RetroArch logs**: `.config/retroarch/logs/` (look for "NOT FOUND" lines)

If a game fails silently, that's almost always BIOS. The RetroArch log
will name the exact files it looked for.

## Console / handheld systems

| System          | File(s)                                    | Emulator    |
|-----------------|--------------------------------------------|-------------|
| PS1 (psx)       | scph5501.bin (+ other regions)             | DuckStation |
| PS2 (ps2)       | BIOS files in PCSX2 bios dir               | PCSX2       |
| PS3 (ps3)       | PS3 firmware (PS3UPDAT.PUP)                | RPCS3       |
| Saturn          | saturn_bios.bin                            | RetroArch   |
| Dreamcast       | dc_boot.bin, dc_flash.bin                  | RetroArch   |
| DS (nds)        | bios7.bin, bios9.bin, firmware             | melonDS     |
| GBA (gba)       | gba_bios.bin (optional for mGBA)           | mGBA        |
| 3DS (n3ds)      | see Azahar docs                            | Azahar      |
| Xbox (xbox)     | mcpx_1.0.bin, Complex_4627.bin + HDD image | xemu        |
| Lynx            | lynxboot.img                               | RetroArch   |
| PC Engine CD    | syscard3.pce                               | RetroArch   |
| Neo Geo         | neogeo.zip (in arcade/ or here)            | RetroArch   |
| ColecoVision    | coleco.col                                 | blueMSX     |
| MSX / MSX2      | MSX system ROMs (various)                  | blueMSX     |
| Spectravideo    | SVI-318 / SVI-328 ROMs                     | blueMSX     |
| CreatiVision    | bioscv.rom                                 | JollyCV     |
| Sharp X68000    | iplrom.dat, cgrom.dat                      | PX68K       |

## MAME-driven systems (zip up the BIOS files into the matching name)

These all use mame_libretro and need a `<system>.zip` of MAME BIOS files
in `ROMs/bios/` (or in the system's own ROM folder). MAME version this
bundle ships matches the libretro core's MAME — see the RetroArch log
header for the exact MAME version when troubleshooting.

| ES-DE system | Required BIOS zip(s)                      |
|--------------|-------------------------------------------|
| archimedes   | aa310.zip, archimedes_keyboard.zip        |
| apple2       | apple2e.zip                               |
| apple2gs     | apple2gs.zip                              |
| adam         | adam.zip, adam_kb.zip, adam_prn.zip, adam_ddp.zip, adam_fdc.zip |
| dragon32     | dragon32.zip                              |
| fm7          | fm7.zip (and fm77av.zip if using that)    |
| gamate       | gamate.zip                                |
| gamecom      | gamecom.zip                               |
| gmaster      | gmaster.zip                               |
| pv1000       | pv1000.zip                                |
| scv          | scv.zip                                   |
| supracan     | supracan.zip (umc6650.bin can be empty)   |
| ti99         | ti99_4a.zip, ti99_speech.zip              |
| vsmile       | vsmile.zip                                |
| lcdgames / gameandwatch | one zip per game (gnw_ball.zip, etc.) |

For BBC Micro (b2_libretro), the b2 core handles BIOS internally — no
extra files needed.

## MAME BIOS version mismatches (silent emulator exit)

MAME romsets are tightly version-locked. Each MAME release renames or
restructures BIOS files. If your BIOS pack is from an older MAME (e.g.
RetroBat era, ~MAME 0.174-2016), the current MAME core (0.287+) will
fail to find files inside your zips even though the zips look right —
because the internal filenames have changed.

To handle this, the bundle ships multiple MAME cores side-by-side:
- mame_libretro (current, MAME 0.287+)
- mame2010_libretro (MAME 0.139 — older BIOS fallback)
- mame2003_plus_libretro (MAME 0.78 with backports — oldest fallback)

Note: mame2014/2016 cores are NOT built for Linux x86_64 on the libretro
buildbot, so they aren't included. mame2010 is the closest available
fallback for RetroBat-era BIOS packs (originally targeting MAME 0.174).
Some systems may still fail because BIOS expectations differ between
0.139 and 0.174 — those need a current 0.287-compatible BIOS pack.

Every BIOS zip in this folder is automatically symlinked into each
core's system_directory, so all cores can see the same files.

**To switch a system to an older MAME core in ES-DE:**
1. Highlight the system in the system list (don't enter it).
2. Press the menu button (typically Start or F1 → "Other settings").
3. Choose "Alternative emulator".
4. Pick e.g. "MAME (MAME 2010)" instead of the default "MAME".

You can also override per-game from the game's metadata edit screen.
If the default core fails silently, try MAME 2010 first — it covers
most BIOS packs from the past several years.
BIOSREADME

cat > "$BASE/README.md" << 'MAINREADME'
# Portable ES-DE for Linux

A fully self-contained retro gaming bundle. Unzip and run — no installation needed.

## What is this?

**RetroBat** on Windows gives you a portable, plug-and-play retro gaming setup in a single folder. Nothing like it existed for Linux — until now.

`setup-portable-esde.sh` is a single script that builds a complete portable [ES-DE](https://es-de.org/) retro gaming bundle on any Linux machine. Fully portable: works on any machine, survives OS reinstallations, and runs from any external drive.

---

## What you get

| Component | System | Notes |
|---|---|---|
| **ES-DE 3.4.1** | Frontend | Portable mode — no system installation |
| **RetroArch** | 60+ systems | NES (Mesen), SNES, Genesis, GB/GBC/GBA, N64, PS1, Saturn, Dreamcast, Arcade, MAME & more |
| | | |
| **DuckStation** | PlayStation 1 | Alt to Mednafen PSX core |
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
| **DOSBox-X** | DOS games | |
| **86Box** | Win98 / Windows 9x / retro PC | Configure with your own Windows ISO |
| **Ruffle** | Adobe Flash | |
| **SimCoupe** | MGT SAM Coupé | |
| **Solarus** | Solarus engine games | |
| **Supermodel** | Sega Model 3 | Community AppImage via pkgforge-dev |
| **VPinball** | Visual Pinball | BGFX + GL builds |
| **3dSen** | NES in 3D | Commercial — buy on [Steam](https://store.steampowered.com/app/1147940/3dSen/) or [itch.io](https://geod.itch.io/3dsen), auto-detected if installed |
| **fake-08** | PICO-8 | Free open-source PICO-8 compatible core via RetroArch |

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
├── import-collection.sh         ← Import RetroBat collections anytime
├── verify-bios.sh              ← Check BIOS files (auto-runs after imports)
├── ES-DE/
│   ├── custom_systems/         ← Hack system definitions (snesh, nesh, etc.)
│   ├── settings/               ← ES-DE configuration
│   ├── gamelists/              ← Game metadata
│   └── themes/                 ← Downloaded theme
├── Emulators/
│   ├── RetroArch*.AppImage
│   ├── retroarch-cores/        ← 60+ .so core files
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
| Win98 / retro PC | Windows installation ISO (your own licensed copy) via 86Box |

---

## Importing from RetroBat

If you have an existing RetroBat collection on Windows (dual-boot or a mounted drive), the script can import it automatically — media, gamelists, and ROMs:

```bash
# During initial setup — answer yes to the RetroBat prompt
./setup-portable-esde.sh

# Or anytime after setup using the included converter
./import-collection.sh
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

It checks every emulator against its latest GitHub release, shows you what's changed, and asks before downloading anything. RetroArch and RPCS3 are nightly builds — re-downloading always gets the latest. All 60+ RetroArch cores can also be updated in one go from buildbot.libretro.com.

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
if emu_selected retroarch; then
    download_direct \
        "https://github.com/hizzlekizzle/RetroArch-AppImage/releases/download/Linux_LTS_Nightlies/RetroArch-Linux-x86_64-Nightly.AppImage" \
        "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage" \
        "RetroArch" || true
else
    info "Skipped retroarch (deselected) — no libretro cores will be downloaded"
fi

#=============================================================================
# STEP 9: DOWNLOAD RETROARCH CORES
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading RetroArch cores..."
echo ""
if emu_selected retroarch; then
    download_cores "$EMUS/retroarch-cores"
else
    info "Skipped (RetroArch is deselected)"
fi

#=============================================================================
# Emulator install functions
# Used by both the main install flow below AND by the bundle's
# install-emulator.sh (a heredoc copy of these functions for on-demand
# installation when import-collection.sh imports a system whose emulator
# isn't yet installed).
#=============================================================================

install_retroarch() {
    download_direct \
        "https://github.com/hizzlekizzle/RetroArch-AppImage/releases/download/Linux_LTS_Nightlies/RetroArch-Linux-x86_64-Nightly.AppImage" \
        "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage" \
        "RetroArch" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_rpcs3() {
    download_rpcs3 "$EMUS" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_pcsx2() {
    github_appimage "PCSX2/pcsx2" \
        "linux-appimage-x64.*\.AppImage$" \
        "$EMUS/pcsx2-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_duckstation() {
    github_appimage "stenzek/duckstation" \
        "DuckStation.*x64.*\.AppImage$" \
        "$EMUS/DuckStation-x64.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_ppsspp() {
    github_appimage "hrydgard/ppsspp" \
        "PPSSPP.*x86_64.*\.AppImage$" \
        "$EMUS/PPSSPP-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_melonds() {
    github_appimage "pkgforge-dev/melonDS-AppImage-Enhanced" \
        "melonDS.*x86_64.*\.AppImage$" \
        "$EMUS/melonDS-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_dolphin() {
    github_appimage "pkgforge-dev/Dolphin-emu-AppImage" \
        "Dolphin_Emulator.*x86_64.*\.AppImage$" \
        "$EMUS/dolphin-emu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_cemu() {
    github_appimage "cemu-project/Cemu" \
        "Cemu.*\.AppImage$" \
        "$EMUS/Cemu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_azahar() {
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
}

install_xemu() {
    github_appimage "xemu-project/xemu" \
        "xemu-[0-9].*x86_64\.AppImage$" \
        "$EMUS/xemu-latest.AppImage" || {
            github_appimage "xemu-project/xemu" \
                "xemu.*x86_64\.AppImage$" \
                "$EMUS/xemu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        } || true
}

install_xenia() {
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
}

install_ryujinx() {
    # Ryubing is hosted on a self-managed Forgejo instance, not GitHub
    # Downloads from git.ryujinx.app via their GitHub mirror releases
    if compgen -G "$EMUS/ryujinx*.AppImage" > /dev/null 2>&1; then
        ok "Ryubing already exists, skipping"
    else
        info "Downloading Ryubing ..."
        # Try GitHub mirror first
        RYUBING_URL=$(curl -sfL "https://api.github.com/repos/Ryubing/Ryujinx/releases?per_page=5" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -P "x64\.AppImage$" \
            | head -1) || true
        # Fallback: direct download from ryujinx.app
        if [[ -z "$RYUBING_URL" ]]; then
            RYUBING_URL=$(curl -sfL "https://git.ryujinx.app/api/v1/repos/ryubing/ryujinx/releases?limit=5" \
                | grep -oP '"browser_download_url":\s*"\K[^"]*' \
                | grep -P "x64\.AppImage$" \
                | head -1) || true
        fi
        if [[ -n "$RYUBING_URL" ]]; then
            RYUBING_FNAME=$(basename "$RYUBING_URL")
            if curl -#fL -o "$EMUS/$RYUBING_FNAME" "$RYUBING_URL"; then
                chmod +x "$EMUS/$RYUBING_FNAME"
                ok "Ryubing downloaded: $RYUBING_FNAME"
            else
                fail "Ryubing download failed"
                DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                rm -f "$EMUS/$RYUBING_FNAME"
            fi
        else
            warn "Ryubing URL not found — download manually from https://git.ryujinx.app/ryubing/ryujinx"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi
}

install_eden() {
    # Eden is hosted on git.eden-emu.dev (Gitea instance, not GitHub)
    # Stable releases: git.eden-emu.dev/eden-emu/eden
    # Nightly builds:  git.eden-emu.dev/eden-ci/nightly
    if compgen -G "$EMUS/Eden*.AppImage" > /dev/null 2>&1; then
        ok "Eden already exists, skipping"
    else
        info "Downloading Eden ..."
        # Try stable release first via Gitea API
        EDEN_URL=$(curl -sfL "https://git.eden-emu.dev/api/v1/repos/eden-emu/eden/releases?limit=5&token=" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "amd64.*\.AppImage$|x86_64.*\.AppImage$" \
            | grep -iv "arm\|zsync\|deb\|room" \
            | head -1) || true
        # Fallback: nightly builds
        if [[ -z "$EDEN_URL" ]]; then
            EDEN_URL=$(curl -sfL "https://git.eden-emu.dev/api/v1/repos/eden-ci/nightly/releases?limit=3" \
                | grep -oP '"browser_download_url":\s*"\K[^"]*' \
                | grep -iP "amd64.*\.AppImage$|x86_64.*\.AppImage$" \
                | grep -iv "arm\|zsync\|deb\|room" \
                | head -1) || true
        fi
        if [[ -n "$EDEN_URL" ]]; then
            EDEN_FNAME=$(basename "$EDEN_URL")
            if curl -#fL -o "$EMUS/$EDEN_FNAME" "$EDEN_URL"; then
                chmod +x "$EMUS/$EDEN_FNAME"
                ok "Eden downloaded: $EDEN_FNAME"
            else
                fail "Eden download failed"
                DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                rm -f "$EMUS/$EDEN_FNAME"
            fi
        else
            warn "Eden URL not found — download manually from https://git.eden-emu.dev/eden-emu/eden/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi
}

install_shadps4() {
    if [[ -f "$EMUS/shadps4" ]] || [[ -f "$EMUS/shadps4-qt" ]]; then
        ok "shadPS4 already exists, skipping"
    else
        # shadPS4 ships as tar.gz/zip for Linux — try Qt build first, then headless
        # shadPS4 releases: shadps4-linux-sdl-*.zip containing Shadps4-sdl.AppImage
        SHADPS4_URL=$(curl -sfL "https://api.github.com/repos/shadps4-emu/shadPS4/releases?per_page=5" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "shadps4-linux-sdl.*\.zip$|linux.*x86.?64.*\.(tar\.(gz|xz)|zip)$" \
            | grep -iv "debug\|symbols\|arm\|qt" \
            | grep -v "Pre-release" \
            | head -1) || true
        if [[ -n "$SHADPS4_URL" ]]; then
            info "Downloading shadPS4 ..."
            SHADPS4_TMPDIR=$(mktemp -d)
            SHADPS4_FILE="$SHADPS4_TMPDIR/shadps4-dl"
            if curl -#fL -o "$SHADPS4_FILE" "$SHADPS4_URL"; then
                # Detect archive type by content, not extension
                FILE_TYPE=$(file "$SHADPS4_FILE" | tr '[:upper:]' '[:lower:]')
                if echo "$FILE_TYPE" | grep -q "zip"; then
                    unzip -qo "$SHADPS4_FILE" -d "$SHADPS4_TMPDIR/extract" 2>/dev/null || true
                elif echo "$FILE_TYPE" | grep -q "xz\|lzma"; then
                    tar -xJf "$SHADPS4_FILE" -C "$SHADPS4_TMPDIR" 2>/dev/null || true
                else
                    tar -xzf "$SHADPS4_FILE" -C "$SHADPS4_TMPDIR" 2>/dev/null || true
                fi
                # Find the main shadPS4 executable (qt preferred over headless)
                SHADPS4_BIN=$(find "$SHADPS4_TMPDIR" -type f \( -name "shadps4-qt" -o -name "shadps4" -o -iname "shadps4*.AppImage" -o -iname "Shadps4*.AppImage" \) 2>/dev/null | grep -v "\.so" | head -1)
                if [[ -n "$SHADPS4_BIN" ]]; then
                    # Copy the binary and any sibling shared libs it needs
                    BIN_DIR=$(dirname "$SHADPS4_BIN")
                    cp "$SHADPS4_BIN" "$EMUS/shadps4"
                    chmod +x "$EMUS/shadps4"
                    # Copy .so files from same dir (shadPS4 bundles Qt libs)
                    find "$BIN_DIR" -maxdepth 1 -name "*.so*" -exec cp {} "$EMUS/" \; 2>/dev/null || true
                    find "$BIN_DIR" -maxdepth 1 -type d -exec cp -r {} "$EMUS/" \; 2>/dev/null || true
                    ok "shadPS4 downloaded"
                else
                    fail "Could not find shadPS4 binary inside archive"
                    DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                fi
            else
                fail "shadPS4 download failed"
                DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
            rm -rf "$SHADPS4_TMPDIR"
        else
            warn "shadPS4 download URL not found — check https://github.com/shadps4-emu/shadPS4/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi
}

install__86box() {
    github_appimage "86Box/86Box" \
        "86Box.*x86_64.*\.AppImage$" \
        "$EMUS/86Box-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_vpinball() {
    if [[ -f "$EMUS/VPinballX_BGFX" ]] || [[ -f "$EMUS/VPinballX_GL" ]]; then
        ok "VPinball already exists, skipping"
    else
        # vpinball releases: BGFX and GL are separate zips, each containing one binary
        # plus shared support dirs (scripts/, shaders/, assets/, pinmame/, etc.)
        # Real filename format: VPinballX_BGFX-10.8.1-3788-2151290-linux-x64-Release.zip
        VPINBALL_TMP=$(mktemp -d)
        VPINBALL_GOT=0
        VPINBALL_COUNT_FILE=$(mktemp)
        echo 0 > "$VPINBALL_COUNT_FILE"

        # Fetch BGFX and GL zip URLs from the latest release only
        VPINBALL_URLS=$(curl -sfL "https://api.github.com/repos/vpinball/vpinball/releases?per_page=1"         | grep -oP '"browser_download_url":\s*"\K[^"]*'         | grep -iP "VPinballX_(BGFX|GL)-.*linux.*x64.*\.zip$"         | grep -iv "debug\|symbols") || true

        if [[ -z "$VPINBALL_URLS" ]]; then
            warn "VPinball download URL not found — check https://github.com/vpinball/vpinball/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        else
            # Download and extract each zip — VPinball zips contain a tar.gz inside
            while IFS= read -r VPURL; do
                [[ -z "$VPURL" ]] && continue
                VPZIP=$(basename "$VPURL")
                info "Downloading $VPZIP ..."
                if curl -#fL -o "$VPINBALL_TMP/$VPZIP" "$VPURL"; then
                    # Step 1: unzip to get the tar.gz inside
                    unzip -qo "$VPINBALL_TMP/$VPZIP" -d "$VPINBALL_TMP" 2>/dev/null || true
                    # Step 2: extract any tar.gz that came out of the zip
                    for TGZ in "$VPINBALL_TMP"/*.tar.gz "$VPINBALL_TMP"/*.tar.xz; do
                        [[ -f "$TGZ" ]] || continue
                        mkdir -p "$VPINBALL_TMP/extract"
                        tar -xzf "$TGZ" -C "$VPINBALL_TMP/extract" 2>/dev/null ||                     tar -xJf "$TGZ" -C "$VPINBALL_TMP/extract" 2>/dev/null || true
                        rm -f "$TGZ"
                    done
                    echo $(( $(cat "$VPINBALL_COUNT_FILE") + 1 )) > "$VPINBALL_COUNT_FILE"
                else
                    warn "Failed to download $VPZIP"
                fi
            done <<< "$VPINBALL_URLS"
            VPINBALL_GOT=$(cat "$VPINBALL_COUNT_FILE")
            rm -f "$VPINBALL_COUNT_FILE"

            if [[ $VPINBALL_GOT -gt 0 ]]; then
                # Copy binaries — search at any depth after extraction
                for BIN in VPinballX_BGFX VPinballX_GL VPinballX; do
                    FOUND=$(find "$VPINBALL_TMP" -name "$BIN" -type f 2>/dev/null | head -1)
                    if [[ -n "$FOUND" ]]; then
                        cp "$FOUND" "$EMUS/$BIN"
                        chmod +x "$EMUS/$BIN"
                        ok "  Installed: $BIN"
                    fi
                done
                # Copy all support subdirectories (scripts, shaders, assets, pinmame, etc.)
                EXTRACT_ROOT="$VPINBALL_TMP/extract"
                [[ ! -d "$EXTRACT_ROOT" ]] && EXTRACT_ROOT="$VPINBALL_TMP"
                find "$EXTRACT_ROOT" -mindepth 1 -maxdepth 2 -type d | while read -r D; do
                    DNAME=$(basename "$D")
                    # Skip the extract dir itself and temp root
                    [[ "$DNAME" == "extract" ]] && continue
                    [[ ! -d "$EMUS/$DNAME" ]] && mkdir -p "$EMUS/$DNAME"
                    cp -rn "$D/." "$EMUS/$DNAME/" 2>/dev/null || true
                done
                # Copy bundled shared libraries — VPinball ships libbgfx.so,
                # libSDL3*.so, libfreeimage.so etc. as ROOT-LEVEL files in the
                # archive (NOT in a subdir), so the directory loop above misses
                # them. Without these the binary dies at load time with
                # "error while loading shared libraries: libbgfx.so". Find at
                # any depth and flatten next to the binary; the wrapper's
                # LD_LIBRARY_PATH points the loader here.
                VP_LIBS=0
                while IFS= read -r LIB; do
                    [[ -z "$LIB" ]] && continue
                    LIBNAME=$(basename "$LIB")
                    [[ -f "$EMUS/$LIBNAME" ]] && continue
                    cp "$LIB" "$EMUS/$LIBNAME" 2>/dev/null && VP_LIBS=$((VP_LIBS + 1))
                done < <(find "$EXTRACT_ROOT" -type f -name '*.so*' 2>/dev/null)
                # Synthesize SONAME symlinks (libFOO.so.1.2.3 -> libFOO.so.1).
                # find -type f copies only the real versioned files; the binary
                # links against the major-version SONAME. Without these links
                # the loader fails with "libSDL3.so.0: cannot open shared
                # object file". This mini-ldconfig pass makes it work whether
                # or not the archive shipped the symlinks.
                ( cd "$EMUS" && for real in lib*.so.*; do
                    [[ -f "$real" && ! -L "$real" ]] || continue
                    soname=$(printf '%s' "$real" | sed -E 's/(\.so\.[0-9]+)\..*/\1/')
                    [[ "$soname" != "$real" && ! -e "$soname" ]] && ln -s "$real" "$soname"
                done )
                # VPinball Standalone auto-detects a pinmame/ folder next to the
                # .vpx files; create it so PinMAME-based tables (real solid-state
                # / DMD machines) have a ROM directory. Users drop romset zips
                # into ROMs/vpinball/pinmame/roms/ themselves (copyrighted, like
                # arcade ROMs — not bundled).
                mkdir -p "$ROMS/vpinball/pinmame/roms" "$ROMS/vpinball/pinmame/nvram"
                ok "VPinball downloaded ($VPINBALL_GOT zip(s) extracted, $VP_LIBS shared libs)"
            else
                fail "VPinball downloads all failed"
                DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        fi
        rm -rf "$VPINBALL_TMP"
    fi
    echo ""

}

install_dosbox_x() {
    if compgen -G "$EMUS/[dD]os[bB]ox-[xX]*.AppImage" > /dev/null 2>&1 \
       || compgen -G "$EMUS/DOSBox-X*.AppImage" > /dev/null 2>&1; then
        ok "DOSBox-X already exists, skipping"
    else
        DOSBOXX_URL=$(curl -sfL "https://api.github.com/repos/pkgforge-dev/DOSBox-X-AppImage/releases?per_page=3" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "\.AppImage$" \
            | grep -iv "arm\|aarch" | head -1) || true
        if [[ -n "$DOSBOXX_URL" ]]; then
            info "Downloading DOSBox-X..."
            FNAME=$(basename "$DOSBOXX_URL")
            if curl -#fL -o "$EMUS/$FNAME" "$DOSBOXX_URL"; then
                chmod +x "$EMUS/$FNAME"
                cat > "$EMUS/dosbox-x-portable.sh" << 'DBXWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -iname 'dosbox-x*.AppImage' | head -1)
exec "$BIN" "$@"
DBXWRAP
                chmod +x "$EMUS/dosbox-x-portable.sh"
                ok "DOSBox-X downloaded"
            else
                fail "DOSBox-X download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "DOSBox-X not found — check https://github.com/pkgforge-dev/DOSBox-X-AppImage/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi
}

install_ruffle() {
    if [[ -f "$EMUS/ruffle" ]] || compgen -G "$EMUS/ruffle*.AppImage" > /dev/null 2>&1; then
        ok "Ruffle already exists, skipping"
    else
        RUFFLE_URL=$(curl -sfL "https://api.github.com/repos/ruffle-rs/ruffle/releases?per_page=3"         | grep -oP '"browser_download_url":\s*"\K[^"]*'         | grep -iP "linux.*x86.?64.*\.tar\.gz$"         | grep -iv "debug\|arm" | head -1) || true
        if [[ -n "$RUFFLE_URL" ]]; then
            info "Downloading Ruffle..."
            RUFFLE_TMP=$(mktemp -d)
            if curl -#fL "$RUFFLE_URL" | tar -xz -C "$RUFFLE_TMP" 2>/dev/null; then
                RUFFLE_BIN=$(find "$RUFFLE_TMP" -name "ruffle" -type f | head -1)
                if [[ -n "$RUFFLE_BIN" ]]; then
                    cp "$RUFFLE_BIN" "$EMUS/ruffle"
                    chmod +x "$EMUS/ruffle"
                    cat > "$EMUS/ruffle-portable.sh" << 'RUFFLEWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
exec "$SCRIPT_DIR/ruffle" "$@"
RUFFLEWRAP
                    chmod +x "$EMUS/ruffle-portable.sh"
                    ok "Ruffle downloaded"
                else
                    fail "Ruffle binary not found in archive"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                fi
            else
                fail "Ruffle download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
            rm -rf "$RUFFLE_TMP"
        else
            warn "Ruffle URL not found — check https://github.com/ruffle-rs/ruffle/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi

}

install_eka2l1() {
    if compgen -G "$EMUS/eka2l1*.AppImage" > /dev/null 2>&1 || compgen -G "$EMUS/EKA2L1*.AppImage" > /dev/null 2>&1; then
        ok "EKA2L1 already exists, skipping"
    else
        # The continuous tag is the only release tag — fetch by tag, not "latest"
        EKA2L1_URL=$(curl -sfL "https://api.github.com/repos/EKA2L1/EKA2L1/releases/tags/continous" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "linux.*\.AppImage$" \
            | grep -iv "arm\|aarch" \
            | head -1) || true
        if [[ -n "$EKA2L1_URL" ]]; then
            info "Downloading EKA2L1..."
            EKA2L1_FNAME=$(basename "$EKA2L1_URL")
            if curl -#fL -o "$EMUS/$EKA2L1_FNAME" "$EKA2L1_URL"; then
                chmod +x "$EMUS/$EKA2L1_FNAME"
                cat > "$EMUS/eka2l1-portable.sh" << 'EKA2L1WRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -iname 'eka2l1*.AppImage' -o -iname 'EKA2L1*.AppImage' 2>/dev/null | head -1)
exec "$BIN" "$@"
EKA2L1WRAP
                chmod +x "$EMUS/eka2l1-portable.sh"
                ok "EKA2L1 downloaded ($EKA2L1_FNAME)"
            else
                fail "EKA2L1 download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                rm -f "$EMUS/$EKA2L1_FNAME"
            fi
        else
            warn "EKA2L1 URL not found — check https://github.com/EKA2L1/EKA2L1/releases/tag/continous"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi

}

install_solarus() {
    if [[ -x "$EMUS/solarus-run" ]] || [[ -x "$EMUS/solarus-portable.sh" ]] \
       || compgen -G "$EMUS/solarus*.AppImage" > /dev/null 2>&1; then
        ok "Solarus already exists, skipping"
    else
        # Known stable direct URL — update version number when new releases come out
        SOLARUS_URL="https://gitlab.com/api/v4/projects/solarus-games%2Fsolarus/packages/generic/solarus/2.0.4/solarus-launcher-v2.0.4-linux-x64.tar.gz"
        info "Downloading Solarus..."
        # Solarus ships as a tar.gz containing a standalone binary
        SOLARUS_TMP=$(mktemp -d)
        if curl -#fL "$SOLARUS_URL" | tar -xz -C "$SOLARUS_TMP" 2>/dev/null; then
            SOLARUS_BIN=$(find "$SOLARUS_TMP" -type f -name "solarus*" ! -name "*.so*" 2>/dev/null | head -1)
            if [[ -n "$SOLARUS_BIN" ]]; then
                cp "$SOLARUS_BIN" "$EMUS/solarus-run"
                chmod +x "$EMUS/solarus-run"
                # Copy any bundled data dirs
                find "$SOLARUS_TMP" -mindepth 1 -maxdepth 2 -type d | while read -r D; do
                    cp -rn "$D" "$EMUS/" 2>/dev/null || true
                done
                cat > "$EMUS/solarus-portable.sh" << 'SOLARUSWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
exec "$SCRIPT_DIR/solarus-run" "$@"
SOLARUSWRAP
                chmod +x "$EMUS/solarus-portable.sh"
                ok "Solarus downloaded"
            else
                fail "Solarus binary not found in archive"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "Solarus download failed — check https://www.solarus-games.org/download/"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
        rm -rf "$SOLARUS_TMP"
    fi

}

install_simcoupe() {
    if [[ -f "$EMUS/simcoupe" ]]; then
        ok "SimCoupe already exists, skipping"
    else
        # Version-pinned direct URL — check https://simonowen.com/simcoupe/ for updates
        SIMCOUPE_URL="https://github.com/simonowen/simcoupe/releases/download/v1.2.15/simcoupe_1.2.15_linux_amd64.tar.gz"
        info "Downloading SimCoupe..."
        SIMCOUPE_TMP=$(mktemp -d)
        if curl -#fL "$SIMCOUPE_URL" | tar -xz -C "$SIMCOUPE_TMP" 2>/dev/null; then
            SIMCOUPE_BIN=$(find "$SIMCOUPE_TMP" -name "simcoupe" -type f 2>/dev/null | head -1)
            if [[ -n "$SIMCOUPE_BIN" ]]; then
                cp "$SIMCOUPE_BIN" "$EMUS/simcoupe"
                chmod +x "$EMUS/simcoupe"
                cat > "$EMUS/simcoupe-portable.sh" << 'SIMWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
# SimCoupe writes its config/saves to ~/.simcoupe/ — redirect HOME so
# everything stays in the bundle (true portability).
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
mkdir -p "$BASE_DIR/.simcoupe"
exec "$SCRIPT_DIR/simcoupe" "$@"
SIMWRAP
                chmod +x "$EMUS/simcoupe-portable.sh"
                ok "SimCoupe downloaded"
            else
                fail "SimCoupe binary not found in archive"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "SimCoupe download failed — check https://simonowen.com/simcoupe/"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
        rm -rf "$SIMCOUPE_TMP"
    fi

}

install_supermodel() {
    if compgen -G "$EMUS/supermodel*.AppImage" > /dev/null 2>&1 || [[ -f "$EMUS/supermodel" ]]; then
        ok "Supermodel already exists, skipping"
    else
        SUPERMODEL_URL=$(curl -sfL "https://api.github.com/repos/pkgforge-dev/Supermodel-AppImage/releases?per_page=3"         | grep -oP '"browser_download_url":\s*"\K[^"]*'         | grep -iP "\.AppImage$"         | grep -iv "arm\|aarch" | head -1) || true
        if [[ -n "$SUPERMODEL_URL" ]]; then
            info "Downloading Supermodel..."
            FNAME=$(basename "$SUPERMODEL_URL")
            if curl -#fL -o "$EMUS/$FNAME" "$SUPERMODEL_URL"; then
                chmod +x "$EMUS/$FNAME"
                cat > "$EMUS/supermodel-portable.sh" << 'SUPERWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -iname 'supermodel*.AppImage' | head -1)
[[ -z "$BIN" ]] && BIN="$SCRIPT_DIR/supermodel"
exec "$BIN" "$@"
SUPERWRAP
                chmod +x "$EMUS/supermodel-portable.sh"
                ok "Supermodel downloaded"
            else
                fail "Supermodel download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "Supermodel URL not found — check https://github.com/pkgforge-dev/Supermodel-AppImage/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi

}

install_mame() {
    if compgen -G "$EMUS/MAME*.AppImage" > /dev/null 2>&1 || compgen -G "$EMUS/mame*.AppImage" > /dev/null 2>&1; then
        ok "Standalone MAME already exists, skipping"
    else
        MAME_URL=$(curl -sfL "https://api.github.com/repos/pkgforge-dev/MAME-AppImage/releases?per_page=3" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "\.AppImage$" \
            | grep -iv "arm\|aarch" | head -1) || true
        if [[ -n "$MAME_URL" ]]; then
            info "Downloading standalone MAME..."
            FNAME=$(basename "$MAME_URL")
            if curl -#fL -o "$EMUS/$FNAME" "$MAME_URL"; then
                chmod +x "$EMUS/$FNAME"
                ok "Standalone MAME downloaded ($FNAME)"
            else
                fail "Standalone MAME download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "Standalone MAME URL not found — check https://github.com/pkgforge-dev/MAME-AppImage/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi

}

#=============================================================================
# STEP 10: DOWNLOAD STANDALONE EMULATORS
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading standalone emulators..."
echo ""

DOWNLOAD_ERRORS=0

echo "   ── RPCS3 (PS3) ──"
if emu_selected rpcs3; then
    install_rpcs3
else
    info "Skipped rpcs3 (deselected)"
fi
echo ""

echo "   ── PCSX2 (PS2) ──"
if emu_selected pcsx2; then
    install_pcsx2
else
    info "Skipped pcsx2 (deselected)"
fi
echo ""

echo "   ── DuckStation (PS1) ──"
if emu_selected duckstation; then
    install_duckstation
else
    info "Skipped duckstation (deselected)"
fi
echo ""

echo "   ── PPSSPP (PSP) ──"
if emu_selected ppsspp; then
    install_ppsspp
else
    info "Skipped ppsspp (deselected)"
fi
echo ""

echo "   ── melonDS (DS) ──"
if emu_selected melonds; then
    install_melonds
else
    info "Skipped melonds (deselected)"
fi
echo ""

echo "   ── Dolphin (GC/Wii) ──"
if emu_selected dolphin; then
    install_dolphin
else
    info "Skipped dolphin (deselected)"
fi
echo ""

echo "   ── Cemu (Wii U) ──"
if emu_selected cemu; then
    install_cemu
else
    info "Skipped cemu (deselected)"
fi
echo ""

echo "   ── Azahar (3DS) ──"
if emu_selected azahar; then
    install_azahar
else
    info "Skipped azahar (deselected)"
fi
echo ""

echo "   ── xemu (Xbox) ──"
if emu_selected xemu; then
    install_xemu
else
    info "Skipped xemu (deselected)"
fi
echo ""

echo "   ── Xenia Canary (Xbox 360) ──"
if emu_selected xenia; then
    install_xenia
else
    info "Skipped xenia (deselected)"
fi

echo "   ── Ryubing (Nintendo Switch) ──"
if emu_selected ryujinx; then
    install_ryujinx
else
    info "Skipped ryujinx (deselected)"
fi
echo ""

echo "   ── Eden (Nintendo Switch) ──"
if emu_selected eden; then
    install_eden
else
    info "Skipped eden (deselected)"
fi
echo ""

echo "   ── shadPS4 (PlayStation 4) ──"
if emu_selected shadps4; then
    install_shadps4
else
    info "Skipped shadps4 (deselected)"
fi
echo ""

echo "   ── 86Box (Windows 9x / retro PC) ──"
if emu_selected _86box; then
    install__86box
else
    info "Skipped _86box (deselected)"
fi
echo ""

echo "   ── VPinball (Visual Pinball) ──"
if emu_selected vpinball; then
    install_vpinball
else
    info "Skipped vpinball (deselected)"
fi

#=============================================================================
# STEP 10b: DOWNLOAD ADDITIONAL STANDALONE EMULATORS
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading additional standalone emulators..."

# ── DOSBox-X (best DOS emulation) ──
# Official upstream ships RPM/Flatpak only; use pkgforge-dev community AppImage
echo "   ── DOSBox-X ──"
if emu_selected dosbox_x; then
    install_dosbox_x
else
    info "Skipped dosbox_x (deselected)"
fi

# ── Ruffle (Adobe Flash) ──
echo "   ── Ruffle ──"
if emu_selected ruffle; then
    install_ruffle
else
    info "Skipped ruffle (deselected)"
fi

# ── EKA2L1 (Symbian / N-Gage) ──
# Continuous CI build — only release tag the project ships. AppImage assets
# are named like "EKA2L1-Linux.AppImage" or similar; pattern is loose to
# survive minor naming drift across CI runs.
echo "   ── EKA2L1 (Symbian / N-Gage) ──"
if emu_selected eka2l1; then
    install_eka2l1
else
    info "Skipped eka2l1 (deselected)"
fi

# ── Solarus ──
# Solarus moved to GitLab — AppImage served via direct URL from solarus-games.org
echo "   ── Solarus ──"
if emu_selected solarus; then
    install_solarus
else
    info "Skipped solarus (deselected)"
fi

# ── SimCoupe (MGT SAM Coupé) ──
# No AppImage exists — downloads tar.gz from simonowen.com official site
echo "   ── SimCoupe ──"
if emu_selected simcoupe; then
    install_simcoupe
else
    info "Skipped simcoupe (deselected)"
fi

# ── Supermodel (Sega Model 3) ──
# Community AppImage from pkgforge-dev
echo "   ── Supermodel ──"
if emu_selected supermodel; then
    install_supermodel
else
    info "Skipped supermodel (deselected)"
fi

# ── MAME (standalone, current version) — alt-emu fallback for testing ──
# Community AppImage from pkgforge-dev. Tier 3 fallback in the alt-emu
# menu when neither current mame_libretro nor mame2010 accept a BIOS pack.
# Resolves %EMULATOR_MAME% via es_find_rules.xml.
echo "   ── MAME (standalone) ──"
if emu_selected mame; then
    install_mame
else
    info "Skipped mame (deselected)"
fi

# ── PICO-8 — retro8 libretro is the default (free, on libretro buildbot) ──
# fake08 also supported as alt emulator if user manually compiles & drops in.
# The actual retro8 core download happens earlier in STEP 9 via download_cores(),
# which prints [exists] vs [ok] vs [fail]. This block is informational only —
# don't claim "downloaded" since the core may have been a no-op skip.
echo "   ── PICO-8 ──"
if [[ -f "$EMUS/retroarch-cores/retro8_libretro.so" ]]; then
    ok "PICO-8: retro8 core available (default). For fake08 alt, compile from"
    ok "  https://github.com/jtothebell/fake-08 and drop into Emulators/retroarch-cores/"
else
    info "PICO-8: retro8 core not present (deselected or download failed). For fake08 alt,"
    info "  compile from https://github.com/jtothebell/fake-08 and drop into Emulators/retroarch-cores/"
fi

ok "Additional standalone emulators done"
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

# ES-DE's settings format: flat <bool>/<int>/<string> elements as direct
# children of the document — NO <config> wrapper. ES-DE's loader iterates
# doc.child("bool"), doc.child("string"), etc. directly; wrapping them in
# <config> hides every key and ES-DE treats the file as empty, falling into
# its first-run init path. That path:
#   1. Logs "Application release number setting is blank, changing it to N"
#   2. Creates downloaded_media/, scripts/, screensavers/ at $home/ES-DE/
#      (the DEFAULT location — ignoring our MediaDirectory override)
#   3. Loads the default theme (linear-es-de) instead of our Theme value
# Then on exit it rewrites the file in the correct flat format, so launch 2
# works fine. Hence the "theme/media only on second launch" symptom.
#
# We pre-write the file in the EXACT format ES-DE writes itself, including
# ApplicationRelease so the "blank release number" branch doesn't fire.
# Keys verified against an ES-DE 3.4.1-written settings file.
cat > "$SETTINGS_FILE" << ESSETTINGS
<?xml version="1.0"?>
<bool name="FavoritesFirst" value="true" />
<bool name="FoldersOnTop" value="true" />
<bool name="ShowHiddenGames" value="false" />
<int name="ApplicationRelease" value="51" />
<string name="CollectionSystemsAuto" value="favorites,recent,lastplayed" />
<string name="MediaDirectory" value="${BASE}/downloaded_media" />
<string name="ROMDirectory" value="${ROMS}" />
<string name="Scraper" value="screenscraper" />
<string name="Theme" value="${THEME_NAME:-linear-es-de}" />
ESSETTINGS
ok "es_settings.xml written (flat format, no <config> wrapper — ES-DE format)"

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

    # EmulationStation / Batocera-style suffix → ES-DE folder map
    # Used by try_import_es_layout for packs that store all media flat in
    # one folder with -image / -thumb / -marquee / -Video filename suffixes.
    declare -A ES_SUFFIX_MAP=(
        [image]=screenshots     [screenshot]=screenshots
        [thumb]=covers          [thumbnail]=covers
        [box]=covers            [boxart]=covers          [box2d]=covers
        [marquee]=marquees
        [fanart]=fanart
        [wheel]=wheels
        [titlescreen]=titlescreens
        [manual]=manuals
        [video]=videos
        [mix]=miximages         [miximage]=miximages
        [cart]=physicalmedia    [cartridge]=physicalmedia
    )

    # Try to import ES/Batocera-suffix media from a flat folder.
    # args: source_dir, dest_root, move_mode (yes=cut, else copy)
    # returns 0 if ES-style suffixes were detected and routed, 1 if not.
    try_import_es_layout() {
        local src="$1" dest="$2" move="$3"
        [[ ! -d "$src" ]] && return 1
        # Detect: any file with -<suffix>.<ext> matching our map?
        local has_es=0
        while IFS= read -r f; do
            local name="${f##*/}"; local stem="${name%.*}"
            [[ "$stem" == *-* ]] || continue
            local sl="${stem##*-}"; sl="${sl,,}"
            if [[ -n "${ES_SUFFIX_MAP[$sl]:-}" ]]; then has_es=1; break; fi
        done < <(find "$src" -maxdepth 1 -type f 2>/dev/null)
        (( has_es == 0 )) && return 1

        local n=0 skipped=0
        while IFS= read -r f; do
            local name="${f##*/}"; local stem="${name%.*}"; local ext="${name##*.}"
            if [[ "$stem" != *-* ]]; then skipped=$((skipped + 1)); continue; fi
            local rom_base="${stem%-*}"; local suffix="${stem##*-}"
            local sl="${suffix,,}"
            local esde_folder="${ES_SUFFIX_MAP[$sl]:-}"
            [[ -z "$esde_folder" ]] && { skipped=$((skipped + 1)); continue; }
            mkdir -p "$dest/$esde_folder"
            local dest_path="$dest/$esde_folder/$rom_base.$ext"
            if [[ "$move" == "yes" ]]; then
                mv -n "$f" "$dest_path" 2>/dev/null && n=$((n + 1))
            else
                cp -n "$f" "$dest_path" 2>/dev/null && n=$((n + 1))
            fi
        done < <(find "$src" -maxdepth 1 -type f 2>/dev/null)

        local mode_label="copied"; [[ "$move" == "yes" ]] && mode_label="moved"
        echo -e "      ${GREEN}✓${NC} ES-layout: $n files $mode_label from $(basename "$src")/ → typed folders$([[ $skipped -gt 0 ]] && echo " ($skipped skipped)")"
        return 0
    }

    # System name mapping: ONLY where RetroBat name ≠ ES-DE name.
    # Hack systems (snesh, nesh, gbh, gbch, gbah, genh, n64h, ggh) are defined
    # as their own ES-DE systems via custom_systems/es_systems.xml.
    declare -A SYS_MAP=(
        # ── SNES (sfc/megadrivejp/saturnjp/amiga500/amiga1200/videopacplus/
        #    n64dd/wiiware now have own custom systems — no mapping needed) ──
        [snesna]=snes           [snes-msu]=snes         [sufami]=snes
        # ── NES ──
        [nes_aladdin]=nes       [nes_hd]=nes            [nes-msu]=nes
        # ── Mega Drive ──
        [nomad]=genesis         [megadrive-msu]=megadrive [msu-md]=megadrive
        # ── Game Boy ──
        [gb2players]=gb         [gba2players]=gba       [gbc2players]=gbc
        # ── GameCube / Wii ──
        [gamecube]=gc
        # ── 3DS ──
        [3ds]=n3ds
        # ── Atari ──
        [jaguar]=atarijaguar    [jaguarcd]=atarijaguarcd [lynx]=atarilynx
        # ── Sega ──
        [sg1000]=sg-1000        [sc3000]=sg-1000         [markiii]=mastersystem
        [dreamcast-jp]=dreamcast [saturn-jp]=saturnjp
        # ── NEC ──
        [tgcd]=tg-cd
        # ── SNK ──
        [neogeomvs]=neogeo
        # ── Philips ──
        [cdi]=cdimono1
        # ── Bandai ──
        [wswan]=wonderswan      [wswanc]=wonderswancolor
        # ── Commodore ──
        [c20]=vic20             [cplus4]=plus4          [amiga4000]=amiga
        # ── MSX ──
        [msx1]=msx              [msx2+]=msx2
        # ── Arcade ──
        [fbneo]=arcade          [cave]=arcade
        [gaelco]=arcade         [igspgm]=arcade          [aleck64]=arcade
        # ── xbla maps to xbla (own custom system) — no mapping needed ──
        # ── ps3psn maps to ps3psn (own custom system) — no mapping needed ──
    )

    # Folders that exist in roms/ but are NOT game systems — skip them.
    # RetroBat packs often include metadata/utility folders alongside system folders;
    # importing these creates phantom ES-DE systems and misplaces files.
    declare -A SKIP_SYSTEMS=(
        [media]=1           # RetroBat media root (handled separately per-system)
        [bios]=1            # BIOS/firmware files — imported separately, not a game system
        [emulators]=1       # RetroBat emulator configs — not a game system
        [saves]=1           # Save files — go to Saves/, not ROMs/
        [screenshots]=1     # Screenshots — go to Saves/screenshots/
        [cheats]=1          # Cheats — go to .config/retroarch/cheats/
        [records]=1         # Recording output — not a game system
        [sounds]=1          # Sound packs — not a game system
        [decorations]=1     # Bezel decorations — not a game system
        [library]=1         # RetroArch library cache
        [system]=1          # RetroArch system/bios mirror
        [music]=1           # Background music — not a game system
    )

    for IDX in "${!RETROBAT_PATHS[@]}"; do
        RETROBAT_PATH="${RETROBAT_PATHS[$IDX]}"
        RETROBAT_REAL_PATH="${RETROBAT_REAL_PATHS[$IDX]:-$RETROBAT_PATH}"
        echo ""
        info "Importing from: $RETROBAT_REAL_PATH"
        echo ""

        # ── BIOS files ──
        # Copy flat BIOS files to ROMs/bios/
        # Route emulator-specific subdirs to their correct config locations
        # Skip non-BIOS subdirs (thebezelproject, config, output)
        BIOS_SKIP=(thebezelproject config output bizhawk)
        if [[ -d "$RETROBAT_PATH/bios" ]]; then
            echo -n "   BIOS files → ROMs/bios/              [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
            mkdir -p "$ROMS/bios"
            if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                find "$RETROBAT_PATH/bios" -maxdepth 1 -type f -exec mv -n {} "$ROMS/bios/" \; 2>/dev/null || true
            else
                find "$RETROBAT_PATH/bios" -maxdepth 1 -type f -exec cp -n {} "$ROMS/bios/" \; 2>/dev/null || true
            fi
            echo -e " ${GREEN}done${NC}"

            # Route emulator BIOS subdirs to correct config locations
            for BIOS_SUBDIR in "$RETROBAT_PATH/bios"/*/; do
                [[ -d "$BIOS_SUBDIR" ]] || continue
                BIOS_NAME=$(basename "$BIOS_SUBDIR")
                SKIP=false
                for S in "${BIOS_SKIP[@]}"; do [[ "$BIOS_NAME" == "$S" ]] && SKIP=true; done
                $SKIP && continue

                case "$BIOS_NAME" in
                    duckstation)
                        echo -n "   BIOS/duckstation → .config/duckstation/ [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        mkdir -p "$BASE/.config/duckstation"
                        cp -rn "$BIOS_SUBDIR/." "$BASE/.config/duckstation/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    pcsx2)
                        echo -n "   BIOS/pcsx2 → .config/PCSX2/bios/       [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        mkdir -p "$BASE/.config/PCSX2/bios"
                        cp -rn "$BIOS_SUBDIR/." "$BASE/.config/PCSX2/bios/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    melonds|melonDS|"melonDS DS"|"melonds ds")
                        echo -n "   BIOS/melonds → ROMs/bios/               [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        cp -rn "$BIOS_SUBDIR/." "$ROMS/bios/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    retroarch)
                        echo -n "   BIOS/retroarch → .config/retroarch/system/ [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        mkdir -p "$BASE/.config/retroarch/system"
                        cp -rn "$BIOS_SUBDIR/." "$BASE/.config/retroarch/system/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    mame)
                        echo -n "   BIOS/mame → ROMs/bios/                  [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        # libretro mame_libretro looks for BIOS in either:
                        #   (1) the rompath (we add %ROMPATH%/bios in custom_systems)
                        #   (2) <system_directory>/mame/bios/ or /mame/roms/
                        # Cover both — flatten any .zip found anywhere under bios/mame/
                        # to ROMs/bios/ AND ROMs/bios/mame/bios/ for double safety.
                        # RetroBat's bios/mame/ tree contains hash/, roms/, and sometimes
                        # bios files at the root — we don't want to recursively dump
                        # the whole tree (creates ROMs/bios/hash/, ROMs/bios/roms/ which
                        # MAME ignores). Grab only the .zip files.
                        mkdir -p "$ROMS/bios/mame/bios"
                        find "$BIOS_SUBDIR" -type f \( -iname '*.zip' -o -iname '*.7z' \) \
                            -exec cp -n {} "$ROMS/bios/" \; 2>/dev/null || true
                        find "$BIOS_SUBDIR" -type f \( -iname '*.zip' -o -iname '*.7z' \) \
                            -exec cp -n {} "$ROMS/bios/mame/bios/" \; 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    mednafen)
                        echo -n "   BIOS/mednafen → ROMs/bios/              [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        cp -rn "$BIOS_SUBDIR/." "$ROMS/bios/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    mame2000|mame2003|mame2003-plus|mame2010|mame2014|mame2016|hbmame|fbneo|fba)
                        # Versioned MAME / FBNeo libretro cores look for BIOS in
                        # <system_dir>/<core_name>/. Mirror RetroBat's directory
                        # structure to .config/retroarch/system/<core_name>/ so each
                        # versioned core finds its own romset.
                        echo -n "   BIOS/$BIOS_NAME → .config/retroarch/system/$BIOS_NAME/  [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        mkdir -p "$BASE/.config/retroarch/system/$BIOS_NAME"
                        cp -rn "$BIOS_SUBDIR/." "$BASE/.config/retroarch/system/$BIOS_NAME/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    Databases|Machines|keropi|np2kai|openmsx|same_cdi|flycast|hatari|hatarib|kronos|neocd|psxmame|quasi88|raine|scummvm|vice|xmil|cannonball|fmtowns|fmtownsux|HdPacks|Mupen64plus|PPSSPP|dc)
                        # Core-specific BIOS subdirs — preserve the directory
                        # structure inside ROMs/bios/. blueMSX needs Databases/
                        # and Machines/ as directories. PX68K needs keropi/.
                        # NP2 wants np2kai/. OpenMSX wants openmsx/. etc.
                        echo -n "   BIOS/$BIOS_NAME → ROMs/bios/$BIOS_NAME/  [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        mkdir -p "$ROMS/bios/$BIOS_NAME"
                        cp -rn "$BIOS_SUBDIR/." "$ROMS/bios/$BIOS_NAME/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    xbox)
                        # xemu wants its BIOS in .config/xemu/
                        echo -n "   BIOS/xbox → .config/xemu/  [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        mkdir -p "$BASE/.config/xemu"
                        cp -rn "$BIOS_SUBDIR/." "$BASE/.config/xemu/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    eka2l1)
                        # EKA2L1 (N-Gage) — not currently bundled, but copy data anyway
                        echo -n "   BIOS/eka2l1 → .config/eka2l1/  [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
                        mkdir -p "$BASE/.config/eka2l1"
                        cp -rn "$BIOS_SUBDIR/." "$BASE/.config/eka2l1/" 2>/dev/null || true
                        echo -e " ${GREEN}done${NC}" ;;
                    *)
                        # Unknown subdir — copy flat files to ROMs/bios/ as safe fallback
                        find "$BIOS_SUBDIR" -maxdepth 1 -type f -exec cp -n {} "$ROMS/bios/" \; 2>/dev/null || true ;;
                esac
            done
        fi

        # ── Post-processing: extract specific BIOS files cores need flat ──
        # JollyCV (CreatiVision) wants bioscv.rom — same data as crvision.u20
        # inside the MAME crvision.zip.
        if [[ -f "$ROMS/bios/crvision.zip" && ! -f "$ROMS/bios/bioscv.rom" ]]; then
            if command -v unzip >/dev/null 2>&1; then
                if unzip -p "$ROMS/bios/crvision.zip" crvision.u20 > "$ROMS/bios/bioscv.rom" 2>/dev/null && \
                   [[ -s "$ROMS/bios/bioscv.rom" ]]; then
                    ok "Extracted bioscv.rom from crvision.zip (for JollyCV core)"
                else
                    rm -f "$ROMS/bios/bioscv.rom"
                fi
            fi
        fi

        # ── Mirror flat BIOS zips to versioned MAME core system dirs ──
        # Each libretro MAME core (current/2016/2014/2010/2003-plus) is
        # version-locked to a specific MAME release with its own BIOS romset.
        # Users' BIOS packs match ONE of those versions — usually unknown until
        # tested. Mirror every zip in ROMs/bios/ to each versioned core's
        # system_directory (.config/retroarch/system/<core>/) so when ES-DE
        # falls back to an alt emulator, that core finds the BIOS without
        # needing the user to copy anything.
        #
        # Symlinks are used by default (one source of truth, zero extra disk).
        # FAT32/exFAT don't support symlinks — copy instead on those.
        FS_TYPE=$(stat -f -c %T "$ROMS/bios" 2>/dev/null || echo unknown)
        case "$FS_TYPE" in
            msdos|vfat|exfat)
                MIRROR_MODE=copy
                warn "FAT/exFAT filesystem detected — using BIOS copies (more disk usage)"
                ;;
            *)
                MIRROR_MODE=symlink
                ;;
        esac

        echo -n "   Mirroring MAME BIOS to versioned core dirs ($MIRROR_MODE)..."
        MIRROR_COUNT=0
        for CORE in mame2003-plus mame2010; do
            CORE_DIR="$BASE/.config/retroarch/system/$CORE"
            mkdir -p "$CORE_DIR"
            # Iterate every zip at the top level of ROMs/bios/
            shopt -s nullglob
            for ZIP in "$ROMS/bios"/*.zip "$ROMS/bios"/*.7z; do
                ZNAME=$(basename "$ZIP")
                DEST="$CORE_DIR/$ZNAME"
                [[ -e "$DEST" ]] && continue
                if [[ "$MIRROR_MODE" == "symlink" ]]; then
                    # Relative symlink — survives bundle relocation
                    ln -s "../../../../ROMs/bios/$ZNAME" "$DEST" 2>/dev/null && \
                        MIRROR_COUNT=$((MIRROR_COUNT + 1))
                else
                    cp -n "$ZIP" "$DEST" 2>/dev/null && \
                        MIRROR_COUNT=$((MIRROR_COUNT + 1))
                fi
            done
            shopt -u nullglob
        done
        echo -e " ${GREEN}done${NC} ($MIRROR_COUNT entries)"


        # ── Saves ──
        # Map RetroBat saves → ES-DE Saves/files/ with same SYS_MAP logic
        # Special cases: dolphin, rpcs3, switch, xbox keep their structure
        if [[ -d "$RETROBAT_PATH/saves" ]]; then
            echo ""
            info "Importing saves..."

            # Special-case saves that need specific destinations
            declare -A SAVE_SPECIAL=(
                [dolphin]=".config/dolphin-emu"
                [gamecube]=".config/dolphin-emu"
                [rpcs3]=".config/rpcs3"
                [ps3]=".config/rpcs3"
                [ps3psn]=".config/rpcs3"
                [xbla]="Saves/files/xbla"
                [switch]=".local/share"
                [xbox]=".config/xemu"
                [psp]=".config/ppsspp"
            )

            declare -A SAVE_MERGE=(
                # These still merge since they share hardware/emulator with parent
                [snesna]=snes           [snes-msu]=snes         [sufami]=snes
                [gb2players]=gb         [gbc2players]=gbc        [gba2players]=gba
                [dreamcast-jp]=dreamcast
                [megadrive-msu]=megadrive [msu-md]=megadrive
                [win98]=windows9x       [3ds]=n3ds
                [jaguar]=atarijaguar    [jaguarcd]=atarijaguarcd
                [lynx]=atarilynx        [wswan]=wonderswan      [wswanc]=wonderswancolor
                [tg-16]=tg16            [cdi]=cdimono1
                [c20]=vic20             [cplus4]=plus4          [amiga4000]=amiga
                [msx1]=msx              [msx2+]=msx2            [neogeomvs]=neogeo
                [gw]=gameandwatch       [o2em]=odyssey2         [mesen]=nes
                # Systems with own ES-DE entry — saves go to their own folder
                # (sfc, n64dd, wiiware, megadrivejp, saturnjp, amiga500, amiga1200,
                #  videopacplus, vpinball all handled by default SYS_MAP fallback)
            )

            for SAVE_DIR in "$RETROBAT_PATH/saves"/*/; do
                [[ -d "$SAVE_DIR" ]] || continue
                RB_SYS=$(basename "$SAVE_DIR")

                # Determine destination
                if [[ -n "${SAVE_SPECIAL[$RB_SYS]:-}" ]]; then
                    SAVE_DEST="$BASE/${SAVE_SPECIAL[$RB_SYS]}"
                elif [[ -n "${SAVE_MERGE[$RB_SYS]:-}" ]]; then
                    SAVE_DEST="$BASE/Saves/files/${SAVE_MERGE[$RB_SYS]}"
                else
                    ESDE_SYS="${SYS_MAP[$RB_SYS]:-$RB_SYS}"
                    SAVE_DEST="$BASE/Saves/files/$ESDE_SYS"
                fi

                # Check if there's anything worth copying
                FILE_COUNT=$(find "$SAVE_DIR" -type f 2>/dev/null | wc -l)
                [[ $FILE_COUNT -eq 0 ]] && continue

                printf "      %-20s → %s\n" "$RB_SYS" "${SAVE_DEST#$BASE/}"
                mkdir -p "$SAVE_DEST"
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    cp -rn "$SAVE_DIR/." "$SAVE_DEST/" 2>/dev/null || true
                    rm -rf "$SAVE_DIR" 2>/dev/null || true
                else
                    cp -rn "$SAVE_DIR/." "$SAVE_DEST/" 2>/dev/null || true
                fi
            done
            ok "Saves imported"
        fi

        # ── Cheats ──
        # RetroArch .cht files work directly — copy to retroarch cheats dir
        if [[ -d "$RETROBAT_PATH/cheats" ]]; then
            echo -n "   Cheats → .config/retroarch/cheats/   [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
            mkdir -p "$BASE/.config/retroarch/cheats"
            cp -rn "$RETROBAT_PATH/cheats/." "$BASE/.config/retroarch/cheats/" 2>/dev/null || true
            echo -e " ${GREEN}done${NC}"
        fi

        # ── Screenshots ──
        if [[ -d "$RETROBAT_PATH/screenshots" ]]; then
            echo -n "   Screenshots → Saves/screenshots/      [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
            mkdir -p "$BASE/Saves/screenshots"
            cp -rn "$RETROBAT_PATH/screenshots/." "$BASE/Saves/screenshots/" 2>/dev/null || true
            echo -e " ${GREEN}done${NC}"
        fi

        # ── Collections ──
        # Custom game collections from RetroBat's emulationstation
        ES_COLL="$RETROBAT_PATH/emulationstation/.emulationstation/collections"
        if [[ -d "$ES_COLL" ]]; then
            echo -n "   Collections → ES-DE/collections/      [$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")...]"
            mkdir -p "$ESDE_DATA/collections"
            cp -rn "$ES_COLL/." "$ESDE_DATA/collections/" 2>/dev/null || true
            echo -e " ${GREEN}done${NC}"
        fi

        echo ""

        # Process each system
        for SYS_DIR in "$RETROBAT_PATH/roms"/*/; do
            [[ -d "$SYS_DIR" ]] || continue
            RB_SYS=$(basename "$SYS_DIR")

            # Skip non-system folders
            [[ -n "${SKIP_SYSTEMS[$RB_SYS]:-}" ]] && continue
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
                        TRANSFER_LABEL="$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")"
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
            else
                # Non-RetroBat layouts. Two shapes are common:
                #   (a) ES/Batocera-style with suffixes — images/<rom>-image.png,
                #       images/<rom>-thumb.png, videos/<rom>-Video.mp4
                #   (b) Simple flat with media subfolders directly in ROM dir
                #       and un-suffixed filenames — vpinball-style RetroBat packs
                es_detected=0
                [[ -d "$SYS_DIR/images" ]] && try_import_es_layout "$SYS_DIR/images" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" && es_detected=1
                [[ -d "$SYS_DIR/videos" ]] && try_import_es_layout "$SYS_DIR/videos" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" && es_detected=1
                [[ -d "$SYS_DIR/manuals" ]] && try_import_es_layout "$SYS_DIR/manuals" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" && es_detected=1
                (( es_detected )) && IMPORT_MEDIA=$((IMPORT_MEDIA + 1))

                # Fall back to simple flat copy only if no ES-suffixed media was found
                if (( ! es_detected )); then
                for RB_TYPE in "${!MEDIA_MAP[@]}"; do
                    SRC="$SYS_DIR/$RB_TYPE"
                    if [[ -d "$SRC" ]]; then
                        ESDE_TYPE="${MEDIA_MAP[$RB_TYPE]}"
                        DST="$ESDE_MEDIA_DIR/$ESDE_TYPE"
                        mkdir -p "$DST"
                        TRANSFER_LABEL="$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")"
                        [[ "$RB_TYPE" == "videos" ]] \
                            && echo "      videos (flat) → videos     [$TRANSFER_LABEL — large sets take time...]" \
                            || echo -n "      $(printf '%-14s' "$RB_TYPE") (flat) → $(printf '%-10s' "$ESDE_TYPE") [$TRANSFER_LABEL...]"
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
                fi  # close: if (( ! es_detected ))
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

# Read existing destination gamelist paths to avoid duplicates on merge.
# Also capture any existing <alternativeEmulator> block so we can preserve
# it across the rewrite — users can pick an alt-emu manually via ES-DE's
# UI menu (Options → Alternative Emulators) and we shouldn't clobber that
# choice when they re-run the importer.
# IMPORTANT: ES-DE 3.x requires <alternativeEmulator> to be a SIBLING of
# <gameList> (root level), NOT a child of <gameList>. If it ends up inside
# gameList ES-DE silently ignores it on launch.
existing_paths = set()
existing_alt_emu = ''
if os.path.exists(dst):
    with open(dst, 'r', encoding='utf-8', errors='replace') as f:
        dst_content = f.read()
    for line in dst_content.splitlines():
        m = re.search(r'<path>([^<]+)</path>', line)
        if m:
            existing_paths.add(m.group(1).strip())
    # Capture <alternativeEmulator>...</alternativeEmulator> block (multiline)
    alt_match = re.search(
        r'<alternativeEmulator>.*?</alternativeEmulator>',
        dst_content, re.DOTALL)
    if alt_match:
        existing_alt_emu = alt_match.group(0).rstrip() + '\n'

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
    # No new games — but if we captured an alt-emu block and dest doesn't
    # exist (or was just an alt-emu-only file), still write it back in
    # the canonical OUTSIDE-gameList position.
    if existing_alt_emu and not existing_paths:
        with open(dst, 'w', encoding='utf-8') as f:
            f.write('<?xml version="1.0"?>\n')
            f.write(existing_alt_emu)
            f.write('<gameList>\n</gameList>\n')
    sys.exit(0)

if os.path.exists(dst) and existing_paths:
    # Merge: insert new games before </gameList>. Existing alt-emu (which
    # SHOULD already be outside gameList, but if it isn't we'll fix that
    # below) is left where it is.
    with open(dst, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    insert = '\n'.join(new_games)
    content = content.replace('</gameList>', insert + '\n</gameList>')
    # If alt-emu ended up inside <gameList>, hoist it out
    if existing_alt_emu:
        # Strip alt-emu wherever it is, then re-insert before <gameList>
        content = re.sub(r'\s*<alternativeEmulator>.*?</alternativeEmulator>\s*',
                         '\n', content, flags=re.DOTALL)
        content = re.sub(r'(<gameList[\s>])',
                         existing_alt_emu + r'\1', content, count=1)
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(content)
else:
    # Fresh write — alt-emu OUTSIDE gameList (canonical ES-DE 3.x position)
    with open(dst, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0"?>\n')
        if existing_alt_emu:
            f.write(existing_alt_emu)
        f.write('<gameList>\n')
        f.writelines(new_games)
        f.write('</gameList>\n')
GLFIX
            fi

            # ROMs — detect category-folder systems and flatten, or preserve disc-game folders
            # Category systems (C64, Amiga, etc.) organise ROMs in subfolders like 1-hit/, 2-best/
            # Disc systems (PS2, PS3, GC, etc.) have per-game folders that must be preserved
            # vpinball: .vpx tables are flat at the ROM dir root (RetroBat pack layout)
            FLAT_ROM_SYSTEMS=(c64 amiga amiga500 amiga1200 amigacd32 msx msx2 msx1 vic20 atarist
                              zxspectrum zx81 dos atari800 pc vpinball)
            IS_FLAT=false
            for FS in "${FLAT_ROM_SYSTEMS[@]}"; do
                [[ "$ESDE_SYS" == "$FS" || "$RB_SYS" == "$FS" ]] && IS_FLAT=true && break
            done

            TRANSFER_LABEL="$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "cutting" || echo "copying")"
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
                    # Skip media folders — RetroBat's media/ AND ES/Batocera-style
                    # images/ videos/ manuals/ — so they aren't copied into the
                    # ROM directory as if they were game subfolders.
                    case "$DIRNAME" in media|images|videos|manuals) continue ;; esac
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

    # Cut mode — delete source files from real paths (not synthetic symlink parents)
    if [[ "$RETROBAT_MOVE" == "yes" ]]; then
        for IDX in "${!RETROBAT_REAL_PATHS[@]}"; do
            REAL="${RETROBAT_REAL_PATHS[$IDX]}"
            SYNTH="${RETROBAT_PATHS[$IDX]}"
            if [[ "$SYNTH" == "$REAL" ]]; then
                # Full RetroBat install — remove roms/ and bios/ subfolders
                rm -rf "$REAL/roms" "$REAL/bios" 2>/dev/null || true
                ok "Removed: $REAL/roms and bios"
            else
                # Standalone ROM pack — remove the entire folder (it was the roms dir)
                rm -rf "$REAL" 2>/dev/null || true
                ok "Removed: $REAL"
            fi
        done
    fi

    # Clean up synthetic temp directories
    for SYNTH_DIR in "${RETROBAT_SYNTH_DIRS[@]:-}"; do
        [[ -d "$SYNTH_DIR" ]] && rm -rf "$SYNTH_DIR"
    done
    echo ""
fi

# ── Post-import cleanup: remove any RetroBat non-system folders from ROMs/ ──
# These can appear even without a RetroBat import if the user's ROM pack
# included them. Remove only if empty to avoid accidental data loss.
# bios is intentionally excluded here — it lives in ROMs/bios/ legitimately and must not be deleted
NON_SYSTEM_FOLDERS=(emulators saves screenshots cheats records sounds decorations library system music)
for NSF in "${NON_SYSTEM_FOLDERS[@]}"; do
    NSF_PATH="$ROMS/$NSF"
    if [[ -d "$NSF_PATH" ]]; then
        FILE_COUNT=$(find "$NSF_PATH" -type f 2>/dev/null | wc -l)
        if [[ $FILE_COUNT -eq 0 ]]; then
            rm -rf "$NSF_PATH"
        else
            warn "ROMs/$NSF has $FILE_COUNT files — not auto-removed. Move contents manually if needed."
        fi
    fi
done

# ── Remove known junk subfolders that some RetroBat packs embed inside ROM dirs ──
for JUNK_DIR in "$ROMS/ps4/_saves_" "$ROMS/ps3/_saves_" "$ROMS/xbox360/_saves_" "$ROMS/xbla/_saves_"; do
    [[ -d "$JUNK_DIR" ]] && rm -rf "$JUNK_DIR" && ok "Removed junk folder: $JUNK_DIR"
done

# ── ps3psn media: symlink to ps3 media so both systems share the same artwork ──
if [[ -d "$BASE/downloaded_media/ps3" ]] && [[ ! -e "$BASE/downloaded_media/ps3psn" ]]; then
    ln -s "$BASE/downloaded_media/ps3" "$BASE/downloaded_media/ps3psn"
    ok "ps3psn media symlinked to ps3"
fi

# ── vpinball: migrate flat media folders from ROM dir to downloaded_media ──
VPIN_ROM="$ROMS/vpinball"
VPIN_MEDIA="$BASE/downloaded_media/vpinball"
if [[ -d "$VPIN_ROM" ]]; then
    declare -A VPIN_MAP=([images]=screenshots [marquee]=marquees [marquees]=marquees
                         [videos]=videos [manuals]=manuals [fanart]=fanart)
    for SRC_NAME in "${!VPIN_MAP[@]}"; do
        SRC="$VPIN_ROM/$SRC_NAME"
        [[ -d "$SRC" ]] || continue
        DST="$VPIN_MEDIA/${VPIN_MAP[$SRC_NAME]}"
        mkdir -p "$DST"
        mv -n "$SRC"/. "$DST/" 2>/dev/null || true
        rmdir "$SRC" 2>/dev/null || true
        ok "vpinball: moved $SRC_NAME -> downloaded_media/vpinball/${VPIN_MAP[$SRC_NAME]}"
    done
fi

#=============================================================================
# STEP 13: WRITE CONVERSION SCRIPT TO BUNDLE
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing import-collection.sh to bundle..."

cat > "$BASE/import-collection.sh" << 'CONVSCRIPT'
#!/usr/bin/env bash
#=============================================================================
# Portable ES-DE — Collection Importer
# Import a RetroBat install, a ROM-pack collection, or a single-system
# folder into the bundle. Run anytime after setup.
# Usage: ./import-collection.sh [--dry-run]
#   --dry-run   scan sources and report what WOULD be imported;
#               copies/moves/modifies NOTHING.
#=============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
ROMS="$BASE/ROMs"
ESDE_DATA="$BASE/ES-DE"
MEDIA_BASE="$BASE/downloaded_media"

# --dry-run: scan sources and report what WOULD happen, copying/moving nothing.
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|--dry|-n) DRY_RUN=true ;;
        -h|--help)
            echo "Usage: ./import-collection.sh [--dry-run]"
            echo "  --dry-run   scan sources, report what would import, change nothing"
            exit 0 ;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "   ${GREEN}✓${NC} $1"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; }
info() { echo -e "   ${CYAN}→${NC} $1"; }

# Whiptail UI helpers (bundle requires whiptail — installed by setup)
if ! command -v whiptail >/dev/null 2>&1; then
    fail "whiptail is required but not found in PATH."
    echo "   Install with: sudo apt install whiptail   (or 'sudo dnf install newt' on Fedora)"
    exit 1
fi
wt_input() { whiptail --title "$1" --inputbox "$2" 14 78 "$3" 3>&1 1>&2 2>&3; }
wt_yesno() { whiptail --title "$1" --yesno "$2" 14 78; }
wt_menu() {
    local title="$1" prompt="$2"; shift 2
    whiptail --title "$title" --menu "$prompt" 22 78 12 "$@" 3>&1 1>&2 2>&3
}
wt_msg()  { whiptail --title "$1" --msgbox "$2" 14 78; }

echo ""
echo -e "${CYAN}Collection Importer → ES-DE${NC}"
$DRY_RUN && echo -e "${YELLOW}── DRY RUN — nothing will be copied, moved, or modified ──${NC}"
echo ""

RETROBAT_PATHS=()
while true; do
    [[ ${#RETROBAT_PATHS[@]} -eq 0 ]] && PROMPT_LABEL="Path" || PROMPT_LABEL="Another path"
    INPUT=$(wt_input "Import Collection" \
"$PROMPT_LABEL to a collection folder — a RetroBat install or any ROM pack
containing a 'roms' subfolder.

Leave blank and press OK to finish adding paths and continue." \
        "") || INPUT=""
    [[ -z "$INPUT" ]] && break
    INPUT="${INPUT/#\~/$HOME}"
    INPUT="$(realpath -m "$INPUT")"
    if [[ -d "$INPUT/roms" ]]; then
        RETROBAT_PATHS+=("$INPUT")
        echo -e "   ${GREEN}✓${NC} Added (collection): $INPUT"
    elif [[ -n "$(ls -A "$INPUT" 2>/dev/null)" ]]; then
        # No roms/ subfolder, but the folder has content — treat it as a
        # single-system folder where the folder name IS the system
        # (e.g. pointing directly at a dreamcast/ folder of .chd files).
        RETROBAT_PATHS+=("$INPUT")
        echo -e "   ${GREEN}✓${NC} Added (single system '$(basename "$INPUT")'): $INPUT"
    else
        wt_msg "Path not valid" "Empty folder, or no 'roms' subfolder:\n\n$INPUT\n\nSkipping this entry."
    fi
done

[[ ${#RETROBAT_PATHS[@]} -eq 0 ]] && echo "Nothing to import." && exit 0

RETROBAT_MOVE=""
if ! $DRY_RUN; then
    MOVE_CHOICE=$(wt_menu "Transfer mode" \
"How should files be transferred from the source to the ES-DE bundle?" \
    "copy" "Keep originals (safe, uses extra disk space)" \
    "cut"  "Move files as they're imported (no extra space needed)") || MOVE_CHOICE="copy"
    [[ "$MOVE_CHOICE" == "cut" ]] && RETROBAT_MOVE="yes"
fi
echo ""

declare -A MEDIA_MAP=(
    [thumbnails]=3dboxes [box2d]=covers [fanarts]=fanart [marquee]=marquees
    [images]=screenshots [titles]=titlescreens [cartridges]=physicalmedia [videos]=videos
)

# EmulationStation / Batocera-style suffix → ES-DE folder map
declare -A ES_SUFFIX_MAP=(
    [image]=screenshots     [screenshot]=screenshots
    [thumb]=covers          [thumbnail]=covers
    [box]=covers            [boxart]=covers          [box2d]=covers
    [marquee]=marquees
    [fanart]=fanart
    [wheel]=wheels
    [titlescreen]=titlescreens
    [manual]=manuals
    [video]=videos
    [mix]=miximages         [miximage]=miximages
    [cart]=physicalmedia    [cartridge]=physicalmedia
)

# Try to import ES/Batocera-suffix media from a flat folder.
# args: source_dir, dest_root, move_mode (yes=cut, else copy)
# returns 0 if ES-style suffixes were detected and routed, 1 if not.
try_import_es_layout() {
    local src="$1" dest="$2" move="$3"
    [[ ! -d "$src" ]] && return 1
    local has_es=0
    while IFS= read -r f; do
        local name="${f##*/}"; local stem="${name%.*}"
        [[ "$stem" == *-* ]] || continue
        local sl="${stem##*-}"; sl="${sl,,}"
        if [[ -n "${ES_SUFFIX_MAP[$sl]:-}" ]]; then has_es=1; break; fi
    done < <(find "$src" -maxdepth 1 -type f 2>/dev/null)
    (( has_es == 0 )) && return 1

    local n=0 skipped=0
    while IFS= read -r f; do
        local name="${f##*/}"; local stem="${name%.*}"; local ext="${name##*.}"
        if [[ "$stem" != *-* ]]; then skipped=$((skipped + 1)); continue; fi
        local rom_base="${stem%-*}"; local suffix="${stem##*-}"
        local sl="${suffix,,}"
        local esde_folder="${ES_SUFFIX_MAP[$sl]:-}"
        [[ -z "$esde_folder" ]] && { skipped=$((skipped + 1)); continue; }
        mkdir -p "$dest/$esde_folder"
        local dest_path="$dest/$esde_folder/$rom_base.$ext"
        if [[ "$move" == "yes" ]]; then
            mv -n "$f" "$dest_path" 2>/dev/null && n=$((n + 1))
        else
            cp -n "$f" "$dest_path" 2>/dev/null && n=$((n + 1))
        fi
    done < <(find "$src" -maxdepth 1 -type f 2>/dev/null)

    local mode_label="copied"; [[ "$move" == "yes" ]] && mode_label="moved"
    echo -e "      ${GREEN}✓${NC} ES-layout: $n files $mode_label from $(basename "$src")/ → typed folders$([[ $skipped -gt 0 ]] && echo " ($skipped skipped)")"
    return 0
}

declare -A SYS_MAP=(
    # SNES
    [snesna]=snes           [snes-msu]=snes         [sufami]=snes
    # NES
    [nes_aladdin]=nes       [nes_hd]=nes            [nes-msu]=nes
    # Mega Drive
    [nomad]=genesis         [megadrive-msu]=megadrive [msu-md]=megadrive
    # Game Boy
    [gb2players]=gb         [gba2players]=gba       [gbc2players]=gbc
    # GameCube / Wii
    [gamecube]=gc
    # 3DS
    [3ds]=n3ds
    # Atari
    [jaguar]=atarijaguar    [jaguarcd]=atarijaguarcd [lynx]=atarilynx
    # Sega
    [sg1000]=sg-1000        [sc3000]=sg-1000         [markiii]=mastersystem
    [dreamcast-jp]=dreamcast [saturn-jp]=saturnjp
    # NEC
    [tgcd]=tg-cd
    # SNK
    [neogeomvs]=neogeo
    # Philips
    [cdi]=cdimono1
    # Bandai
    [wswan]=wonderswan      [wswanc]=wonderswancolor
    # Commodore
    [c20]=vic20             [cplus4]=plus4          [amiga4000]=amiga
    # MSX
    [msx1]=msx              [msx2+]=msx2
    # Arcade
    [fbneo]=arcade          [cave]=arcade
    [gaelco]=arcade         [igspgm]=arcade          [aleck64]=arcade
)
FLAT_ROM_SYSTEMS=(c64 amiga amiga500 amiga1200 amigacd32 msx msx2 msx1 vic20 atarist zxspectrum zx81 dos atari800 pc vpinball)

# ES-DE system → required standalone emulator (uses install-emulator.sh)
declare -A SYS_TO_EMU=(
    [gc]=dolphin           [wii]=dolphin             [wiiware]=dolphin
    [wiiu]=cemu
    [ps2]=pcsx2
    [ps3]=rpcs3            [ps3psn]=rpcs3
    [ps4]=shadps4
    [psp]=ppsspp
    [nds]=melonds
    [n3ds]=azahar          [3ds]=azahar
    [switch]=eden
    [xbox]=xemu
    [xbox360]=xenia        [xbla]=xenia
    [vpinball]=vpinball
    [model2]=supermodel    [model3]=supermodel
    [dos]=dosbox_x
    [windows]=_86box       [win98]=_86box
    [flash]=ruffle
    [solarus]=solarus
    [samcoupe]=simcoupe
    [ngage]=eka2l1
    # MAME standalone systems (current MAME for software lists)
    [archimedes]=mame      [apple2gs]=mame          [adam]=mame
    [dragon32]=mame        [fm7]=mame               [ti99]=mame
    [supracan]=mame        [scv]=mame               [pv1000]=mame
    [gamate]=mame          [gmaster]=mame           [gamecom]=mame
    [videopacplus]=mame    [vsmile]=mame            [spectravideo]=mame
    [pico]=mame            [satellaview]=mame
)

# ES-DE system → recommended libretro core (uses install-core.sh; needs RetroArch)
declare -A SYS_TO_CORE=(
    [psx]=mednafen_psx_hw
    [saturn]=mednafen_saturn          [saturnjp]=mednafen_saturn
    [snes]=snes9x                     [sfc]=snes9x
    [snesh]=snes9x                    [sgb]=snes9x
    [nes]=fceumm                      [famicom]=fceumm    [nesh]=fceumm
    [gb]=gambatte                     [gbh]=gambatte
    [gbc]=gambatte                    [gbch]=gambatte
    [gba]=mgba                        [gbah]=mgba
    [megadrive]=genesis_plus_gx       [megadrivejp]=genesis_plus_gx
    [genesis]=genesis_plus_gx         [genh]=genesis_plus_gx
    [mastersystem]=genesis_plus_gx
    [gamegear]=genesis_plus_gx        [ggh]=genesis_plus_gx
    [megacd]=genesis_plus_gx          [segacd]=genesis_plus_gx
    [sg-1000]=genesis_plus_gx         [sg1000]=genesis_plus_gx
    [sega32x]=picodrive
    [dreamcast]=flycast               [atomiswave]=flycast
    [naomi]=flycast                   [naomi2]=flycast
    [n64]=mupen64plus_next            [n64h]=mupen64plus_next
    [n64dd]=mupen64plus_next
    [atari2600]=stella
    [atari5200]=a5200
    [atari7800]=prosystem
    [atarilynx]=handy                 [lynx]=handy
    [atarist]=hatari
    [atarijaguar]=virtualjaguar
    [atarijaguarcd]=virtualjaguar
    [3do]=opera
    [colecovision]=bluemsx
    [intellivision]=freeintv
    [vectrex]=vecx
    [neogeo]=fbneo
    [neogeocd]=neocd
    [pcengine]=mednafen_pce           [tg16]=mednafen_pce
    [supergrafx]=mednafen_pce
    [pcenginecd]=mednafen_pce_fast    [tg-cd]=mednafen_pce_fast
    [pcfx]=mednafen_pcfx
    [virtualboy]=mednafen_vb
    [ngp]=mednafen_ngp                [ngpc]=mednafen_ngp
    [wonderswan]=mednafen_wswan       [wonderswancolor]=mednafen_wswan
    [zxspectrum]=fuse                 [zx81]=81
    [c64]=vice_x64                    [vic20]=vice_xvic   [plus4]=vice_xplus4
    [amiga]=puae                      [amiga500]=puae
    [amiga1200]=puae                  [amigacd32]=puae
    [amstradcpc]=cap32
    [msx]=bluemsx                     [msx1]=bluemsx
    [msx2]=bluemsx                    [msxturbor]=bluemsx
    [scummvm]=scummvm
    [pico8]=retro8
    [arcade]=mame2003_plus
    [cps1]=fbneo                      [cps2]=fbneo        [cps3]=fbneo
    [pc98]=np2kai
    [x68000]=px68k
    [x1]=x1
    [bbcmicro]=b2
    [cdimono1]=  # CD-i: no good libretro core; standalone CDi required (not in bundle yet)
    [pokemini]=pokemini
    [easyrpg]=easyrpg
    [odyssey2]=o2em                   [videopac]=o2em
    [channelf]=freechaf
    [arduboy]=arduous
    [uzebox]=uzem
    [tic80]=tic80
)

# Bundle-relative file checks
is_emulator_installed() {
    local emu="$1"
    case "$emu" in
        rpcs3)       compgen -G "$EMUS/rpcs3*" > /dev/null ;;
        pcsx2)       compgen -G "$EMUS/pcsx2*" > /dev/null ;;
        duckstation) compgen -G "$EMUS/[dD]uckstation*" > /dev/null ;;
        ppsspp)      compgen -G "$EMUS/[pP]psspp*" > /dev/null || compgen -G "$EMUS/PPSSPP*" > /dev/null ;;
        melonds)     compgen -G "$EMUS/[mM]elon*" > /dev/null ;;
        dolphin)     compgen -G "$EMUS/[dD]olphin*" > /dev/null ;;
        cemu)        compgen -G "$EMUS/[cC]emu*" > /dev/null || compgen -G "$EMUS/Cemu*" > /dev/null ;;
        azahar)      compgen -G "$EMUS/[aA]zahar*" > /dev/null ;;
        xemu)        compgen -G "$EMUS/xemu*" > /dev/null ;;
        xenia)       compgen -G "$EMUS/[xX]enia*" > /dev/null ;;
        ryujinx)     compgen -G "$EMUS/[rR]yujinx*" > /dev/null || compgen -G "$EMUS/[rR]yubing*" > /dev/null ;;
        eden)        compgen -G "$EMUS/[eE]den*" > /dev/null ;;
        shadps4)     compgen -G "$EMUS/[sS]hadps4*" > /dev/null ;;
        _86box)      compgen -G "$EMUS/86[bB]ox*" > /dev/null || compgen -G "$EMUS/_86Box*" > /dev/null ;;
        vpinball)    compgen -G "$EMUS/VPinball*" > /dev/null ;;
        dosbox_x)    compgen -G "$EMUS/dosbox-x*" > /dev/null || compgen -G "$EMUS/[dD]osBox*" > /dev/null ;;
        ruffle)      compgen -G "$EMUS/ruffle*" > /dev/null || [[ -f "$EMUS/ruffle" ]] ;;
        eka2l1)      compgen -G "$EMUS/[eE]ka2l1*" > /dev/null || compgen -G "$EMUS/EKA2L1*" > /dev/null ;;
        solarus)     compgen -G "$EMUS/solarus*" > /dev/null ;;
        simcoupe)    compgen -G "$EMUS/[sS]im[cC]oupe*" > /dev/null ;;
        supermodel)  compgen -G "$EMUS/[sS]upermodel*" > /dev/null ;;
        mame)        compgen -G "$EMUS/mame*" > /dev/null || compgen -G "$EMUS/MAME*" > /dev/null ;;
        *)           return 1 ;;
    esac
}

is_retroarch_installed() {
    compgen -G "$EMUS/[rR]etroArch*" > /dev/null || compgen -G "$EMUS/retroarch*" > /dev/null
}

is_core_installed() {
    [[ -f "$EMUS/retroarch-cores/${1}_libretro.so" ]]
}

# Detect missing emulator/core for an ES-DE system, prompt to install, dispatch.
# Called right after each system's import block finishes.
ensure_emulator_for() {
    local esde_sys="$1"
    local emu="${SYS_TO_EMU[$esde_sys]:-}"
    local core="${SYS_TO_CORE[$esde_sys]:-}"

    if [[ -n "$emu" ]] && ! is_emulator_installed "$emu"; then
        echo ""
        if wt_yesno "Missing emulator: $emu" \
"$esde_sys ROMs were imported but the $emu emulator is not installed.

Install $emu now?"; then
            if [[ -x "$BASE/install-emulator.sh" ]]; then
                "$BASE/install-emulator.sh" "$emu" || warn "install-emulator.sh failed for $emu"
            else
                warn "install-emulator.sh not found in bundle"
            fi
        else
            info "Skipped $emu install — $esde_sys games will not launch until you install it"
        fi
        echo ""
    fi

    if [[ -n "$core" ]]; then
        if ! is_retroarch_installed; then
            echo ""
            if wt_yesno "Missing RetroArch + $core" \
"$esde_sys needs RetroArch + the $core libretro core, but RetroArch is not installed.

Install RetroArch + $core now?"; then
                if [[ -x "$BASE/install-emulator.sh" ]]; then
                    "$BASE/install-emulator.sh" retroarch || warn "install-emulator.sh failed for retroarch"
                else
                    warn "install-emulator.sh not found in bundle"
                fi
                if [[ -x "$BASE/install-core.sh" ]]; then
                    "$BASE/install-core.sh" "$core" || warn "install-core.sh failed for $core"
                else
                    warn "install-core.sh not found in bundle"
                fi
            else
                info "Skipped RetroArch + $core install — $esde_sys games will not launch until you install them"
            fi
            echo ""
        elif ! is_core_installed "$core"; then
            echo ""
            if wt_yesno "Missing libretro core: $core" \
"$esde_sys ROMs were imported but the $core libretro core is not installed.

Install $core now?"; then
                if [[ -x "$BASE/install-core.sh" ]]; then
                    "$BASE/install-core.sh" "$core" || warn "install-core.sh failed for $core"
                else
                    warn "install-core.sh not found in bundle"
                fi
            else
                info "Skipped $core install — $esde_sys games will not launch until you install it"
            fi
            echo ""
        fi
    fi
}

IMPORT_SYSTEMS=0; IMPORT_MEDIA=0; IMPORT_ROMS=0

# Non-game folders to skip in the system loop (used by both dry-run + real import)
declare -A CONV_SKIP=( [media]=1 [bios]=1 [emulators]=1 [saves]=1
    [screenshots]=1 [cheats]=1 [records]=1 [sounds]=1 [decorations]=1
    [library]=1 [system]=1 [music]=1 )

# Yield system directories for a source path, one per line. A "collection"
# (RetroBat install or ROM pack) has a roms/ subfolder containing system
# subdirs. A "single-system folder" has no roms/ — the folder itself IS the
# system dir, named after the system (e.g. a bare dreamcast/ folder). Both
# the dry-run reporter and the real import loop go through this so all three
# documented input shapes behave identically.
enumerate_system_dirs() {
    local p="$1" d
    if [[ -d "$p/roms" ]]; then
        for d in "$p/roms"/*/; do
            [[ -d "$d" ]] && printf '%s\n' "$d"
        done
    else
        printf '%s\n' "$p"
    fi
}

# ── Dry-run reporter ──────────────────────────────────────────────────────
# Scans one source and reports what WOULD be imported. Reuses SYS_MAP /
# MEDIA_MAP / SYS_TO_EMU / SYS_TO_CORE / FLAT_ROM_SYSTEMS / CONV_SKIP and the
# is_*_installed helpers defined above. Copies / moves / writes NOTHING.
dry_run_report() {
    local path="$1"
    echo ""
    echo -e "${BOLD}${CYAN}═══ DRY RUN — $path ═══${NC}"
    echo ""

    if [[ -d "$path/roms" ]]; then
        info "Source type: collection (roms/ with system subfolders)"
    else
        info "Source type: single-system folder ('$(basename "$path")')"
    fi

    if [[ -d "$path/bios" ]]; then
        local bcount
        bcount=$(find "$path/bios" -type f 2>/dev/null | wc -l)
        info "BIOS: $bcount file(s) would be copied → ROMs/bios/"
    else
        info "BIOS: no bios/ folder in this source"
    fi
    echo ""

    local total_sys=0 total_roms=0 total_media=0
    local -a unknown_systems=() needs_install=() name_remaps=()

    while IFS= read -r SYS_DIR; do
        [[ -d "$SYS_DIR" ]] || continue
        local RB_SYS ESDE_SYS
        RB_SYS=$(basename "$SYS_DIR")
        [[ -n "${CONV_SKIP[$RB_SYS]:-}" ]] && continue
        ESDE_SYS="${SYS_MAP[$RB_SYS]:-$RB_SYS}"
        total_sys=$((total_sys + 1))
        [[ "$RB_SYS" != "$ESDE_SYS" ]] && name_remaps+=("$RB_SYS → $ESDE_SYS")

        # ROM count — mirror the import loop's flat-vs-nested decision
        local IS_FLAT=false fs
        for fs in "${FLAT_ROM_SYSTEMS[@]}"; do
            [[ "$ESDE_SYS" == "$fs" || "$RB_SYS" == "$fs" ]] && IS_FLAT=true && break
        done
        local rom_count subdir_count
        rom_count=$(find "$SYS_DIR" -maxdepth 1 -type f \
            ! -name 'gamelist*' ! -name '*.txt' ! -name '*.xml' ! -name '_*' 2>/dev/null | wc -l)
        # Subfolder count excludes media-type dirs (images/videos/manuals/media)
        # so it reflects only genuine ROM subfolders (e.g. multi-disc, m3u sets).
        subdir_count=$(find "$SYS_DIR" -maxdepth 1 -mindepth 1 -type d \
            ! -name media ! -name images ! -name videos ! -name manuals 2>/dev/null | wc -l)
        total_roms=$((total_roms + rom_count))

        local arrow=""
        [[ "$RB_SYS" != "$ESDE_SYS" ]] && arrow=" ${YELLOW}→ $ESDE_SYS${NC}"
        echo -e "  ${CYAN}${RB_SYS}${NC}${arrow}"
        echo "     ROMs:     $rom_count top-level file(s)$([ "$subdir_count" -gt 0 ] && echo ", $subdir_count subfolder(s)")$([ "$IS_FLAT" == true ] && echo "  [flat-system rules]")"

        # Media layout detection
        local media_note="none detected"
        if [[ -d "$SYS_DIR/media" ]]; then
            local mtypes=0 t
            for t in "${!MEDIA_MAP[@]}"; do
                [[ -d "$SYS_DIR/media/$t" ]] && mtypes=$((mtypes + 1))
            done
            media_note="RetroBat layout — $mtypes media type folder(s)"
            total_media=$((total_media + mtypes))
        elif [[ -d "$SYS_DIR/images" || -d "$SYS_DIR/videos" || -d "$SYS_DIR/manuals" ]]; then
            media_note="ES/Batocera layout (images/ videos/ manuals/)"
            total_media=$((total_media + 1))
        fi
        echo "     Media:    $media_note"

        # Gamelist
        if [[ -f "$SYS_DIR/gamelist.xml" ]]; then
            local gcount
            # Match <game> / <game ...> but NOT the <gameList> container
            gcount=$(grep -oE '<game[ >]' "$SYS_DIR/gamelist.xml" 2>/dev/null | wc -l)
            echo "     Gamelist: present — ~$gcount game entr$([ "$gcount" = 1 ] && echo y || echo ies) (merged, not clobbered)"
        else
            echo "     Gamelist: none — ROMs import without metadata"
        fi

        # vpinball: PinMAME ROMs live OUTSIDE roms/ (under emulators/.../VPinMAME)
        # — report whether the pack ships them, since solid-state/DMD tables
        # can't run without them.
        if [[ "$ESDE_SYS" == "vpinball" ]]; then
            local vpm
            vpm=$(find "$path" -type d -iname VPinMAME -print -quit 2>/dev/null)
            if [[ -n "$vpm" && -d "$vpm/roms" ]]; then
                local vpmn vproot
                vpmn=$(find "$vpm/roms" -maxdepth 1 -type f -name '*.zip' 2>/dev/null | wc -l)
                echo "     PinMAME:  $vpmn ROM zip(s) in VPinMAME/ → would import to pinmame/roms/"
                vproot=$(dirname "$vpm")
                if [[ -d "$vproot/Music" ]]; then
                    local mn
                    mn=$(find "$vproot/Music" -type f 2>/dev/null | wc -l)
                    echo "     Music:    $mn file(s) in Music/ → would import to Emulators/Music/"
                fi
                local vpscr="$vproot/Scripts"
                [[ ! -d "$vpscr" ]] && vpscr="$vpm/Scripts"
                if [[ -d "$vpscr" ]]; then
                    local sn
                    sn=$(find "$vpscr" -maxdepth 1 -type f -iname '*.vbs' 2>/dev/null | wc -l)
                    echo "     Scripts:  $sn .vbs library file(s) → would import to ROMs/vpinball/"
                fi
            else
                echo -e "     PinMAME:  ${YELLOW}no VPinMAME folder — solid-state/DMD tables won't run without ROMs${NC}"
            fi
        fi

        # Emulator / core need
        local emu core
        emu="${SYS_TO_EMU[$ESDE_SYS]:-}"
        core="${SYS_TO_CORE[$ESDE_SYS]:-}"
        if [[ -n "$emu" ]]; then
            if is_emulator_installed "$emu"; then
                echo -e "     Launches: $emu ${GREEN}(installed)${NC}"
            else
                echo -e "     Launches: $emu ${YELLOW}(NOT installed — would prompt to install)${NC}"
                needs_install+=("$ESDE_SYS → $emu (standalone)")
            fi
        elif [[ -n "$core" ]]; then
            if is_core_installed "$core"; then
                echo -e "     Launches: RetroArch / $core ${GREEN}(installed)${NC}"
            else
                echo -e "     Launches: RetroArch / $core ${YELLOW}(NOT installed — would prompt)${NC}"
                needs_install+=("$ESDE_SYS → $core (libretro core)")
            fi
        else
            echo -e "     Launches: ${YELLOW}⚠ no emulator/core mapping for '$ESDE_SYS'${NC}"
            unknown_systems+=("$RB_SYS$([ "$RB_SYS" != "$ESDE_SYS" ] && echo " (→ $ESDE_SYS)")")
        fi
        echo ""
    done < <(enumerate_system_dirs "$path")

    echo -e "${BOLD}── Summary: $path ──${NC}"
    echo "  Systems detected:     $total_sys"
    echo "  ROMs (top-level):     ~$total_roms file(s)"
    echo "  Media type/layouts:   $total_media hit(s)"
    if [[ ${#name_remaps[@]} -gt 0 ]]; then
        echo ""
        info "System-name remaps that would be applied:"
        local r; for r in "${name_remaps[@]}"; do echo "     $r"; done
    fi
    if [[ ${#needs_install[@]} -gt 0 ]]; then
        echo ""
        warn "Would prompt to install ${#needs_install[@]} emulator(s)/core(s):"
        local n; for n in "${needs_install[@]}"; do echo "     - $n"; done
    fi
    if [[ ${#unknown_systems[@]} -gt 0 ]]; then
        echo ""
        warn "Unrecognized system(s) — will import as ROMs but have NO launch command:"
        local u; for u in "${unknown_systems[@]}"; do echo "     - $u"; done
        echo "     (Fix: add a mapping to SYS_TO_EMU or SYS_TO_CORE, or rename the folder.)"
    fi
    echo ""
    return 0
}

if $DRY_RUN; then
    for RETROBAT_PATH in "${RETROBAT_PATHS[@]}"; do
        dry_run_report "$RETROBAT_PATH"
    done
    # BIOS verification is read-only — safe to run in dry-run for a real report
    if [[ -x "$BASE/verify-bios.sh" ]]; then
        echo -e "${CYAN}── BIOS status (read-only check) ──${NC}"
        "$BASE/verify-bios.sh" || true
        echo ""
    fi
    ok "Dry run complete — nothing was copied, moved, or modified."
    echo "   Re-run without --dry-run to perform the actual import."
    exit 0
fi

for RETROBAT_PATH in "${RETROBAT_PATHS[@]}"; do
    info "Importing from: $RETROBAT_PATH"
    if [[ -d "$RETROBAT_PATH/bios" ]]; then
        echo -n "   BIOS files → ROMs/bios/ [copying...]"
        cp -rn "$RETROBAT_PATH/bios/." "$ROMS/bios/" 2>/dev/null || true
        echo -e " ${GREEN}done${NC}"
    fi

    while IFS= read -r SYS_DIR; do
        [[ -d "$SYS_DIR" ]] || continue
        RB_SYS=$(basename "$SYS_DIR")
        [[ -n "${CONV_SKIP[$RB_SYS]:-}" ]] && continue
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
        else
            # Non-RetroBat layouts. Two shapes are common:
            #   (a) ES/Batocera-style with suffixes — images/<rom>-image.png,
            #       images/<rom>-thumb.png, videos/<rom>-Video.mp4
            #   (b) Simple flat with media subfolders directly in ROM dir
            es_detected=0
            [[ -d "$SYS_DIR/images" ]] && try_import_es_layout "$SYS_DIR/images" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" && es_detected=1
            [[ -d "$SYS_DIR/videos" ]] && try_import_es_layout "$SYS_DIR/videos" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" && es_detected=1
            [[ -d "$SYS_DIR/manuals" ]] && try_import_es_layout "$SYS_DIR/manuals" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" && es_detected=1
            (( es_detected )) && IMPORT_MEDIA=$((IMPORT_MEDIA + 1))
            if (( ! es_detected )); then
            for RB_TYPE in "${!MEDIA_MAP[@]}"; do
                SRC="$SYS_DIR/$RB_TYPE"
                if [[ -d "$SRC" ]]; then
                    ESDE_TYPE="${MEDIA_MAP[$RB_TYPE]}"
                    DST="$ESDE_MEDIA_DIR/$ESDE_TYPE"
                    mkdir -p "$DST"
                    [[ "$RB_TYPE" == "videos" ]] \
                        && echo "      videos (flat) → videos [copying — large sets take time...]" \
                        || echo -n "      $(printf '%-14s' "$RB_TYPE") (flat) → $(printf '%-10s' "$ESDE_TYPE") [copying...]"
                    cp -rn "$SRC/." "$DST/" 2>/dev/null || true
                    [[ "$RB_TYPE" == "videos" ]] \
                        && echo -e "      ${GREEN}✓${NC} videos done" \
                        || echo -e " ${GREEN}done${NC}"
                    IMPORT_MEDIA=$((IMPORT_MEDIA + 1))
                fi
            done
            fi  # close: if (( ! es_detected ))
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
existing_alt_emu = ''
if os.path.exists(dst):
    with open(dst,'r',encoding='utf-8',errors='replace') as f:
        dst_content = f.read()
    for line in dst_content.splitlines():
        m = re.search(r'<path>([^<]+)</path>', line)
        if m: existing_paths.add(m.group(1).strip())
    alt_match = re.search(r'<alternativeEmulator>.*?</alternativeEmulator>', dst_content, re.DOTALL)
    if alt_match:
        existing_alt_emu = alt_match.group(0).rstrip() + '\n'
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
if not new_games:
    if existing_alt_emu and not existing_paths:
        with open(dst,'w',encoding='utf-8') as f:
            f.write('<?xml version="1.0"?>\n')
            f.write(existing_alt_emu)
            f.write('<gameList>\n</gameList>\n')
    sys.exit(0)
if os.path.exists(dst) and existing_paths:
    with open(dst,'r',encoding='utf-8',errors='replace') as f: content = f.read()
    content = content.replace('</gameList>', '\n'.join(new_games) + '\n</gameList>')
    if existing_alt_emu:
        content = re.sub(r'\s*<alternativeEmulator>.*?</alternativeEmulator>\s*', '\n', content, flags=re.DOTALL)
        content = re.sub(r'(<gameList[\s>])', existing_alt_emu + r'\1', content, count=1)
    with open(dst,'w',encoding='utf-8') as f: f.write(content)
else:
    with open(dst,'w',encoding='utf-8') as f:
        f.write('<?xml version="1.0"?>\n')
        if existing_alt_emu: f.write(existing_alt_emu)
        f.write('<gameList>\n')
        f.writelines(new_games)
        f.write('</gameList>\n')
GLFIX
        fi
        IS_FLAT=false
        for FS in "${FLAT_ROM_SYSTEMS[@]}"; do
            [[ "$ESDE_SYS" == "$FS" || "$RB_SYS" == "$FS" ]] && IS_FLAT=true && break
        done
        TRANSFER_LABEL="$([[ "$RETROBAT_MOVE" == "yes" ]] && echo "moving" || echo "copying")"
        echo -n "      ROMs [$TRANSFER_LABEL...]"
        COPIED=0; SEEN=0
        if [[ "$IS_FLAT" == "true" ]]; then
            while IFS= read -r -d '' ROM; do
                BASENAME=$(basename "$ROM")
                [[ "$BASENAME" == _* || "$BASENAME" == "gamelist"* || "$BASENAME" == *.txt || "$BASENAME" == *.xml ]] && continue
                SEEN=$((SEEN + 1))
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    mv -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                else
                    cp -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                fi
                # Progress ping every 50 files so large packs don't look frozen
                (( SEEN % 50 == 0 )) && echo -n " ${SEEN}..."
            done < <(find "$SYS_DIR" -not -path "*/media/*" -type f -print0)
        else
            while IFS= read -r -d '' SUBDIR; do
                DIRNAME=$(basename "$SUBDIR")
                # Skip RetroBat media/ AND ES/Batocera images/ videos/ manuals/
                # so media folders aren't copied into the ROM directory.
                case "$DIRNAME" in media|images|videos|manuals) continue ;; esac
                echo ""; echo -n "        $DIRNAME [$TRANSFER_LABEL...]"
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    mv -n "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || cp -rn "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || true
                else
                    cp -rn "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || true
                fi
                echo -e " ${GREEN}done${NC}"; COPIED=$((COPIED + 1))
            done < <(find "$SYS_DIR" -maxdepth 1 -mindepth 1 -type d -print0)
            while IFS= read -r -d '' ROM; do
                BASENAME=$(basename "$ROM")
                [[ "$BASENAME" == _* || "$BASENAME" == "gamelist"* || "$BASENAME" == *.txt ]] && continue
                SEEN=$((SEEN + 1))
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    mv -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                else
                    cp -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                fi
                (( SEEN % 50 == 0 )) && echo -n " ${SEEN}..."
            done < <(find "$SYS_DIR" -maxdepth 1 -type f -print0)
        fi
        [[ $COPIED -gt 0 ]] && echo -e " ${GREEN}done ($COPIED items)${NC}" || echo ""
        IMPORT_ROMS=$((IMPORT_ROMS + COPIED))
        # RetroBat-style vpinball packs ship the PinMAME ROMs (the actual
        # machine ROMs that drive solid-state / DMD tables) under
        # emulators/<...>/VPinMAME/, which the system loop never visits because
        # emulators/ is skipped. Without these, ROM-based tables load visually
        # but can't run their game logic. Harvest them into the bundle's
        # pinmame/ folder, which VPinball Standalone auto-detects next to the
        # .vpx files.
        if [[ "$ESDE_SYS" == "vpinball" ]]; then
            VPM=$(find "$RETROBAT_PATH" -type d -iname VPinMAME -print -quit 2>/dev/null)
            if [[ -n "$VPM" && -d "$VPM" ]]; then
                echo "      PinMAME content found in $(basename "$(dirname "$VPM")")/VPinMAME/"
                for VSUB in roms nvram altcolor altsound cfg samples; do
                    [[ -d "$VPM/$VSUB" ]] || continue
                    mkdir -p "$ROMS/vpinball/pinmame/$VSUB"
                    echo -n "        pinmame/$VSUB ..."
                    cp -rn "$VPM/$VSUB/." "$ROMS/vpinball/pinmame/$VSUB/" 2>/dev/null || true
                    echo -e " ${GREEN}$(find "$ROMS/vpinball/pinmame/$VSUB" -maxdepth 1 -type f 2>/dev/null | wc -l) files${NC}"
                done
                # VPROOT = emulators/vpinball/ — Music/ and Scripts/ sit beside
                # VPinMAME/. Music: classic VPinball keeps one Music/ folder next
                # to the VPX binary (Emulators/), tables PlayMusic against it.
                # Scripts: the core.vbs / manufacturer .vbs library — tables do
                # GetTextFile("core.vbs"), resolved relative to the table dir,
                # so the library belongs in ROMs/vpinball/ alongside the .vpx.
                VPROOT=$(dirname "$VPM")
                if [[ -d "$VPROOT/Music" ]]; then
                    mkdir -p "$BASE/Emulators/Music"
                    echo -n "        Emulators/Music ..."
                    cp -rn "$VPROOT/Music/." "$BASE/Emulators/Music/" 2>/dev/null || true
                    echo -e " ${GREEN}$(find "$BASE/Emulators/Music" -type f 2>/dev/null | wc -l) files${NC}"
                fi
                VPSCR="$VPROOT/Scripts"
                [[ ! -d "$VPSCR" ]] && VPSCR="$VPM/Scripts"
                if [[ -d "$VPSCR" ]]; then
                    echo -n "        ROMs/vpinball/ (script library) ..."
                    SCRN=0
                    while IFS= read -r -d '' SVB; do
                        cp -n "$SVB" "$ROMS/vpinball/" 2>/dev/null && SCRN=$((SCRN + 1)) || true
                    done < <(find "$VPSCR" -maxdepth 1 -type f -iname '*.vbs' -print0 2>/dev/null)
                    echo -e " ${GREEN}$SCRN .vbs files${NC}"
                fi
            else
                warn "vpinball: no VPinMAME folder in source — PinMAME tables will need ROMs added to ROMs/vpinball/pinmame/roms/ manually"
            fi
            # Offer to fetch per-table Linux script patches. Some VPX tables
            # need a patched .vbs sidecar to run under Standalone; the fetcher
            # downloads any whose name exactly matches a patch in the repo.
            if [[ -x "$BASE/fetch-vpx-patches.sh" ]]; then
                if wt_yesno "Table script patches" \
"Some VPX tables need a patched script to run under VPinball Standalone.

Download available patches now from the jsm174/vpx-standalone-scripts
project? Matches tables by exact name, needs an internet connection, and
can be re-run anytime via ./fetch-vpx-patches.sh"; then
                    echo ""
                    "$BASE/fetch-vpx-patches.sh" || true
                    echo ""
                fi
            fi
        fi
        echo -e "      ${GREEN}✓ done${NC}"; echo ""
        # Detect missing emulator/core for this system; prompt + install if user agrees
        ensure_emulator_for "$ESDE_SYS"
        # Auto-verify BIOS for the system we just imported (if verifier present)
        if [[ -x "$BASE/verify-bios.sh" ]]; then
            "$BASE/verify-bios.sh" "$ESDE_SYS" || true
        fi
    done < <(enumerate_system_dirs "$RETROBAT_PATH")
    if [[ "$RETROBAT_MOVE" == "yes" ]]; then
        if [[ -d "$RETROBAT_PATH/roms" ]]; then
            rm -rf "$RETROBAT_PATH/roms" "$RETROBAT_PATH/bios" 2>/dev/null || true
        else
            # single-system folder — its ROMs were moved out; drop the now-empty dir
            rmdir "$RETROBAT_PATH" 2>/dev/null || true
        fi
        ok "Removed source files from $RETROBAT_PATH"
    fi
done
echo ""
ok "Import complete: $IMPORT_SYSTEMS systems, $IMPORT_MEDIA media types, $IMPORT_ROMS items"
echo ""
# Final summary BIOS sweep across everything in the bundle
if [[ -x "$BASE/verify-bios.sh" ]]; then
    echo -e "${CYAN}── Final BIOS sweep across all systems ──${NC}"
    "$BASE/verify-bios.sh" || true
fi
CONVSCRIPT

chmod +x "$BASE/import-collection.sh"
ok "import-collection.sh written to bundle"

#=============================================================================
# STEP 14: WRITE BIOS VERIFIER SCRIPT TO BUNDLE
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing verify-bios.sh to bundle..."

cat > "$BASE/verify-bios.sh" << 'VERIFYBIOSSCRIPT'
#!/usr/bin/env bash
#=============================================================================
# Portable ES-DE — BIOS Verifier
#
# Verifies BIOS files in $BASE/ROMs/bios against a known-good table.
# Reports PASS / WARN / FAIL per system with confidence indication.
#
# Hashes sourced from emulator source code, Redump, No-Intro, libretro docs,
# and the Abdess/retrobios database (MIT-licensed, source-verified).
#
# Usage:
#   ./verify-bios.sh                # verify all systems present in ROMs/
#   ./verify-bios.sh <system>       # verify just one ES-DE system
#   ./verify-bios.sh --list         # list systems we have BIOS data for
#   ./verify-bios.sh --table        # dump the entire BIOS table
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
ROMS="$BASE/ROMs"
BIOS_DIR="$ROMS/bios"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

#=============================================================================
# BIOS Table
#
# Format: system|file|req|conf|md5_list|description
#   req:    REQ | REQ_ANY:<group> | OPT | OPT_BOOT
#   conf:   HIGH (Redump/source-code) | MED (libretro docs/wiki) | LOW (filename only)
#   md5:    comma-separated lowercase MD5s, or "-" for filename-only check
#=============================================================================

declare -a BIOS_TABLE=(
    # ── Sony PlayStation (psx) — Beetle PSX / Beetle PSX HW / PCSX-ReARMed ──
    "psx|scph5500.bin|REQ_ANY:region|HIGH|8dd7d5296a650fac7319bce665a6a53c|PS1 BIOS Japan v3.0 (SCPH-5500)"
    "psx|scph5501.bin|REQ_ANY:region|HIGH|490f666e1afb15b7362b406ed1cea246|PS1 BIOS USA v3.0 (SCPH-5501)"
    "psx|scph5502.bin|REQ_ANY:region|HIGH|32736f17079d0b2b7024407c39bd3050|PS1 BIOS Europe v3.0 (SCPH-5502)"
    "psx|scph7001.bin|REQ_ANY:region|HIGH|1e68c231d0896b7eadcad1d7d8e76129|PS1 BIOS USA v4.1 (SCPH-7001)"
    "psx|scph7003.bin|REQ_ANY:region|HIGH|490f666e1afb15b7362b406ed1cea246|PS1 BIOS USA v4.1 alt (SCPH-7003)"
    "psx|scph101.bin|REQ_ANY:region|HIGH|6e3735ff4c7dc899ee98981385f6f3d0|PSone BIOS USA v4.4 (SCPH-101)"

    # ── Sony PlayStation 2 (ps2) — PCSX2 ──
    "ps2|ps2-0230a-20080220.bin|REQ_ANY:region|MED|9b0fcab1ee9e74c20efde6aebd96e80b|PS2 BIOS USA v2.30"
    "ps2|ps2-0220a-20060905.bin|REQ_ANY:region|MED|9c0d3dcdde9b1e4ac3f08fa1f3a36f0e|PS2 BIOS USA v2.20"
    "ps2|ps2-0190a-20030822.bin|REQ_ANY:region|LOW|-|PS2 BIOS USA v1.90 (filename only)"
    "ps2|SCPH-70012_BIOS_V12_USA_200.BIN|REQ_ANY:region|LOW|-|PS2 BIOS slim USA"
    "ps2|SCPH-77001_BIOS_V14_USA_220.BIN|REQ_ANY:region|LOW|-|PS2 BIOS slim USA (alt)"

    # ── Sega Saturn (saturn, saturnjp) — Beetle Saturn ──
    "saturn|sega_101.bin|REQ_ANY:region|HIGH|85ec9ca47d8f6807718151cbcca8b964|Saturn BIOS NTSC-J"
    "saturn|mpr-17933.bin|REQ_ANY:region|HIGH|3240872c70984b6cbfda1586cab68dbe|Saturn BIOS NTSC-U/PAL"
    "saturnjp|sega_101.bin|REQ_ANY:region|HIGH|85ec9ca47d8f6807718151cbcca8b964|Saturn BIOS NTSC-J"
    "saturnjp|mpr-17933.bin|REQ_ANY:region|HIGH|3240872c70984b6cbfda1586cab68dbe|Saturn BIOS NTSC-U/PAL (fallback)"

    # ── Sega CD / Mega-CD (segacd, megacd) — Genesis Plus GX / Picodrive ──
    "segacd|bios_CD_J.bin|REQ_ANY:region|HIGH|278a9397d192149e84e820ac621a8edd|Sega CD BIOS Japan"
    "segacd|bios_CD_U.bin|REQ_ANY:region|HIGH|2efd74e3232ff260e371b99f84024f7f|Sega CD BIOS USA"
    "segacd|bios_CD_E.bin|REQ_ANY:region|HIGH|e66fa1dc5820d254611fdcdba0662372|Mega-CD BIOS Europe"
    "megacd|bios_CD_J.bin|REQ_ANY:region|HIGH|278a9397d192149e84e820ac621a8edd|Mega-CD BIOS Japan"
    "megacd|bios_CD_U.bin|REQ_ANY:region|HIGH|2efd74e3232ff260e371b99f84024f7f|Sega CD BIOS USA"
    "megacd|bios_CD_E.bin|REQ_ANY:region|HIGH|e66fa1dc5820d254611fdcdba0662372|Mega-CD BIOS Europe"

    # ── Sega 32X (sega32x) ──
    # picodrive (the libretro core for 32X in this bundle) does NOT require
    # 32X_G_BIOS.BIN / 32X_M_BIOS.BIN / 32X_S_BIOS.BIN. Those are needed only
    # by Gens / Fusion. No BIOS table entries for sega32x intentionally.

    # ── Sega Dreamcast (dreamcast, atomiswave, naomi, naomi2) — Flycast ──
    # Flycast has built-in HLE BIOS (reios) for Dreamcast — dc_boot.bin and
    # dc_flash.bin are recommended (date/time, accuracy) but not mandatory.
    "dreamcast|dc_boot.bin|OPT_BOOT|HIGH|e10c53c2f8b90bab96ead2d368858623|Dreamcast Boot ROM (HLE fallback exists)"
    "dreamcast|dc_flash.bin|OPT|HIGH|0a93f7940c455905bea6e392dfde92a4|Dreamcast Flash ROM (date/time + region)"
    "atomiswave|awbios.zip|REQ|HIGH|0ec5ae5b5a5c4959fa8b43fcf8687f7c|Atomiswave BIOS (MAME-style zip)"
    "naomi|naomi.zip|REQ|HIGH|eb4099aeb42ef089cfe94f8fe95e51f6|NAOMI BIOS set (MAME-style zip)"
    "naomi|hod2bios.zip|OPT|HIGH|9c755171b222fb1f4e1439d5b709dbf1|NAOMI House of the Dead 2 BIOS (specific game)"
    "naomi|f355bios.zip|OPT|HIGH|f126d318f135f38ee377fef2acf08d7e|NAOMI F355 Challenge BIOS (specific game)"
    "naomi|f355dlx.zip|OPT|HIGH|5e83867c751f692a000afdf658dc181f|NAOMI F355 Challenge DX BIOS (specific game)"
    "naomi|airlbios.zip|OPT|HIGH|3f348c88af99a40fbd11fa435f28c69d|NAOMI Airline Pilots BIOS (specific game)"
    "naomi2|naomi2.zip|REQ|MED|-|NAOMI 2 BIOS set (zip, treated as NAOMI by libretro flycast)"

    # ── SNK Neo Geo CD (neogeocd) — NeoCD core ──
    "neogeocd|neocd_z.rom|REQ_ANY:model|HIGH|e7dac420ea7e6fbd4dc1fafef3a05bf2|Neo Geo CDZ BIOS (top-loader)"
    "neogeocd|neocd_t.rom|REQ_ANY:model|MED|-|Neo Geo CD top-loader BIOS"
    "neogeocd|neocd_f.rom|REQ_ANY:model|MED|-|Neo Geo CD front-loader BIOS"

    # ── SNK Neo Geo MVS/AES (neogeo) — FBNeo / MAME ──
    "neogeo|neogeo.zip|REQ|HIGH|-|Neo Geo BIOS set (MAME-style zip, hash varies by version)"

    # ── NEC PC-FX (pcfx) — Beetle PC-FX ──
    "pcfx|pcfx.rom|REQ|HIGH|e73d2c1f95975e3f06f4c1f7e4dc60d2|PC-FX BIOS"

    # ── NEC TurboGrafx-CD / PC Engine CD (tg-cd, pcenginecd) — Beetle PCE / PCE Fast ──
    "tg-cd|syscard3.pce|REQ|HIGH|38179df8f4ac870017db21ebcbf53114|TurboGrafx-CD System Card 3.0"
    "tg-cd|syscard2.pce|OPT|MED|f3e6d4d34c00b53eb6cd9e1eef6ea21f|TG-CD System Card 2.0 (older games)"
    "tg-cd|syscard1.pce|OPT|MED|-|TG-CD System Card 1.0 (older games)"
    "pcenginecd|syscard3.pce|REQ|HIGH|38179df8f4ac870017db21ebcbf53114|PC Engine CD System Card 3.0"

    # ── Atari Lynx (atarilynx) — Handy ──
    "atarilynx|lynxboot.img|REQ|HIGH|fcd403db69f54290b51035d82f835e7b|Atari Lynx Boot ROM"

    # ── Atari 5200 (atari5200) — a5200 core ──
    "atari5200|5200.rom|REQ|HIGH|281f20ea4320404ec820fb7ec0693b38|Atari 5200 BIOS"

    # ── Atari 7800 (atari7800) — ProSystem ──
    "atari7800|7800 BIOS (U).rom|OPT_BOOT|MED|0763f1ffb006ddbe32e52d497ee848ae|Atari 7800 BIOS USA (boot screen)"
    "atari7800|7800 BIOS (E).rom|OPT_BOOT|MED|397bb566584be7b9764e7a68974c4263|Atari 7800 BIOS Europe (boot screen)"

    # ── Atari Jaguar CD (jaguarcd) — Virtual Jaguar ──
    "jaguarcd|jagcd.rom|REQ|MED|-|Jaguar CD boot ROM"

    # ── 3DO (3do) — Opera core ──
    "3do|panafz1.bin|REQ_ANY:model|HIGH|f47264dd47fe30f73ab3c010015c155b|3DO Panasonic FZ-1 BIOS"
    "3do|panafz10.bin|REQ_ANY:model|HIGH|51f2f43ae2f3508a14d9f56597e2d3ce|3DO Panasonic FZ-10 BIOS"
    "3do|sanyotry.bin|REQ_ANY:model|MED|-|3DO Sanyo Try BIOS"
    "3do|goldstar.bin|REQ_ANY:model|MED|-|3DO Goldstar GDO-101 BIOS"

    # ── ColecoVision (colecovision) — blueMSX / Gearcoleco ──
    "colecovision|colecovision.rom|REQ|HIGH|2c66f5911e5b42b8ebe113403548eee7|ColecoVision BIOS"

    # ── Intellivision (intellivision) — FreeIntv ──
    "intellivision|exec.bin|REQ|HIGH|62e761035cb657903761800f4437b8af|Intellivision Executive ROM"
    "intellivision|grom.bin|REQ|HIGH|0cd5946c6473e42e8e4c2137785e427f|Intellivision Graphics ROM"

    # ── Commodore Amiga (amiga500, amiga1200, amigacd32) — PUAE ──
    "amiga500|kick34005.A500|REQ_ANY:revision|HIGH|82a21c1890cae844b3df741f2762d48d|Amiga Kickstart 1.3 (A500)"
    "amiga500|kick40063.A500|REQ_ANY:revision|HIGH|59886e09c0c61b9e6e6e74b95a40fb33|Amiga Kickstart 3.1 (A500)"
    "amiga1200|kick40068.A1200|REQ|HIGH|646773759326fbac3b2311fd8c8793ee|Amiga Kickstart 3.1 (A1200)"
    "amigacd32|kick40060.CD32|REQ|HIGH|5f8924d013dd57a89cf349f4cdedc6b1|CD32 Kickstart"
    "amigacd32|kick40060.CD32.ext|REQ|HIGH|bb72565701b1b6faece07d68ea5da639|CD32 extended ROM"

    # ── Atari ST (atarist) — Hatari ──
    "atarist|tos.img|REQ|MED|-|Atari ST TOS image (typically TOS 1.04 or 2.06)"

    # ── Amstrad CPC / GX4000 (amstradcpc, amstradgx4000) — Caprice32 ──
    "amstradcpc|cpc6128.rom|REQ_ANY:model|MED|-|Amstrad CPC 6128 OS+BASIC"
    "amstradcpc|cpc664.rom|REQ_ANY:model|MED|-|Amstrad CPC 664 OS+BASIC"
    "amstradcpc|cpc464.rom|REQ_ANY:model|MED|-|Amstrad CPC 464 OS+BASIC"

    # ── Sharp X68000 (x68000) — PX68k ──
    "x68000|iplrom.dat|REQ|MED|-|X68000 IPL ROM"
    "x68000|cgrom.dat|REQ|MED|-|X68000 Character Generator ROM"

    # ── Sharp X1 (x1) — X Millennium ──
    "x1|ipl.x1|REQ|LOW|-|X1 IPL ROM"

    # ── NEC PC-98 (pc98) — Neko Project II Kai ──
    "pc98|bios.rom|REQ|MED|-|PC-98 BIOS"
    "pc98|font.rom|REQ|MED|-|PC-98 font ROM"

    # ── MSX / MSX2 (msx, msx2, msxturbor) — blueMSX ──
    "msx|MSX.ROM|REQ_ANY:variant|MED|-|MSX system ROM"
    "msx|MSXJ.ROM|REQ_ANY:variant|LOW|-|MSX Japanese system ROM"
    "msx2|MSX2.ROM|REQ_ANY:variant|MED|-|MSX2 system ROM"
    "msx2|MSX2EXT.ROM|REQ|MED|-|MSX2 extended ROM"
    "msxturbor|MSX2P.ROM|REQ|MED|-|MSX2+ system ROM"
    "msxturbor|MSX2PEXT.ROM|REQ|MED|-|MSX2+ extended ROM"

    # ── BBC Micro (bbcmicro) — B-em (if used) ──
    "bbcmicro|os12.rom|REQ|LOW|-|BBC Micro OS 1.20"
    "bbcmicro|basic2.rom|REQ|LOW|-|BBC BASIC 2"

    # ── Spectravideo (spectravideo) — blueMSX ──
    "spectravideo|SVI.ROM|REQ|LOW|-|Spectravideo SV-318/328 system ROM"

    # ── Dragon 32 / 64 (dragon32) — MAME standalone ──
    "dragon32|dragon32.zip|REQ|MED|-|Dragon 32 BIOS (MAME-style zip)"

    # ── Coleco Adam (adam) — MAME standalone ──
    "adam|adam.zip|REQ|MED|-|Coleco Adam BIOS (MAME-style zip)"

    # ── Fujitsu FM-7 (fm7) — MAME standalone ──
    "fm7|fm7.zip|REQ|MED|-|FM-7 BIOS (MAME-style zip)"

    # ── Texas Instruments TI-99/4A (ti99) — MAME standalone ──
    "ti99|ti99_4a.zip|REQ|MED|-|TI-99/4A BIOS (MAME-style zip)"

    # ── Acorn Archimedes (archimedes) — MAME standalone ──
    "archimedes|aa310.zip|REQ|HIGH|-|Archimedes A310 BIOS (Arthur ROMs + RISC OS, MAME-style zip)"

    # ── Apple IIgs (apple2gs) — MAME standalone ──
    "apple2gs|apple2gs.zip|REQ|HIGH|-|Apple IIgs ROM03 BIOS (MAME-style zip)"

    # ── Funtech Super A'Can (supracan) — MAME standalone ──
    "supracan|supracan.zip|OPT|LOW|-|Super A'Can BIOS (optional, MAME-style zip)"

    # ── Epoch Super Cassette Vision (scv) — MAME standalone ──
    "scv|scv.zip|OPT|LOW|-|Super Cassette Vision BIOS (optional, MAME-style zip)"

    # ── Casio PV-1000 (pv1000) — MAME standalone ──
    "pv1000|pv1000.zip|OPT|LOW|-|PV-1000 BIOS (optional, MAME-style zip)"

    # ── Nintendo Famicom Disk System / NES disk addon ──
    "nes|disksys.rom|OPT|HIGH|ca30b50f880eb660a320674ed365ef7a|FDS BIOS (required only for .fds games)"
    "famicom|disksys.rom|OPT|HIGH|ca30b50f880eb660a320674ed365ef7a|FDS BIOS (required only for .fds games)"

    # ── Nintendo Game Boy Advance (gba) ──
    "gba|gba_bios.bin|OPT_BOOT|HIGH|a860e8c0b6d573d191e4ec7db1b1e4f6|GBA BIOS (boot logo + some games)"

    # ── Nintendo 64DD (n64dd) ──
    "n64dd|64DD_IPL.bin|REQ|MED|-|N64DD IPL ROM (required for 64DD emulation)"

    # ── ZX Spectrum (zxspectrum) — Fuse ──
    "zxspectrum|48.rom|OPT|MED|0e0e6c11c5fb443f6c2a0fde11feb0eb|ZX Spectrum 48K ROM"
    "zxspectrum|128-0.rom|OPT|MED|3a5d8e08bda1a76e2872d3a31fae3b04|ZX Spectrum 128K ROM 0"
    "zxspectrum|128-1.rom|OPT|MED|7c2b66c33d8b8be2a6b934d5cd5b0a8a|ZX Spectrum 128K ROM 1"
)

#=============================================================================
# ES-DE system name → BIOS table key mapping
# (some ES-DE names need normalization to our table keys; empty = no BIOS data)
#=============================================================================
declare -A ESDE_TO_BIOSKEY=(
    [megadrive]=""           # no BIOS needed for cart Genesis
    [megadrivejp]=""
    [genesis]=""
    [mastersystem]=""
    [gamegear]=""
    [snes]=""                # SNES BIOS optional/cart-only
    [sfc]=""
    [snesh]=""
    [sgb]=""
    [gb]=""
    [gbh]=""
    [gbc]=""
    [gbch]=""
    [gba]=gba
    [gbah]=gba
    [nes]=nes
    [nesh]=nes
    [famicom]=famicom
    [n64]=""
    [n64h]=""
    [n64dd]=n64dd
    [psx]=psx
    [ps2]=ps2
    [saturn]=saturn
    [saturnjp]=saturnjp
    [segacd]=segacd
    [megacd]=megacd
    [megacdjp]=megacd
    [sega32x]=""             # picodrive HLE — no BIOS required
    [dreamcast]=dreamcast
    [atomiswave]=atomiswave
    [naomi]=naomi
    [naomi2]=naomi2
    [neogeocd]=neogeocd
    [neogeo]=neogeo
    [pcfx]=pcfx
    [tg-cd]=tg-cd
    [pcenginecd]=pcenginecd
    [atarilynx]=atarilynx
    [lynx]=atarilynx
    [atari5200]=atari5200
    [atari7800]=atari7800
    [jaguarcd]=jaguarcd
    [3do]=3do
    [colecovision]=colecovision
    [intellivision]=intellivision
    [amiga500]=amiga500
    [amiga1200]=amiga1200
    [amigacd32]=amigacd32
    [atarist]=atarist
    [amstradcpc]=amstradcpc
    [x68000]=x68000
    [x1]=x1
    [pc98]=pc98
    [msx]=msx
    [msx1]=msx
    [msx2]=msx2
    [msxturbor]=msxturbor
    [bbcmicro]=bbcmicro
    [spectravideo]=spectravideo
    [dragon32]=dragon32
    [adam]=adam
    [fm7]=fm7
    [ti99]=ti99
    [archimedes]=archimedes
    [apple2gs]=apple2gs
    [supracan]=supracan
    [scv]=scv
    [pv1000]=pv1000
    [zxspectrum]=zxspectrum
    [zx81]=""
    [c64]=""
    [vic20]=""
    [plus4]=""
    [dos]=""
    [pico8]=""
    [vpinball]=""
    [arcade]=""
    [mame]=""
    [model2]=""
    [model3]=""
    [cps1]=""
    [cps2]=""
    [cps3]=""
)

#=============================================================================
# Helper functions
#=============================================================================

md5_of() {
    [[ -f "$1" ]] || { echo ""; return; }
    md5sum "$1" 2>/dev/null | awk '{print tolower($1)}'
}

list_table_systems() {
    local seen=""
    for entry in "${BIOS_TABLE[@]}"; do
        local sys="${entry%%|*}"
        [[ ",$seen," == *",$sys,"* ]] && continue
        seen="$seen,$sys"
        echo "$sys"
    done | sort -u
}

conf_color() {
    case "$1" in
        HIGH) echo -e "${GREEN}HIGH${NC}" ;;
        MED)  echo -e "${YELLOW}MED${NC}" ;;
        LOW)  echo -e "${DIM}LOW${NC}" ;;
        *)    echo -e "${DIM}?${NC}" ;;
    esac
}

# args: file_relative_to_bios_dir, expected_md5_list (comma-sep, "-" for skip)
# stdout: "OK_HASH" | "OK_NOHASH" | "MISSING" | "WRONG_HASH:<observed_md5>"
verify_entry() {
    local file="$1"
    local expected="$2"
    local path="$BIOS_DIR/$file"
    [[ ! -f "$path" ]] && { echo "MISSING"; return; }
    if [[ "$expected" == "-" || -z "$expected" ]]; then
        echo "OK_NOHASH"
        return
    fi
    local actual
    actual=$(md5_of "$path")
    local IFS=','
    for h in $expected; do
        [[ "$actual" == "$h" ]] && { echo "OK_HASH"; return; }
    done
    echo "WRONG_HASH:$actual"
}

# Returns: 0=pass, 1=warn, 2=fail
verify_system() {
    local system="$1"
    local mapped="${ESDE_TO_BIOSKEY[$system]-$system}"

    if [[ -z "$mapped" ]]; then
        echo -e "${DIM}── $system ── (no BIOS required or not in table)${NC}"
        return 0
    fi

    local entries=()
    for entry in "${BIOS_TABLE[@]}"; do
        local s="${entry%%|*}"
        [[ "$s" == "$mapped" ]] && entries+=("$entry")
    done

    if (( ${#entries[@]} == 0 )); then
        echo -e "${DIM}── $system ── (no BIOS data in table)${NC}"
        return 0
    fi

    echo -e "${BOLD}── $system ──${NC}"

    local has_fail=0
    local has_warn=0
    declare -A req_any_groups

    # Collect REQ_ANY groups
    for entry in "${entries[@]}"; do
        IFS='|' read -r _s _file req _conf _md5 _desc <<< "$entry"
        if [[ "$req" =~ ^REQ_ANY: ]]; then
            req_any_groups["${req#REQ_ANY:}"]=0
        fi
    done

    # Verify each entry
    for entry in "${entries[@]}"; do
        IFS='|' read -r _s file req conf md5 desc <<< "$entry"
        local result
        result=$(verify_entry "$file" "$md5")
        local conf_str
        conf_str=$(conf_color "$conf")

        case "$result" in
            OK_HASH)
                echo -e "   ${GREEN}✓${NC} $file  [${conf_str}]  $desc"
                if [[ "$req" =~ ^REQ_ANY: ]]; then
                    req_any_groups[${req#REQ_ANY:}]=1
                fi
                ;;
            OK_NOHASH)
                echo -e "   ${YELLOW}~${NC} $file  [${conf_str}]  $desc ${DIM}(hash unverified)${NC}"
                if [[ "$req" =~ ^REQ_ANY: ]]; then
                    req_any_groups[${req#REQ_ANY:}]=1
                fi
                ;;
            MISSING)
                case "$req" in
                    REQ)
                        echo -e "   ${RED}✗${NC} $file  [${conf_str}]  $desc ${RED}(MISSING — required)${NC}"
                        has_fail=1
                        ;;
                    REQ_ANY:*)
                        echo -e "   ${DIM}·${NC} $file  [${conf_str}]  $desc ${DIM}(missing — group fallback)${NC}"
                        ;;
                    OPT|OPT_BOOT)
                        echo -e "   ${DIM}·${NC} $file  [${conf_str}]  $desc ${DIM}(optional, missing)${NC}"
                        ;;
                esac
                ;;
            WRONG_HASH:*)
                local observed="${result#WRONG_HASH:}"
                echo -e "   ${RED}✗${NC} $file  [${conf_str}]  $desc"
                echo -e "      ${RED}wrong file?${NC} observed MD5 ${RED}$observed${NC}  expected ${GREEN}$md5${NC}"
                case "$req" in
                    REQ)             has_fail=1 ;;
                    REQ_ANY:*)       : ;;
                    OPT|OPT_BOOT)    has_warn=1 ;;
                esac
                ;;
        esac
    done

    # Evaluate REQ_ANY groups
    for group in "${!req_any_groups[@]}"; do
        if [[ "${req_any_groups[$group]}" != "1" ]]; then
            echo -e "   ${RED}✗${NC} group [${BOLD}$group${NC}] — none of the alternatives present"
            has_fail=1
        fi
    done

    if (( has_fail )); then
        echo -e "   ${RED}${BOLD}FAIL${NC} — system will not boot until missing/wrong BIOS is fixed"
        echo ""
        return 2
    elif (( has_warn )); then
        echo -e "   ${YELLOW}${BOLD}WARN${NC} — system should work; optional files missing/mismatched"
        echo ""
        return 1
    else
        echo -e "   ${GREEN}${BOLD}PASS${NC} — required BIOS in place"
        echo ""
        return 0
    fi
}

verify_all() {
    local total_pass=0 total_warn=0 total_fail=0 total_skip=0
    while IFS= read -r sys; do
        if [[ -d "$ROMS/$sys" ]] && [[ -n "$(ls -A "$ROMS/$sys" 2>/dev/null)" ]]; then
            verify_system "$sys"
            case $? in
                0) total_pass=$((total_pass + 1)) ;;
                1) total_warn=$((total_warn + 1)) ;;
                2) total_fail=$((total_fail + 1)) ;;
            esac
        else
            total_skip=$((total_skip + 1))
        fi
    done < <(list_table_systems)

    echo -e "${BOLD}Summary:${NC} ${GREEN}$total_pass PASS${NC}  ${YELLOW}$total_warn WARN${NC}  ${RED}$total_fail FAIL${NC}  ${DIM}$total_skip not present${NC}"
    (( total_fail > 0 )) && return 2
    (( total_warn > 0 )) && return 1
    return 0
}

#=============================================================================
# Main
#=============================================================================

case "${1:-}" in
    --list)
        echo "Systems with BIOS data in the table:"
        list_table_systems | sed 's/^/   /'
        exit 0
        ;;
    --table)
        echo "BIOS table (system|file|req|conf|md5|description):"
        printf '%s\n' "${BIOS_TABLE[@]}"
        exit 0
        ;;
    -h|--help)
        cat << 'HELP'

Portable ES-DE — BIOS Verifier

Usage:
   ./verify-bios.sh                 verify all systems present in ROMs/
   ./verify-bios.sh <system>        verify a specific ES-DE system
   ./verify-bios.sh --list          list systems we have BIOS data for
   ./verify-bios.sh --table         dump the entire BIOS table

States:
   PASS  required BIOS present and hash-verified
   WARN  system will work; optional BIOS missing or hash mismatched
   FAIL  system will not boot — required BIOS missing or hash mismatched

Confidence:
   HIGH  hash sourced from emulator source code / Redump / MAME DAT
   MED   hash sourced from libretro docs / community wiki
   LOW   filename-only check (no canonical hash available)
HELP
        exit 0
        ;;
    "")
        echo ""
        echo -e "${CYAN}Portable ES-DE — BIOS Verifier${NC}"
        echo ""
        if [[ ! -d "$BIOS_DIR" ]]; then
            echo -e "${RED}✗${NC} BIOS directory not found: $BIOS_DIR"
            exit 1
        fi
        verify_all
        exit $?
        ;;
    *)
        echo ""
        if [[ ! -d "$BIOS_DIR" ]]; then
            echo -e "${RED}✗${NC} BIOS directory not found: $BIOS_DIR"
            exit 1
        fi
        verify_system "$1"
        exit $?
        ;;
esac
VERIFYBIOSSCRIPT

chmod +x "$BASE/verify-bios.sh"
ok "verify-bios.sh written to bundle"

# Deploy fetch-vpx-patches.sh — pulls VPX Standalone sidecar scripts for
# tables that have a community patch in jsm174/vpx-standalone-scripts.
cat > "$BASE/fetch-vpx-patches.sh" << 'FETCHVPXSCRIPT'
#!/usr/bin/env bash
# fetch-vpx-patches.sh — download VPX Standalone "sidecar" scripts for tables
# that have a community patch in jsm174/vpx-standalone-scripts.
#
# Some older / Windows-authored VPX tables won't run correctly under VPinball
# Standalone (incomplete VBScript support). The fix is a patched .vbs placed
# next to the .vpx with the IDENTICAL name — VPinball picks it up automatically.
#
# This tool matches the .vpx tables in ROMs/vpinball/ against the repo by
# EXACT filename. An exact match means it's the same table release, so the
# patch is correct. No match -> nothing downloaded (never a wrong patch).
# Tables that already have a sidecar .vbs are skipped, so it's re-runnable.
#
# Usage:  ./fetch-vpx-patches.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPX_DIR="$SCRIPT_DIR/ROMs/vpinball"
REPO="jsm174/vpx-standalone-scripts"
BRANCH="master"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${CYAN}VPX Standalone — sidecar script fetcher${NC}"
echo "Source: github.com/$REPO"
echo ""

if [[ ! -d "$VPX_DIR" ]]; then
    echo "No ROMs/vpinball/ folder found — nothing to do."
    exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}python3 is required but not found in PATH.${NC}"
    exit 1
fi

VPX_COUNT=$(find "$VPX_DIR" -maxdepth 1 -type f -name '*.vpx' 2>/dev/null | wc -l)
if [[ "$VPX_COUNT" -eq 0 ]]; then
    echo "No .vpx tables in ROMs/vpinball/ — nothing to do."
    exit 0
fi
echo "Tables in bundle: $VPX_COUNT"

# Pull the repo file tree (one API call; raw downloads below don't count
# against the API rate limit).
TREE=$(mktemp)
trap 'rm -f "$TREE"' EXIT
echo -n "Fetching patch index ... "
if ! curl -fsSL "https://api.github.com/repos/$REPO/git/trees/$BRANCH?recursive=1" -o "$TREE" 2>/dev/null \
        || [[ ! -s "$TREE" ]]; then
    echo -e "${YELLOW}failed${NC}"
    echo "Could not reach GitHub (offline, or API rate-limited — limit is 60/hour"
    echo "unauthenticated). Try again later."
    exit 1
fi
echo -e "${GREEN}done${NC}"

# Match .vpx basenames against repo .vbs files. Emit  url<TAB>destpath  lines
# for tables that (a) have an exact-name patch and (b) don't already have a
# sidecar .vbs in place.
MATCHES=$(python3 - "$VPX_DIR" "$TREE" "$RAW" <<'PYEOF'
import sys, json, os, urllib.parse
vpx_dir, tree_file, raw = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(tree_file, encoding='utf-8') as fh:
        tree = json.load(fh)
except Exception:
    sys.exit(0)

# repo: map  "<TableName>" (no .vbs)  ->  repo path.  Only exact ".vbs"
# blobs — not .vbs.original / .vbs.patch / .vbs.dmd variants.
patches = {}
for ent in tree.get('tree', []):
    p = ent.get('path', '')
    if ent.get('type') == 'blob' and p.endswith('.vbs'):
        patches[os.path.basename(p)[:-4]] = p

for f in sorted(os.listdir(vpx_dir)):
    if not f.endswith('.vpx'):
        continue
    base = f[:-4]
    if base not in patches:
        continue
    if os.path.exists(os.path.join(vpx_dir, base + '.vbs')):
        continue   # already has a sidecar — leave it
    url = raw + '/' + urllib.parse.quote(patches[base])
    print(url + '\t' + os.path.join(vpx_dir, base + '.vbs'))
PYEOF
)

if [[ -z "$MATCHES" ]]; then
    echo ""
    echo "No new patches to fetch — either no exact-name matches, or every"
    echo "matching table already has its sidecar .vbs in place."
    echo "(Patches match by exact table filename; packs using different table"
    echo " releases than the repo simply won't match. That's expected.)"
    exit 0
fi

N=$(printf '%s\n' "$MATCHES" | grep -c .)
echo ""
echo "Matched $N table(s) with an available patch — downloading:"
echo ""

OK=0; FAIL=0
while IFS=$'\t' read -r URL DEST; do
    [[ -z "$URL" ]] && continue
    NAME=$(basename "$DEST")
    echo -n "  $NAME ... "
    if curl -fsSL "$URL" -o "$DEST" 2>/dev/null && [[ -s "$DEST" ]]; then
        echo -e "${GREEN}ok${NC}"
        OK=$((OK + 1))
    else
        echo -e "${YELLOW}failed${NC}"
        rm -f "$DEST"
        FAIL=$((FAIL + 1))
    fi
done <<< "$MATCHES"

echo ""
echo -e "${GREEN}Done — $OK sidecar script(s) installed into ROMs/vpinball/.${NC}"
[[ "$FAIL" -gt 0 ]] && echo -e "${YELLOW}$FAIL download(s) failed — re-run to retry.${NC}"
echo "Re-run anytime: new patches are added to the repo regularly, and any"
echo "tables you add later will be picked up on the next run."
FETCHVPXSCRIPT
chmod +x "$BASE/fetch-vpx-patches.sh"
ok "fetch-vpx-patches.sh written to bundle"

#=============================================================================
# STEP 15: WRITE INSTALL-CORE.SH TO BUNDLE
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing install-core.sh to bundle..."

cat > "$BASE/install-core.sh" << 'INSTALLCORESCRIPT'
#!/usr/bin/env bash
#=============================================================================
# Portable ES-DE — Libretro Core Installer
# Downloads a single libretro core from the buildbot, into the bundle.
# Usage: ./install-core.sh <core_name>
#   e.g. ./install-core.sh mednafen_psx_hw
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
EMUS="$BASE/Emulators"
CORE_DIR="$EMUS/retroarch-cores"
CORE_BASE_URL="https://buildbot.libretro.com/nightly/linux/x86_64/latest"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "   ${GREEN}✓${NC} $1"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; }
info() { echo -e "   ${CYAN}→${NC} $1"; }

install_core() {
    local core_name="$1"
    local zip_name="${core_name}_libretro.so.zip"
    local so_name="${core_name}_libretro.so"
    mkdir -p "$CORE_DIR"
    if [[ -f "$CORE_DIR/$so_name" ]]; then
        ok "Core $core_name already installed"
        return 0
    fi
    info "Downloading $core_name from libretro buildbot..."
    local tmp="/tmp/$zip_name"
    if curl -sfL -o "$tmp" "$CORE_BASE_URL/$zip_name"; then
        if unzip -qo "$tmp" -d "$CORE_DIR" 2>/dev/null; then
            rm -f "$tmp"
            ok "Installed $core_name"
            return 0
        fi
    fi
    rm -f "$tmp"
    fail "Failed to install core $core_name (network or core unavailable on Linux x86_64 buildbot)"
    return 1
}

case "${1:-}" in
    "")     echo "Usage: $0 <core_name>"; echo "Example: $0 mednafen_psx_hw"; exit 1 ;;
    -h|--help)
            echo "Portable ES-DE — Libretro Core Installer"
            echo "Usage: $0 <core_name>"
            echo "Examples:"
            echo "   $0 mednafen_psx_hw       # PS1 (high accuracy)"
            echo "   $0 snes9x                # SNES"
            echo "   $0 flycast               # Dreamcast / NAOMI / Atomiswave"
            exit 0 ;;
    *)      install_core "$1" ;;
esac
INSTALLCORESCRIPT

chmod +x "$BASE/install-core.sh"
ok "install-core.sh written to bundle"

#=============================================================================
# STEP 16: WRITE INSTALL-EMULATOR.SH TO BUNDLE
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing install-emulator.sh to bundle..."

cat > "$BASE/install-emulator.sh" << 'INSTALLEMUSCRIPT'
#!/usr/bin/env bash
#=============================================================================
# Portable ES-DE — Standalone Emulator Installer
# Downloads a single standalone emulator into the bundle.
# Usage: ./install-emulator.sh <emulator_name>
#   e.g. ./install-emulator.sh dolphin
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
EMUS="$BASE/Emulators"
mkdir -p "$EMUS"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "   ${GREEN}✓${NC} $1"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; }
info() { echo -e "   ${CYAN}→${NC} $1"; }

DOWNLOAD_ERRORS=0

#=============================================================================
# Download helpers (shared with setup-portable-esde.sh)
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

#=============================================================================
# Emulator install functions
# Used by both the main install flow below AND by the bundle's
# install-emulator.sh (a heredoc copy of these functions for on-demand
# installation when import-collection.sh imports a system whose emulator
# isn't yet installed).
#=============================================================================

install_retroarch() {
    download_direct \
        "https://github.com/hizzlekizzle/RetroArch-AppImage/releases/download/Linux_LTS_Nightlies/RetroArch-Linux-x86_64-Nightly.AppImage" \
        "$EMUS/RetroArch-Linux-x86_64-Nightly.AppImage" \
        "RetroArch" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_rpcs3() {
    download_rpcs3 "$EMUS" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_pcsx2() {
    github_appimage "PCSX2/pcsx2" \
        "linux-appimage-x64.*\.AppImage$" \
        "$EMUS/pcsx2-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_duckstation() {
    github_appimage "stenzek/duckstation" \
        "DuckStation.*x64.*\.AppImage$" \
        "$EMUS/DuckStation-x64.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_ppsspp() {
    github_appimage "hrydgard/ppsspp" \
        "PPSSPP.*x86_64.*\.AppImage$" \
        "$EMUS/PPSSPP-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_melonds() {
    github_appimage "pkgforge-dev/melonDS-AppImage-Enhanced" \
        "melonDS.*x86_64.*\.AppImage$" \
        "$EMUS/melonDS-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_dolphin() {
    github_appimage "pkgforge-dev/Dolphin-emu-AppImage" \
        "Dolphin_Emulator.*x86_64.*\.AppImage$" \
        "$EMUS/dolphin-emu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_cemu() {
    github_appimage "cemu-project/Cemu" \
        "Cemu.*\.AppImage$" \
        "$EMUS/Cemu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_azahar() {
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
}

install_xemu() {
    github_appimage "xemu-project/xemu" \
        "xemu-[0-9].*x86_64\.AppImage$" \
        "$EMUS/xemu-latest.AppImage" || {
            github_appimage "xemu-project/xemu" \
                "xemu.*x86_64\.AppImage$" \
                "$EMUS/xemu-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        } || true
}

install_xenia() {
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
}

install_ryujinx() {
    # Ryubing is hosted on a self-managed Forgejo instance, not GitHub
    # Downloads from git.ryujinx.app via their GitHub mirror releases
    if compgen -G "$EMUS/ryujinx*.AppImage" > /dev/null 2>&1; then
        ok "Ryubing already exists, skipping"
    else
        info "Downloading Ryubing ..."
        # Try GitHub mirror first
        RYUBING_URL=$(curl -sfL "https://api.github.com/repos/Ryubing/Ryujinx/releases?per_page=5" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -P "x64\.AppImage$" \
            | head -1) || true
        # Fallback: direct download from ryujinx.app
        if [[ -z "$RYUBING_URL" ]]; then
            RYUBING_URL=$(curl -sfL "https://git.ryujinx.app/api/v1/repos/ryubing/ryujinx/releases?limit=5" \
                | grep -oP '"browser_download_url":\s*"\K[^"]*' \
                | grep -P "x64\.AppImage$" \
                | head -1) || true
        fi
        if [[ -n "$RYUBING_URL" ]]; then
            RYUBING_FNAME=$(basename "$RYUBING_URL")
            if curl -#fL -o "$EMUS/$RYUBING_FNAME" "$RYUBING_URL"; then
                chmod +x "$EMUS/$RYUBING_FNAME"
                ok "Ryubing downloaded: $RYUBING_FNAME"
            else
                fail "Ryubing download failed"
                DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                rm -f "$EMUS/$RYUBING_FNAME"
            fi
        else
            warn "Ryubing URL not found — download manually from https://git.ryujinx.app/ryubing/ryujinx"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi
}

install_eden() {
    # Eden is hosted on git.eden-emu.dev (Gitea instance, not GitHub)
    # Stable releases: git.eden-emu.dev/eden-emu/eden
    # Nightly builds:  git.eden-emu.dev/eden-ci/nightly
    if compgen -G "$EMUS/Eden*.AppImage" > /dev/null 2>&1; then
        ok "Eden already exists, skipping"
    else
        info "Downloading Eden ..."
        # Try stable release first via Gitea API
        EDEN_URL=$(curl -sfL "https://git.eden-emu.dev/api/v1/repos/eden-emu/eden/releases?limit=5&token=" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "amd64.*\.AppImage$|x86_64.*\.AppImage$" \
            | grep -iv "arm\|zsync\|deb\|room" \
            | head -1) || true
        # Fallback: nightly builds
        if [[ -z "$EDEN_URL" ]]; then
            EDEN_URL=$(curl -sfL "https://git.eden-emu.dev/api/v1/repos/eden-ci/nightly/releases?limit=3" \
                | grep -oP '"browser_download_url":\s*"\K[^"]*' \
                | grep -iP "amd64.*\.AppImage$|x86_64.*\.AppImage$" \
                | grep -iv "arm\|zsync\|deb\|room" \
                | head -1) || true
        fi
        if [[ -n "$EDEN_URL" ]]; then
            EDEN_FNAME=$(basename "$EDEN_URL")
            if curl -#fL -o "$EMUS/$EDEN_FNAME" "$EDEN_URL"; then
                chmod +x "$EMUS/$EDEN_FNAME"
                ok "Eden downloaded: $EDEN_FNAME"
            else
                fail "Eden download failed"
                DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                rm -f "$EMUS/$EDEN_FNAME"
            fi
        else
            warn "Eden URL not found — download manually from https://git.eden-emu.dev/eden-emu/eden/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi
}

install_shadps4() {
    if [[ -f "$EMUS/shadps4" ]] || [[ -f "$EMUS/shadps4-qt" ]]; then
        ok "shadPS4 already exists, skipping"
    else
        # shadPS4 ships as tar.gz/zip for Linux — try Qt build first, then headless
        # shadPS4 releases: shadps4-linux-sdl-*.zip containing Shadps4-sdl.AppImage
        SHADPS4_URL=$(curl -sfL "https://api.github.com/repos/shadps4-emu/shadPS4/releases?per_page=5" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "shadps4-linux-sdl.*\.zip$|linux.*x86.?64.*\.(tar\.(gz|xz)|zip)$" \
            | grep -iv "debug\|symbols\|arm\|qt" \
            | grep -v "Pre-release" \
            | head -1) || true
        if [[ -n "$SHADPS4_URL" ]]; then
            info "Downloading shadPS4 ..."
            SHADPS4_TMPDIR=$(mktemp -d)
            SHADPS4_FILE="$SHADPS4_TMPDIR/shadps4-dl"
            if curl -#fL -o "$SHADPS4_FILE" "$SHADPS4_URL"; then
                # Detect archive type by content, not extension
                FILE_TYPE=$(file "$SHADPS4_FILE" | tr '[:upper:]' '[:lower:]')
                if echo "$FILE_TYPE" | grep -q "zip"; then
                    unzip -qo "$SHADPS4_FILE" -d "$SHADPS4_TMPDIR/extract" 2>/dev/null || true
                elif echo "$FILE_TYPE" | grep -q "xz\|lzma"; then
                    tar -xJf "$SHADPS4_FILE" -C "$SHADPS4_TMPDIR" 2>/dev/null || true
                else
                    tar -xzf "$SHADPS4_FILE" -C "$SHADPS4_TMPDIR" 2>/dev/null || true
                fi
                # Find the main shadPS4 executable (qt preferred over headless)
                SHADPS4_BIN=$(find "$SHADPS4_TMPDIR" -type f \( -name "shadps4-qt" -o -name "shadps4" -o -iname "shadps4*.AppImage" -o -iname "Shadps4*.AppImage" \) 2>/dev/null | grep -v "\.so" | head -1)
                if [[ -n "$SHADPS4_BIN" ]]; then
                    # Copy the binary and any sibling shared libs it needs
                    BIN_DIR=$(dirname "$SHADPS4_BIN")
                    cp "$SHADPS4_BIN" "$EMUS/shadps4"
                    chmod +x "$EMUS/shadps4"
                    # Copy .so files from same dir (shadPS4 bundles Qt libs)
                    find "$BIN_DIR" -maxdepth 1 -name "*.so*" -exec cp {} "$EMUS/" \; 2>/dev/null || true
                    find "$BIN_DIR" -maxdepth 1 -type d -exec cp -r {} "$EMUS/" \; 2>/dev/null || true
                    ok "shadPS4 downloaded"
                else
                    fail "Could not find shadPS4 binary inside archive"
                    DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                fi
            else
                fail "shadPS4 download failed"
                DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
            rm -rf "$SHADPS4_TMPDIR"
        else
            warn "shadPS4 download URL not found — check https://github.com/shadps4-emu/shadPS4/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi
}

install__86box() {
    github_appimage "86Box/86Box" \
        "86Box.*x86_64.*\.AppImage$" \
        "$EMUS/86Box-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_vpinball() {
    if [[ -f "$EMUS/VPinballX_BGFX" ]] || [[ -f "$EMUS/VPinballX_GL" ]]; then
        ok "VPinball already exists, skipping"
    else
        # vpinball releases: BGFX and GL are separate zips, each containing one binary
        # plus shared support dirs (scripts/, shaders/, assets/, pinmame/, etc.)
        # Real filename format: VPinballX_BGFX-10.8.1-3788-2151290-linux-x64-Release.zip
        VPINBALL_TMP=$(mktemp -d)
        VPINBALL_GOT=0
        VPINBALL_COUNT_FILE=$(mktemp)
        echo 0 > "$VPINBALL_COUNT_FILE"

        # Fetch BGFX and GL zip URLs from the latest release only
        VPINBALL_URLS=$(curl -sfL "https://api.github.com/repos/vpinball/vpinball/releases?per_page=1"         | grep -oP '"browser_download_url":\s*"\K[^"]*'         | grep -iP "VPinballX_(BGFX|GL)-.*linux.*x64.*\.zip$"         | grep -iv "debug\|symbols") || true

        if [[ -z "$VPINBALL_URLS" ]]; then
            warn "VPinball download URL not found — check https://github.com/vpinball/vpinball/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        else
            # Download and extract each zip — VPinball zips contain a tar.gz inside
            while IFS= read -r VPURL; do
                [[ -z "$VPURL" ]] && continue
                VPZIP=$(basename "$VPURL")
                info "Downloading $VPZIP ..."
                if curl -#fL -o "$VPINBALL_TMP/$VPZIP" "$VPURL"; then
                    # Step 1: unzip to get the tar.gz inside
                    unzip -qo "$VPINBALL_TMP/$VPZIP" -d "$VPINBALL_TMP" 2>/dev/null || true
                    # Step 2: extract any tar.gz that came out of the zip
                    for TGZ in "$VPINBALL_TMP"/*.tar.gz "$VPINBALL_TMP"/*.tar.xz; do
                        [[ -f "$TGZ" ]] || continue
                        mkdir -p "$VPINBALL_TMP/extract"
                        tar -xzf "$TGZ" -C "$VPINBALL_TMP/extract" 2>/dev/null ||                     tar -xJf "$TGZ" -C "$VPINBALL_TMP/extract" 2>/dev/null || true
                        rm -f "$TGZ"
                    done
                    echo $(( $(cat "$VPINBALL_COUNT_FILE") + 1 )) > "$VPINBALL_COUNT_FILE"
                else
                    warn "Failed to download $VPZIP"
                fi
            done <<< "$VPINBALL_URLS"
            VPINBALL_GOT=$(cat "$VPINBALL_COUNT_FILE")
            rm -f "$VPINBALL_COUNT_FILE"

            if [[ $VPINBALL_GOT -gt 0 ]]; then
                # Copy binaries — search at any depth after extraction
                for BIN in VPinballX_BGFX VPinballX_GL VPinballX; do
                    FOUND=$(find "$VPINBALL_TMP" -name "$BIN" -type f 2>/dev/null | head -1)
                    if [[ -n "$FOUND" ]]; then
                        cp "$FOUND" "$EMUS/$BIN"
                        chmod +x "$EMUS/$BIN"
                        ok "  Installed: $BIN"
                    fi
                done
                # Copy all support subdirectories (scripts, shaders, assets, pinmame, etc.)
                EXTRACT_ROOT="$VPINBALL_TMP/extract"
                [[ ! -d "$EXTRACT_ROOT" ]] && EXTRACT_ROOT="$VPINBALL_TMP"
                find "$EXTRACT_ROOT" -mindepth 1 -maxdepth 2 -type d | while read -r D; do
                    DNAME=$(basename "$D")
                    # Skip the extract dir itself and temp root
                    [[ "$DNAME" == "extract" ]] && continue
                    [[ ! -d "$EMUS/$DNAME" ]] && mkdir -p "$EMUS/$DNAME"
                    cp -rn "$D/." "$EMUS/$DNAME/" 2>/dev/null || true
                done
                # Copy bundled shared libraries — VPinball ships libbgfx.so,
                # libSDL3*.so, libfreeimage.so etc. as ROOT-LEVEL files in the
                # archive (NOT in a subdir), so the directory loop above misses
                # them. Without these the binary dies at load time with
                # "error while loading shared libraries: libbgfx.so". Find at
                # any depth and flatten next to the binary; the wrapper's
                # LD_LIBRARY_PATH points the loader here.
                VP_LIBS=0
                while IFS= read -r LIB; do
                    [[ -z "$LIB" ]] && continue
                    LIBNAME=$(basename "$LIB")
                    [[ -f "$EMUS/$LIBNAME" ]] && continue
                    cp "$LIB" "$EMUS/$LIBNAME" 2>/dev/null && VP_LIBS=$((VP_LIBS + 1))
                done < <(find "$EXTRACT_ROOT" -type f -name '*.so*' 2>/dev/null)
                # Synthesize SONAME symlinks (libFOO.so.1.2.3 -> libFOO.so.1).
                # find -type f copies only the real versioned files; the binary
                # links against the major-version SONAME. Without these links
                # the loader fails with "libSDL3.so.0: cannot open shared
                # object file". This mini-ldconfig pass makes it work whether
                # or not the archive shipped the symlinks.
                ( cd "$EMUS" && for real in lib*.so.*; do
                    [[ -f "$real" && ! -L "$real" ]] || continue
                    soname=$(printf '%s' "$real" | sed -E 's/(\.so\.[0-9]+)\..*/\1/')
                    [[ "$soname" != "$real" && ! -e "$soname" ]] && ln -s "$real" "$soname"
                done )
                # VPinball Standalone auto-detects a pinmame/ folder next to the
                # .vpx files; create it so PinMAME-based tables (real solid-state
                # / DMD machines) have a ROM directory. Users drop romset zips
                # into ROMs/vpinball/pinmame/roms/ themselves (copyrighted, like
                # arcade ROMs — not bundled).
                mkdir -p "$ROMS/vpinball/pinmame/roms" "$ROMS/vpinball/pinmame/nvram"
                ok "VPinball downloaded ($VPINBALL_GOT zip(s) extracted, $VP_LIBS shared libs)"
            else
                fail "VPinball downloads all failed"
                DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        fi
        rm -rf "$VPINBALL_TMP"
    fi
    echo ""

}

install_dosbox_x() {
    if compgen -G "$EMUS/[dD]os[bB]ox-[xX]*.AppImage" > /dev/null 2>&1 \
       || compgen -G "$EMUS/DOSBox-X*.AppImage" > /dev/null 2>&1; then
        ok "DOSBox-X already exists, skipping"
    else
        DOSBOXX_URL=$(curl -sfL "https://api.github.com/repos/pkgforge-dev/DOSBox-X-AppImage/releases?per_page=3" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "\.AppImage$" \
            | grep -iv "arm\|aarch" | head -1) || true
        if [[ -n "$DOSBOXX_URL" ]]; then
            info "Downloading DOSBox-X..."
            FNAME=$(basename "$DOSBOXX_URL")
            if curl -#fL -o "$EMUS/$FNAME" "$DOSBOXX_URL"; then
                chmod +x "$EMUS/$FNAME"
                cat > "$EMUS/dosbox-x-portable.sh" << 'DBXWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -iname 'dosbox-x*.AppImage' | head -1)
exec "$BIN" "$@"
DBXWRAP
                chmod +x "$EMUS/dosbox-x-portable.sh"
                ok "DOSBox-X downloaded"
            else
                fail "DOSBox-X download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "DOSBox-X not found — check https://github.com/pkgforge-dev/DOSBox-X-AppImage/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi
}

install_ruffle() {
    if [[ -f "$EMUS/ruffle" ]] || compgen -G "$EMUS/ruffle*.AppImage" > /dev/null 2>&1; then
        ok "Ruffle already exists, skipping"
    else
        RUFFLE_URL=$(curl -sfL "https://api.github.com/repos/ruffle-rs/ruffle/releases?per_page=3"         | grep -oP '"browser_download_url":\s*"\K[^"]*'         | grep -iP "linux.*x86.?64.*\.tar\.gz$"         | grep -iv "debug\|arm" | head -1) || true
        if [[ -n "$RUFFLE_URL" ]]; then
            info "Downloading Ruffle..."
            RUFFLE_TMP=$(mktemp -d)
            if curl -#fL "$RUFFLE_URL" | tar -xz -C "$RUFFLE_TMP" 2>/dev/null; then
                RUFFLE_BIN=$(find "$RUFFLE_TMP" -name "ruffle" -type f | head -1)
                if [[ -n "$RUFFLE_BIN" ]]; then
                    cp "$RUFFLE_BIN" "$EMUS/ruffle"
                    chmod +x "$EMUS/ruffle"
                    cat > "$EMUS/ruffle-portable.sh" << 'RUFFLEWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
exec "$SCRIPT_DIR/ruffle" "$@"
RUFFLEWRAP
                    chmod +x "$EMUS/ruffle-portable.sh"
                    ok "Ruffle downloaded"
                else
                    fail "Ruffle binary not found in archive"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                fi
            else
                fail "Ruffle download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
            rm -rf "$RUFFLE_TMP"
        else
            warn "Ruffle URL not found — check https://github.com/ruffle-rs/ruffle/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi

}

install_eka2l1() {
    if compgen -G "$EMUS/eka2l1*.AppImage" > /dev/null 2>&1 || compgen -G "$EMUS/EKA2L1*.AppImage" > /dev/null 2>&1; then
        ok "EKA2L1 already exists, skipping"
    else
        # The continuous tag is the only release tag — fetch by tag, not "latest"
        EKA2L1_URL=$(curl -sfL "https://api.github.com/repos/EKA2L1/EKA2L1/releases/tags/continous" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "linux.*\.AppImage$" \
            | grep -iv "arm\|aarch" \
            | head -1) || true
        if [[ -n "$EKA2L1_URL" ]]; then
            info "Downloading EKA2L1..."
            EKA2L1_FNAME=$(basename "$EKA2L1_URL")
            if curl -#fL -o "$EMUS/$EKA2L1_FNAME" "$EKA2L1_URL"; then
                chmod +x "$EMUS/$EKA2L1_FNAME"
                cat > "$EMUS/eka2l1-portable.sh" << 'EKA2L1WRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -iname 'eka2l1*.AppImage' -o -iname 'EKA2L1*.AppImage' 2>/dev/null | head -1)
exec "$BIN" "$@"
EKA2L1WRAP
                chmod +x "$EMUS/eka2l1-portable.sh"
                ok "EKA2L1 downloaded ($EKA2L1_FNAME)"
            else
                fail "EKA2L1 download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
                rm -f "$EMUS/$EKA2L1_FNAME"
            fi
        else
            warn "EKA2L1 URL not found — check https://github.com/EKA2L1/EKA2L1/releases/tag/continous"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi

}

install_solarus() {
    if [[ -x "$EMUS/solarus-run" ]] || [[ -x "$EMUS/solarus-portable.sh" ]] \
       || compgen -G "$EMUS/solarus*.AppImage" > /dev/null 2>&1; then
        ok "Solarus already exists, skipping"
    else
        # Known stable direct URL — update version number when new releases come out
        SOLARUS_URL="https://gitlab.com/api/v4/projects/solarus-games%2Fsolarus/packages/generic/solarus/2.0.4/solarus-launcher-v2.0.4-linux-x64.tar.gz"
        info "Downloading Solarus..."
        # Solarus ships as a tar.gz containing a standalone binary
        SOLARUS_TMP=$(mktemp -d)
        if curl -#fL "$SOLARUS_URL" | tar -xz -C "$SOLARUS_TMP" 2>/dev/null; then
            SOLARUS_BIN=$(find "$SOLARUS_TMP" -type f -name "solarus*" ! -name "*.so*" 2>/dev/null | head -1)
            if [[ -n "$SOLARUS_BIN" ]]; then
                cp "$SOLARUS_BIN" "$EMUS/solarus-run"
                chmod +x "$EMUS/solarus-run"
                # Copy any bundled data dirs
                find "$SOLARUS_TMP" -mindepth 1 -maxdepth 2 -type d | while read -r D; do
                    cp -rn "$D" "$EMUS/" 2>/dev/null || true
                done
                cat > "$EMUS/solarus-portable.sh" << 'SOLARUSWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
exec "$SCRIPT_DIR/solarus-run" "$@"
SOLARUSWRAP
                chmod +x "$EMUS/solarus-portable.sh"
                ok "Solarus downloaded"
            else
                fail "Solarus binary not found in archive"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "Solarus download failed — check https://www.solarus-games.org/download/"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
        rm -rf "$SOLARUS_TMP"
    fi

}

install_simcoupe() {
    if [[ -f "$EMUS/simcoupe" ]]; then
        ok "SimCoupe already exists, skipping"
    else
        # Version-pinned direct URL — check https://simonowen.com/simcoupe/ for updates
        SIMCOUPE_URL="https://github.com/simonowen/simcoupe/releases/download/v1.2.15/simcoupe_1.2.15_linux_amd64.tar.gz"
        info "Downloading SimCoupe..."
        SIMCOUPE_TMP=$(mktemp -d)
        if curl -#fL "$SIMCOUPE_URL" | tar -xz -C "$SIMCOUPE_TMP" 2>/dev/null; then
            SIMCOUPE_BIN=$(find "$SIMCOUPE_TMP" -name "simcoupe" -type f 2>/dev/null | head -1)
            if [[ -n "$SIMCOUPE_BIN" ]]; then
                cp "$SIMCOUPE_BIN" "$EMUS/simcoupe"
                chmod +x "$EMUS/simcoupe"
                cat > "$EMUS/simcoupe-portable.sh" << 'SIMWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
# SimCoupe writes its config/saves to ~/.simcoupe/ — redirect HOME so
# everything stays in the bundle (true portability).
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
mkdir -p "$BASE_DIR/.simcoupe"
exec "$SCRIPT_DIR/simcoupe" "$@"
SIMWRAP
                chmod +x "$EMUS/simcoupe-portable.sh"
                ok "SimCoupe downloaded"
            else
                fail "SimCoupe binary not found in archive"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "SimCoupe download failed — check https://simonowen.com/simcoupe/"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
        rm -rf "$SIMCOUPE_TMP"
    fi

}

install_supermodel() {
    if compgen -G "$EMUS/supermodel*.AppImage" > /dev/null 2>&1 || [[ -f "$EMUS/supermodel" ]]; then
        ok "Supermodel already exists, skipping"
    else
        SUPERMODEL_URL=$(curl -sfL "https://api.github.com/repos/pkgforge-dev/Supermodel-AppImage/releases?per_page=3"         | grep -oP '"browser_download_url":\s*"\K[^"]*'         | grep -iP "\.AppImage$"         | grep -iv "arm\|aarch" | head -1) || true
        if [[ -n "$SUPERMODEL_URL" ]]; then
            info "Downloading Supermodel..."
            FNAME=$(basename "$SUPERMODEL_URL")
            if curl -#fL -o "$EMUS/$FNAME" "$SUPERMODEL_URL"; then
                chmod +x "$EMUS/$FNAME"
                cat > "$EMUS/supermodel-portable.sh" << 'SUPERWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -iname 'supermodel*.AppImage' | head -1)
[[ -z "$BIN" ]] && BIN="$SCRIPT_DIR/supermodel"
exec "$BIN" "$@"
SUPERWRAP
                chmod +x "$EMUS/supermodel-portable.sh"
                ok "Supermodel downloaded"
            else
                fail "Supermodel download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "Supermodel URL not found — check https://github.com/pkgforge-dev/Supermodel-AppImage/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi

}

install_mame() {
    if compgen -G "$EMUS/MAME*.AppImage" > /dev/null 2>&1 || compgen -G "$EMUS/mame*.AppImage" > /dev/null 2>&1; then
        ok "Standalone MAME already exists, skipping"
    else
        MAME_URL=$(curl -sfL "https://api.github.com/repos/pkgforge-dev/MAME-AppImage/releases?per_page=3" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "\.AppImage$" \
            | grep -iv "arm\|aarch" | head -1) || true
        if [[ -n "$MAME_URL" ]]; then
            info "Downloading standalone MAME..."
            FNAME=$(basename "$MAME_URL")
            if curl -#fL -o "$EMUS/$FNAME" "$MAME_URL"; then
                chmod +x "$EMUS/$FNAME"
                ok "Standalone MAME downloaded ($FNAME)"
            else
                fail "Standalone MAME download failed"; DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
            fi
        else
            warn "Standalone MAME URL not found — check https://github.com/pkgforge-dev/MAME-AppImage/releases"
            DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1))
        fi
    fi

}


#=============================================================================
# Dispatcher
#=============================================================================
case "${1:-}" in
    "")
        echo "Usage: $0 <emulator_name>"
        echo "Available: retroarch rpcs3 pcsx2 duckstation ppsspp melonds dolphin cemu azahar xemu xenia ryujinx eden shadps4 _86box vpinball dosbox_x ruffle eka2l1 solarus simcoupe supermodel mame"
        exit 1
        ;;
    -h|--help)
        echo "Portable ES-DE — Standalone Emulator Installer"
        echo ""
        echo "Usage: $0 <emulator_name>"
        echo ""
        echo "Available emulators:"
        for n in retroarch rpcs3 pcsx2 duckstation ppsspp melonds dolphin cemu azahar xemu xenia ryujinx eden shadps4 _86box vpinball dosbox_x ruffle eka2l1 solarus simcoupe supermodel mame; do echo "   $n"; done
        exit 0
        ;;
    rpcs3)         install_rpcs3 ;;
    retroarch)     install_retroarch ;;
    pcsx2)         install_pcsx2 ;;
    duckstation)         install_duckstation ;;
    ppsspp)         install_ppsspp ;;
    melonds)         install_melonds ;;
    dolphin)         install_dolphin ;;
    cemu)         install_cemu ;;
    azahar)         install_azahar ;;
    xemu)         install_xemu ;;
    xenia)         install_xenia ;;
    ryujinx)         install_ryujinx ;;
    eden)         install_eden ;;
    shadps4)         install_shadps4 ;;
    _86box)         install__86box ;;
    vpinball)         install_vpinball ;;
    dosbox_x)         install_dosbox_x ;;
    ruffle)         install_ruffle ;;
    eka2l1)         install_eka2l1 ;;
    solarus)         install_solarus ;;
    simcoupe)         install_simcoupe ;;
    supermodel)         install_supermodel ;;
    mame)         install_mame ;;
    *)
        fail "Unknown emulator: $1"
        echo "Run '$0 --help' to see available emulators"
        exit 1
        ;;
esac

exit $DOWNLOAD_ERRORS
INSTALLEMUSCRIPT

chmod +x "$BASE/install-emulator.sh"
ok "install-emulator.sh written to bundle"

#=============================================================================
# STEP 17: WRITE UPDATE SCRIPT TO BUNDLE
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

# Whiptail UI helpers (bundle requires whiptail — installed by setup)
if ! command -v whiptail >/dev/null 2>&1; then
    echo "whiptail is required but not found in PATH."
    echo "Install with: sudo apt install whiptail   (or 'sudo dnf install newt' on Fedora)"
    exit 1
fi
wt_yesno() { whiptail --title "$1" --yesno "$2" 14 78; }

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
    if wt_yesno "Update" "Update?"; then
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
        if wt_yesno "Update" "Re-download latest ES-DE?"; then
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
    if wt_yesno "Update" "Re-download latest?"; then
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
    if wt_yesno "Update" "Re-download latest nightly?"; then
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

check_and_update "86Box (Win9x/PC)" "86Box*.AppImage" \
    "$(github_latest_url 86Box/86Box '86Box.*x86_64.*\.AppImage$')" "86Box-latest"

# shadPS4 — ships as zip, re-download to update
SHADPS4_CURRENT=$(find "$EMUS" -maxdepth 1 -name 'shadps4' -type f 2>/dev/null | head -1)
if [[ -n "$SHADPS4_CURRENT" ]]; then
    printf "   %-32s" "shadPS4 (PS4)"
    echo -e " ${CYAN}[zip release — re-download to update]${NC}"
    if wt_yesno "Update" "Re-download latest?"; then
        SHAD_URL=$(curl -sfL "https://api.github.com/repos/shadps4-emu/shadPS4/releases?per_page=3"             | grep -oP '"browser_download_url":\s*"\K[^"]*'             | grep -iP "linux.*x86.?64.*\.(tar\.(gz|xz)|zip)$"             | grep -iv "debug\|symbols\|arm" | head -1) || true
        if [[ -n "$SHAD_URL" ]]; then
            SHAD_TMP=$(mktemp -d)
            SHAD_FILE="$SHAD_TMP/shadps4-dl"
            if curl -#fL -o "$SHAD_FILE" "$SHAD_URL"; then
                FILE_TYPE=$(file "$SHAD_FILE" | tr '[:upper:]' '[:lower:]')
                if echo "$FILE_TYPE" | grep -q "zip"; then
                    unzip -qo "$SHAD_FILE" -d "$SHAD_TMP/extract" 2>/dev/null || true
                elif echo "$FILE_TYPE" | grep -q "xz\|lzma"; then
                    tar -xJf "$SHAD_FILE" -C "$SHAD_TMP" 2>/dev/null || true
                else
                    tar -xzf "$SHAD_FILE" -C "$SHAD_TMP" 2>/dev/null || true
                fi
                SHAD_BIN=$(find "$SHAD_TMP" -type f \( -name "shadps4-qt" -o -name "shadps4" \) | grep -v "\.so" | head -1)
                if [[ -n "$SHAD_BIN" ]]; then
                    mv "$SHAD_BIN" "$EMUS/shadps4"
                    chmod +x "$EMUS/shadps4"
                    ok "shadPS4 updated"
                else
                    warn "Binary not found in archive"
                fi
            fi
            rm -rf "$SHAD_TMP"
        else
            warn "Could not find download URL"
        fi
    fi
    echo ""
fi

# VPinball — zip-within-tar.gz, re-download to update
if [[ -f "$EMUS/VPinballX_BGFX" ]] || [[ -f "$EMUS/VPinballX_GL" ]]; then
    printf "   %-32s" "VPinball (Visual Pinball)"
    echo -e " ${CYAN}[zip release — re-download to update]${NC}"
    if wt_yesno "Update" "Re-download latest?"; then
        VPIN_URLS=$(curl -sfL "https://api.github.com/repos/vpinball/vpinball/releases?per_page=1"             | grep -oP '"browser_download_url":\s*"\K[^"]*'             | grep -iP "VPinballX_(BGFX|GL)-.*linux.*x64.*\.zip$"             | grep -iv "debug\|symbols") || true
        if [[ -n "$VPIN_URLS" ]]; then
            VPIN_TMP=$(mktemp -d)
            while IFS= read -r VURL; do
                [[ -z "$VURL" ]] && continue
                VZIP=$(basename "$VURL")
                info "Downloading $VZIP ..."
                if curl -#fL -o "$VPIN_TMP/$VZIP" "$VURL"; then
                    unzip -qo "$VPIN_TMP/$VZIP" -d "$VPIN_TMP" 2>/dev/null || true
                    for TGZ in "$VPIN_TMP"/*.tar.gz "$VPIN_TMP"/*.tar.xz; do
                        [[ -f "$TGZ" ]] || continue
                        mkdir -p "$VPIN_TMP/extract"
                        tar -xzf "$TGZ" -C "$VPIN_TMP/extract" 2>/dev/null || true
                        rm -f "$TGZ"
                    done
                fi
            done <<< "$VPIN_URLS"
            for BIN in VPinballX_BGFX VPinballX_GL; do
                FOUND=$(find "$VPIN_TMP" -name "$BIN" -type f 2>/dev/null | head -1)
                [[ -n "$FOUND" ]] && cp "$FOUND" "$EMUS/$BIN" && chmod +x "$EMUS/$BIN"
            done
            rm -rf "$VPIN_TMP"
            ok "VPinball updated"
        else
            warn "Could not find download URL"
        fi
    fi
    echo ""
fi

# DOSBox-X
check_and_update "DOSBox-X (DOS)" "dosbox-x*.AppImage"     "$(github_latest_url pkgforge-dev/DOSBox-X-AppImage '\.AppImage$' | grep -iv arm)" "dosbox-x-latest"

# Supermodel
check_and_update "Supermodel (Model 3)" "Supermodel*.AppImage"     "$(github_latest_url pkgforge-dev/Supermodel-AppImage '\.AppImage$' | grep -iv arm)" "Supermodel-latest"

# Ruffle — tar.gz binary
if [[ -f "$EMUS/ruffle" ]]; then
    printf "   %-32s" "Ruffle (Flash)"
    echo -e " ${CYAN}[tar.gz release — re-download to update]${NC}"
    if wt_yesno "Update" "Re-download latest?"; then
        RUFFLE_URL=$(curl -sfL "https://api.github.com/repos/ruffle-rs/ruffle/releases?per_page=3"             | grep -oP '"browser_download_url":\s*"\K[^"]*'             | grep -iP "linux.*x86.?64.*\.tar\.gz$" | grep -iv "debug\|arm" | head -1) || true
        if [[ -n "$RUFFLE_URL" ]]; then
            RUFFLE_TMP=$(mktemp -d)
            if curl -#fL "$RUFFLE_URL" | tar -xz -C "$RUFFLE_TMP" 2>/dev/null; then
                RUFFLE_BIN=$(find "$RUFFLE_TMP" -name "ruffle" -type f | head -1)
                [[ -n "$RUFFLE_BIN" ]] && mv "$RUFFLE_BIN" "$EMUS/ruffle" && chmod +x "$EMUS/ruffle" && ok "Ruffle updated"
            fi
            rm -rf "$RUFFLE_TMP"
        else
            warn "Could not find download URL"
        fi
    fi
    echo ""
fi

# SimCoupe — tar.gz binary from GitHub releases
if [[ -f "$EMUS/simcoupe" ]]; then
    printf "   %-32s" "SimCoupe (SAM Coupé)"
    echo -e " ${CYAN}[version-pinned — check https://simonowen.com/simcoupe/ for updates]${NC}"
    echo ""
fi

# Solarus — tar.gz binary from solarus-games.org
if [[ -f "$EMUS/solarus-run" ]]; then
    printf "   %-32s" "Solarus"
    echo -e " ${CYAN}[version-pinned — check https://www.solarus-games.org/download/ for updates]${NC}"
    echo ""
fi

check_and_update "Ryubing (Switch)" "ryujinx*.AppImage"     "$(github_latest_url Ryubing/Ryujinx 'x64\.AppImage$')" "ryujinx-latest"

echo ""
echo -e "${CYAN}RetroArch Cores:${NC}"
if wt_yesno "Update" "Update all cores from buildbot.libretro.com?"; then
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
# STEP 18: DESKTOP SHORTCUT
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Desktop shortcut..."

if [[ "$CREATE_SHORTCUT" == "yes" ]]; then
    DESKTOP_DIR="$HOME/.local/share/applications"
    mkdir -p "$DESKTOP_DIR"

    # Extract ES-DE icon from AppImage
    ESDE_APPIMAGE=$(find "$BASE" -maxdepth 1 -name 'ES-DE*.AppImage' | head -1)
    ICON_PATH="$BASE/ES-DE/es-de.png"
    if [[ -n "$ESDE_APPIMAGE" && ! -f "$ICON_PATH" ]]; then
        info "Extracting ES-DE icon..."
        ICON_TMP=$(mktemp -d)
        (cd "$ICON_TMP" && "$ESDE_APPIMAGE" --appimage-extract 2>/dev/null || true)
        # ES-DE stores its icon in various locations depending on version
        for ICON_SRC in             "$ICON_TMP/squashfs-root/usr/share/pixmaps/es-de.png"             "$ICON_TMP/squashfs-root/es-de.png"             "$ICON_TMP/squashfs-root/.DirIcon"             "$ICON_TMP/squashfs-root/usr/bin/es-de.png"; do
            if [[ -f "$ICON_SRC" ]]; then
                cp "$ICON_SRC" "$ICON_PATH"
                break
            fi
        done
        rm -rf "$ICON_TMP"
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
# STEP 19: SUMMARY
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

# ── Completion banner — width-aware so every line aligns regardless of
#    dynamic content length (counts, filenames, bundle path). ASCII-only
#    interior so ${#} measures display width correctly in any locale; the
#    border glyphs live only in the rule lines, which are fixed by construction.
BOX_W=60
box_rule()  { local i; printf '%s' "$1"; for ((i=0;i<BOX_W;i++)); do printf '═'; done; printf '%s\n' "$2"; }
box_blank() { printf '║%*s║\n' "$BOX_W" ""; }
box_line()  {
    local text="$1" len=${#1}
    if (( len >= BOX_W )); then
        printf '║ %s\n' "$text"          # graceful overflow for rare long lines
    else
        printf '║%s%*s║\n' "$text" $((BOX_W - len)) ""
    fi
}

box_rule '╔' '╗'
box_line "  Setup complete!"
box_rule '╠' '╣'
box_blank
box_line "  $APPIMAGE_COUNT AppImages downloaded"
box_line "  $CORE_COUNT RetroArch cores installed"
((DOWNLOAD_ERRORS > 0)) && box_line "  $DOWNLOAD_ERRORS download(s) need manual attention"
box_blank
box_line "  Downloaded emulators:"
for f in "$BASE"/*.AppImage "$EMUS"/*.AppImage "$EMUS"/xenia_canary; do
    [[ -f "$f" ]] && box_line "    - $(basename "$f")"
done
box_blank
box_line "  To start playing:"
box_line "    1. Add ROMs to ROMs/<system>/"
box_line "    2. Add BIOS files to ROMs/bios/"
box_line "    3. Run: ./launch.sh"
box_blank
box_line "  Bundle location:"
box_line "    $BASE"
box_blank
box_line "  Re-run this script anytime to retry failed downloads"
box_line "  or to update after a new ES-DE release."
box_rule '╚' '╝'
