#!/usr/bin/env bash
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

VERSION="1.1.0"
# (ES-DE is downloaded as the latest GitLab release; no pinned version.)

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


backup_file_if_changed() {
    local target="$1"
    local tmp="$2"
    local label="${3:-$(basename "$target")}" 

    if [[ ! -f "$tmp" ]]; then
        warn "$label temporary file was not created: $tmp"
        return 1
    fi

    if [[ -f "$target" ]]; then
        if cmp -s "$target" "$tmp"; then
            rm -f "$tmp"
            ok "$label unchanged, preserved"
            return 0
        fi

        local stamp backup
        stamp=$(date +%Y%m%d-%H%M%S)
        backup="$target.bak-$stamp"
        cp -a "$target" "$backup"
        info "$label changed, existing file backed up to $(basename "$backup")"
    fi

    mv -f "$tmp" "$target"
    ok "$label written"
}

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
# Detect package manager for auto-installing whiptail when missing.
# Sets PKG_INSTALL_CMD (array — runnable command) on mutable distros,
# or PKG_MANUAL_HINT (string) on immutable distros where auto-install
# isn't safe (rpm-ostree systems, SteamOS with read-only /usr).
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
DEFAULT_PATH="$(pwd)/ES-DE"

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
    "retroarch|RetroArch - libretro frontend (needed for cores)"
    " |── Nintendo ──────────────────────────────────"
    "dolphin|Dolphin - GameCube / Wii"
    "cemu|Cemu - Wii U"
    "ryujinx|Ryubing - Nintendo Switch (Ryujinx fork)"
    "eden|Eden - Nintendo Switch (alt fork)"
    "azahar|Azahar - Nintendo 3DS"
    "melonds|melonDS - Nintendo DS"
    "  |── Sony ─────────────────────────────────────"
    "duckstation|DuckStation - PlayStation 1"
    "pcsx2|PCSX2 - PlayStation 2"
    "rpcs3|RPCS3 - PlayStation 3"
    "shadps4|shadPS4 - PlayStation 4"
    "ppsspp|PPSSPP - PlayStation Portable"
    "   |── Microsoft ─────────────────────────────"
    "xemu|xemu - Original Xbox"
    "xenia|Xenia Canary - Xbox 360"
    "    |── Arcade and Pinball ─────────────────────"
    "mame|MAME (standalone) - arcade + fallback"
    "supermodel|Supermodel - Sega Model 3"
    "vpinball|Visual Pinball - virtual pinball tables"
    "     |── PC and Mobile ──────────────────────────"
    "_86box|86Box - Windows 9x / retro PC"
    "simcoupe|SimCoupé - SAM Coupé"
    "eka2l1|EKA2L1 - Symbian / N-Gage"
    "ruffle|Ruffle - Adobe Flash games"
    "scummvm|ScummVM - point-and-click adventures"
    "       |── Ports: Action, Platformer, Arcade ────────"
    "cdogs|C-Dogs SDL - top-down action engine"
    "cgenius|Commander Genius - Commander Keen engine"
    "nxengine|NXEngine - Cave Story engine"
    "opentyrian|OpenTyrian 2000 - Tyrian 2000 engine"
    "        |── Ports: Adventure and RPG ───────────────"
    "solarus|Solarus - Zelda-like RPGs"
    "         |── Ports: Strategy, Simulation, Management ─"
    "openttd|OpenTTD - Transport Tycoon Deluxe engine"
    "openra|OpenRA - Red Alert / Tiberian Dawn / Dune 2000"
)

# Section divider tags used in CORE_CHECKLIST to group cores visually.
# Detected and skipped at install time (they're labels, not installable items).
declare -A IS_SECTION_HEADER=(
    [Nintendo]=1 [Sega]=1 [Sony]=1 [Atari]=1 [NEC]=1 [SNK]=1
    [Arcade]=1 [Portable]=1 [Computers]=1 [Consoles]=1 [Fantasy]=1 [Other]=1
    [ ]=1 [  ]=1 [   ]=1 [    ]=1 [     ]=1
    [      ]=1 [       ]=1 [        ]=1 [         ]=1
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
    "vice_x128|VICE x128 — Commodore 128"
    "vice_xpet|VICE xpet — Commodore PET"
    "puae|PUAE — Commodore Amiga"
    "bluemsx|blueMSX — MSX/MSX2/Turbo R/Spectravideo/Coleco"
    "cap32|Caprice32 — Amstrad CPC / GX4000"
    "quasi88|Quasi88 — NEC PC-88 (alt)"
    "x1|X1 — Sharp X1"
    "px68k|PX68k — Sharp X68000"
    "b2|B2 — BBC Micro / BBC Master"
    "bk|BK — Elektronika BK (Soviet)"
    "ep128emu_core|ep128emu — Enterprise 128"
    "m2000|M2000 — Philips P2000T"
    "theodore|Theodore — Thomson MO/TO"
    "Consoles|─── Other consoles ───"
    "o2em|O2EM — Odyssey²/Videopac"
    "vecx|VecX — GCE Vectrex"
    "freechaf|FreeChaF — Fairchild Channel F"
    "freeintv|FreeIntv — Mattel Intellivision"
    "uzem|Uzem — Uzebox"
    "opera|Opera — 3DO Interactive Multiplayer"
    "amiarcadia|Amiarcadia — Emerson Arcadia 2001"
    "pd777|PD777 — Epoch Cassette Vision"
    "dice|DICE — discrete-logic arcade"
    "Fantasy|─── Fantasy consoles / engines ───"
    "retro8|Retro8 — PICO-8-compatible"
    "tic80|TIC-80 — fantasy console"
    "wasm4|WASM-4 — fantasy console"
    "lowresnx|LowRes NX — fantasy console"
    "lutro|Lutro — Lua game engine"
    "easyrpg|EasyRPG — RPG Maker 2000/2003"
    "Other|─── Other ───"
    "scummvm|ScummVM — point-and-click adventures"
    "dosbox_pure|DOSBox Pure — DOS (auto-runs zip/folder, no setup)"
)

SELECTIONS_CACHE="$BASE/.setup-selections.cfg"

detect_tui_tool() {
    if command -v whiptail >/dev/null 2>&1; then
        TUI_TOOL="whiptail"
    else
        TUI_TOOL=""
    fi
}

# (detect_pkg_manager is defined once near the top of the script.)

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
    local args=() entry key desc state selections _name _w

    # ── Emulator descriptions: align " - " per section ──
    local -a _emu_widths=()   # per-item pad width
    local -a _sec_items=()    # indices of items in current section
    local _sec_max=0 _idx=0
    for entry in "${EMULATOR_CHECKLIST[@]}"; do
        key="${entry%%|*}"; desc="${entry#*|}"
        if [[ -n "${IS_SECTION_HEADER[$key]:-}" ]]; then
            for _i in "${_sec_items[@]}"; do _emu_widths[$_i]=$_sec_max; done
            _sec_items=(); _sec_max=0; _emu_widths[$_idx]=0
        else
            _sec_items+=("$_idx")
            if [[ "$desc" == *" - "* ]]; then
                _name="${desc%% - *}"
                (( ${#_name} > _sec_max )) && _sec_max=${#_name}
            fi
        fi
        (( ++_idx ))
    done
    for _i in "${_sec_items[@]}"; do _emu_widths[$_i]=$_sec_max; done

    _idx=0
    for entry in "${EMULATOR_CHECKLIST[@]}"; do
        key="${entry%%|*}"; desc="${entry#*|}"
        if [[ -n "${IS_SECTION_HEADER[$key]:-}" ]]; then
            args+=("$key" "$desc" "OFF")
            (( ++_idx )); continue
        fi
        _w=${_emu_widths[$_idx]:-0}
        if (( _w > 0 )) && [[ "$desc" == *" - "* ]]; then
            _name="${desc%% - *}"
            desc=$(printf "%-${_w}s - %s" "$_name" "${desc#* - }")
        fi
        state="ON"
        [[ "${SELECTED_EMULATORS[$key]:-1}" == "0" ]] && state="OFF"
        args+=("$key" "$desc" "$state")
        (( ++_idx ))
    done
    selections=$(tui_checklist "Standalone Emulators" "Custom — Screen 1 of 2" "${args[@]}") \
        || { echo "Aborted."; exit 0; }
    SELECTED_EMULATORS=()
    for entry in "${EMULATOR_CHECKLIST[@]}"; do
        key="${entry%%|*}"
        [[ -n "${IS_SECTION_HEADER[$key]:-}" ]] && continue
        SELECTED_EMULATORS["$key"]=0
    done
    while IFS= read -r key; do
        [[ -z "$key" || -n "${IS_SECTION_HEADER[$key]:-}" ]] && continue
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

    # ── Core descriptions: align " — " per section ──
    args=()
    local -a _core_widths=()
    _sec_items=(); _sec_max=0; _idx=0
    for entry in "${CORE_CHECKLIST[@]}"; do
        key="${entry%%|*}"; desc="${entry#*|}"
        if [[ -n "${IS_SECTION_HEADER[$key]:-}" ]]; then
            for _i in "${_sec_items[@]}"; do _core_widths[$_i]=$_sec_max; done
            _sec_items=(); _sec_max=0; _core_widths[$_idx]=0
        else
            _sec_items+=("$_idx")
            if [[ "$desc" == *" — "* ]]; then
                _name="${desc%% — *}"
                (( ${#_name} > _sec_max )) && _sec_max=${#_name}
            fi
        fi
        (( ++_idx ))
    done
    for _i in "${_sec_items[@]}"; do _core_widths[$_i]=$_sec_max; done

    _idx=0
    for entry in "${CORE_CHECKLIST[@]}"; do
        key="${entry%%|*}"; desc="${entry#*|}"
        if [[ -n "${IS_SECTION_HEADER[$key]:-}" ]]; then
            args+=("$key" "$desc" "OFF")
        else
            _w=${_core_widths[$_idx]:-0}
            if (( _w > 0 )) && [[ "$desc" == *" — "* ]]; then
                _name="${desc%% — *}"
                desc=$(printf "%-${_w}s — %s" "$_name" "${desc#* — }")
            fi
            state="ON"
            [[ "${SELECTED_CORES[$key]:-1}" == "0" ]] && state="OFF"
            args+=("$key" "$desc" "$state")
        fi
        (( ++_idx ))
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
# core_selected — mode-aware membership check.
# Full mode: SELECTED_CORES is empty (no checklist was shown), so every core
# is installable. Custom mode: SELECTED_CORES was populated by the checklist,
# so a missing key means the core is NOT in CORE_CHECKLIST and must default
# to deselected — otherwise EASY-batch cores (bk, vice_x128, pd777, dice,
# ep128emu_core, m2000, vice_xpet, theodore, etc.) silently slip past
# a "RetroArch deselected" choice and still get pulled from the buildbot.
# (Closes In Progress #10.)
core_selected() {
    if (( ${#SELECTED_CORES[@]} > 0 )); then
        [[ "${SELECTED_CORES[$1]:-0}" == "1" ]]
    else
        true
    fi
}

tui_select_components

# ── Theme: Art Book Next (auto-installed, no prompt) ─────────────────────
# Earlier builds prompted the user to pick one of six themes. The bundle is
# tuned for Art Book Next specifically (the <theme> values in every custom
# es_systems entry are chosen against its logo set), so picking anything
# else just produced a worse-looking carousel. Now Art Book Next is
# installed automatically. Users who want a different theme can switch via
# ES-DE's built-in Theme Downloader (in-app) after setup.
EXISTING_THEMES=0
EXISTING_THEME_NAME=""
if [[ -d "$ESDE_DATA/themes" ]]; then
    EXISTING_THEMES=$(find "$ESDE_DATA/themes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    if ((EXISTING_THEMES > 0)); then
        # Prefer Art Book Next if it's one of the installed themes (matches
        # the bundle's <theme> tags); otherwise take whatever's first so the
        # generated es_settings.xml points at a theme that actually exists.
        # The old code unconditionally fell back to linear-es-de here, which
        # made a re-run silently change the theme on a bundle that already
        # had Art Book Next (or any other) installed.
        if [[ -d "$ESDE_DATA/themes/art-book-next-es-de" ]]; then
            EXISTING_THEME_NAME="art-book-next-es-de"
        else
            EXISTING_THEME_NAME=$(find "$ESDE_DATA/themes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
                                  | head -1 | xargs -r -I{} basename {})
        fi
    fi
fi
if ((EXISTING_THEMES > 0)); then
    THEME_NAME="$EXISTING_THEME_NAME"
    THEME_SKIP_REASON="already installed (${EXISTING_THEME_NAME:-unknown})"
else
    THEME_NAME="art-book-next-es-de"
    THEME_REPO="https://github.com/anthonycaccese/art-book-next-es-de/archive/refs/heads/main.zip"
    THEME_LABEL="Art Book Next"
    THEME_ZIPDIR="art-book-next-es-de-main"
fi

# ── RetroBat / ROM-collection import ──
# NOTE: import is no longer prompted here. The setup-time importer (former
# STEP 12) was a stale divergent copy of import-collection.sh (Audit F8) and
# has been removed. Collection import is now offered ONCE at the very end of
# setup (STEP 20) by invoking the single canonical importer. This guarantees
# one code path and removes the setup-vs-bundle drift entirely.

# ── Internal resolution ──
# Removed. Pre-seeding resolution into per-emulator configs proved unreliable:
# emulators rewrite their own configs on first launch (so pre-seeded values get
# overwritten), key names and file paths drift across versions, and RetroArch
# cores need per-core .opt files that only exist after the core has run once.
# The bundle now just gets out of the user's way — set video preferences in
# each emulator's own settings menu on first launch. The preserve-configs
# guards from In Progress #20 keep those settings intact on setup re-runs.

# ── Desktop shortcut ──
CREATE_SHORTCUT=""
if wt_yesno "Desktop Shortcut" \
"Create a desktop shortcut for ES-DE in your applications menu?

The shortcut will launch the portable ES-DE installed in this bundle."; then
    CREATE_SHORTCUT="yes"
fi
echo ""

# ── Preflight ──
for cmd in curl grep chmod unzip python3 file find sed awk sort tar realpath; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}ERROR: '$cmd' is required but not found.${NC}"
        exit 1
    fi
done

# The GitHub release-asset parsing below uses PCRE (grep -P, with \K). Not every
# grep build ships PCRE (notably BusyBox and BSD/macOS grep). Detect it up front
# with a clear message rather than letting each download silently find no asset.
if ! printf 'x\n' | grep -qP 'x' 2>/dev/null; then
    echo -e "${RED}ERROR: your 'grep' does not support PCRE (grep -P).${NC}"
    echo "This script parses GitHub release assets with grep -P. Install GNU grep"
    echo "(Debian/Ubuntu: 'sudo apt-get install grep'; Alpine/BusyBox: install the"
    echo "full GNU grep package) and re-run."
    exit 1
fi

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
    local resp url
    resp=$(curl -sfL -H "Accept: application/vnd.github+json" \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$repo/releases?per_page=10" 2>/dev/null) || true
    if [[ -z "$resp" ]]; then
        fail "Could not reach GitHub for $repo (offline or network blocked)"
        return 1
    fi
    if printf '%s' "$resp" | grep -q 'API rate limit exceeded'; then
        fail "GitHub API rate-limited (anonymous limit is 60/hour) — could not check $repo"
        warn "Wait ~1h and re-run, or 'export GITHUB_TOKEN=<token>' to raise the limit, then re-run."
        return 2
    fi
    url=$(printf '%s' "$resp" \
        | grep -oP '"browser_download_url":\s*"\K[^"]*' \
        | grep -P "$pattern" \
        | grep -ivE 'aarch|arm64|armv7|zsync|sha256|\.sig$|\.asc$' \
        | head -1) || true
    if [[ -z "$url" ]]; then
        fail "No matching asset for pattern in $repo releases (release exists, asset does not)"
        return 1
    fi
    info "Downloading $(basename "$url") ..."
    mkdir -p "$(dirname "$outfile")"
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
    if find "$outdir" -maxdepth 1 -iname 'rpcs3*.AppImage' 2>/dev/null | grep -q .; then
        ok "RPCS3 already exists, skipping"
    else
        info "Downloading RPCS3 (latest nightly) ..."
        if (cd "$outdir" && curl -#fJLO "https://rpcs3.net/latest-linux-x64"); then
            chmod +x "$outdir"/rpcs3*.AppImage 2>/dev/null || true
            ok "RPCS3 downloaded"
        else
            fail "RPCS3 download failed"
            return 1
        fi
    fi
    # squashfuse: needed by ps3-launch.sh to mount .squashfs disc images.
    # It is a system package — call the helper only if it exists in this
    # context (setup defines it; the importer's folded copy of this function
    # does not, hence the existence check).
    declare -F ensure_squashfuse_for_ps3 >/dev/null && ensure_squashfuse_for_ps3 || true
}

# Check for squashfuse; if missing, offer to install via the detected
# package manager. Never fails setup — at worst prints a notice telling the
# user how to install it themselves later. Distro-aware: apt/dnf/pacman/
# zypper/apk all covered.
ensure_squashfuse_for_ps3() {
    if command -v squashfuse >/dev/null 2>&1; then
        ok "squashfuse already installed (PS3 .squashfs games will mount)"
        return 0
    fi
    local pm="" cmd=""
    if   command -v apt-get >/dev/null 2>&1; then pm="apt";    cmd="sudo apt-get install -y squashfuse"
    elif command -v dnf     >/dev/null 2>&1; then pm="dnf";    cmd="sudo dnf install -y squashfuse"
    elif command -v pacman  >/dev/null 2>&1; then pm="pacman"; cmd="sudo pacman -S --noconfirm squashfuse"
    elif command -v zypper  >/dev/null 2>&1; then pm="zypper"; cmd="sudo zypper install -y squashfuse"
    elif command -v apk     >/dev/null 2>&1; then pm="apk";    cmd="sudo apk add squashfuse"
    fi
    if [[ -z "$pm" ]]; then
        warn "squashfuse not installed; could not detect your package manager."
        warn "Install it manually for PS3 .squashfs support."
        return 0
    fi
    echo ""
    info "PS3 collections often ship games as compressed .squashfs disc images."
    info "Mounting them requires the 'squashfuse' system package."
    if wt_yesno "Install squashfuse?" \
"PS3 .squashfs games need 'squashfuse' to mount. It is a system package (not bundled).

Detected package manager: $pm
Install command:
    $cmd

Install it now? (sudo password may be required.)

Choose No if you do not have sudo, prefer to install system packages yourself, or will only play PSN (.m3u) games — those work without squashfuse."; then
        if eval "$cmd"; then
            ok "squashfuse installed"
        else
            warn "squashfuse install command failed."
            warn "PS3 .squashfs games will not launch until you run manually:"
            warn "    $cmd"
        fi
    else
        warn "Skipped squashfuse install."
        warn "PS3 .squashfs games will NOT launch until you install it:"
        warn "    $cmd"
        warn "(PSN .m3u games will still work — they do not need squashfuse.)"
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
    # Pick the x64 AppImage from the release asset links. Match on the asset
    # NAME (reliably "ES-DE_x64.AppImage") — GitLab's direct_asset_url is a
    # permalink that does NOT contain the filename, so URL-only filtering fails.
    # Falls back to any AppImage, then to the first link, so this never does
    # worse than a blind first-asset pick.
    local api_json; api_json=$(curl -sfL "$api_url") || true
    dl_url=$(printf '%s' "$api_json" | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
links = (d.get("assets") or {}).get("links") or []
def u(l): return l.get("direct_asset_url") or l.get("url") or ""
def s(l): return ((l.get("name") or "") + " " + u(l)).lower()
def bad(t): return any(x in t for x in ["steamdeck","aarch64","arm64","armhf",".zsync",".sha",".sig",".asc",".deb",".rpm",".tar"])
for l in links:
    t = s(l)
    if ".appimage" in t and ("x64" in t or "x86_64" in t or "x86-64" in t) and not bad(t): print(u(l)); sys.exit(0)
for l in links:
    t = s(l)
    if ".appimage" in t and not bad(t): print(u(l)); sys.exit(0)
if links: print(u(links[0]))
') || true

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

    local tmpd; tmpd=$(mktemp -d "${TMPDIR:-/tmp}/esde-core.XXXXXX") || return 1
    if curl -sfL -o "$tmpd/$zip_name" "$CORE_BASE_URL/$zip_name" 2>/dev/null; then
        if unzip -qo "$tmpd/$zip_name" -d "$core_dir" 2>/dev/null; then
            rm -rf "$tmpd"
            return 0
        fi
    fi
    rm -rf "$tmpd"
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
        [quasi88]="PC-88 (alt)"

        # MAME — two versions because BIOS romsets are MAME-version-locked.
        # We ship mame (current) and mame2010 (0.139). mame2003_plus also exists
        # on the buildbot but is not shipped (no system defaults to it);
        # mame2014/2015/2016 were dropped or never built for Linux x86_64.
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
        [wasm4]="WASM-4"
        [potator]="Watara Supervision"
        [b2]="BBC Micro / BBC Master"
        [retro8]="PICO-8 (retro8 - free PICO-8-compatible core)"

        # EASY systems batch — 14 single-core systems. Each verified present
        # on the libretro Linux x86_64 buildbot (core-info repo).
        [bk]="Elektronika BK-0010/0011"
        [vice_x128]="Commodore 128"
        [pd777]="Epoch Cassette Vision"
        [dice]="DICE (discrete-logic arcade)"
        [ep128emu_core]="Enterprise 64/128"
        [m2000]="Philips P2000T"
        [vice_xpet]="Commodore PET"
        [theodore]="Thomson MO/TO"
        # NOTE: bennugd_libretro.so.zip 404s on the Linux x86_64 buildbot
        # (https://buildbot.libretro.com/nightly/linux/x86_64/latest/) —
        # the core-info file exists but no binary is built. The es_systems
        # entry, ROMs/bennugd folder, and SYS_TO_CORE mapping have all been
        # removed so no dead/unlaunchable system is shown. To re-add bennugd
        # later: confirm the URL returns HTTP 200, uncomment the line below,
        # and restore the es_systems <system>, ROM_DIRS entry, and
        # SYS_TO_CORE mapping.
        # [bennugd]="BennuGD game engine"
    )

    local total=${#CORES[@]}
    local downloaded=0
    local skipped=0
    local failed=0

    # Quick reachability probe BEFORE starting downloads. Sends a HEAD
    # request to each core URL and warns about any that 404. Catches the
    # case where the libretro-core-info repo lists a core but the buildbot
    # does not actually ship a Linux x86_64 binary (e.g. bennugd) — the
    # download itself would just silently fail with curl exit 22.
    # Why this matters: previous failure mode was "info-repo presence
    # claimed core exists -> setup tries download -> silent [fail] line in
    # the log -> user wonders why a system does not work." This surfaces
    # the missing core upfront with a clear name.
    # Build list of cores to actually probe — skip ones we already have on
    # disk (a re-run typically caches almost everything, dropping the probe
    # from 60-80 URLs to a handful). Progress is printed per-URL so the user
    # can see it isn't frozen on slow networks.
    local -a probe_list=()
    for core_name in "${!CORES[@]}"; do
        core_selected "$core_name" || continue
        [[ -f "$core_dir/${core_name}_libretro.so" ]] && continue
        probe_list+=("$core_name")
    done

    local to_probe=${#probe_list[@]}
    if (( to_probe == 0 )); then
        info "All $total selected cores already cached — skipping buildbot check"
    else
        info "Checking buildbot for $to_probe new core(s) (of $total selected)..."
        local unreachable=()
        local i=0
        for core_name in "${probe_list[@]}"; do
            i=$((i+1))
            printf "   [%d/%d] %-30s" "$i" "$to_probe" "$core_name"
            local url="$CORE_BASE_URL/${core_name}_libretro.so.zip"
            local code
            code=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 8 "$url" 2>/dev/null || echo "000")
            if [[ "$code" == "200" ]]; then
                printf " %b\n" "${GREEN}ok${NC}"
            else
                printf " %b\n" "${RED}$code${NC}"
                unreachable+=("$core_name ($code)")
            fi
        done
        if (( ${#unreachable[@]} > 0 )); then
            warn "${#unreachable[@]} core(s) not currently available on the buildbot:"
            for u in "${unreachable[@]}"; do warn "    $u"; done
            warn "These will be skipped. The matching system entries will still appear"
            warn "in ES-DE but launching their ROMs will fail until the core is built."
            echo ""
        fi
    fi

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
TOTAL_STEPS=19

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
    cps1 cps2 cps3 dos dreamcast famicom fds gamegear
    gb gba gbc gc genesis intellivision mastersystem megacd megadrive
    msx msx2 n3ds n64 nds neogeo neogeocd nes ngp ngpc odyssey2
    pc pcengine pcenginecd pcfx pico8 pokemini ports ps2 ps3
    psp psx saturn scummvm sega32x segacd sg-1000 snes
    supergrafx switch tg-cd tg16 ti99 uzebox vectrex vic20 videopac
    virtualboy wii wiiu wonderswan wonderswancolor x68000
    xbox xbox360 zx81 zxspectrum
    ps4 win98 windows
    sfc n64dd wiiware megadrivejp saturnjp amiga500 amiga1200 videopacplus vpinball
    archimedes adam dragon32 fm7 supracan bbcmicro apple2 fbneo
    gx4000 markiii multivision amigacdtv sufami msx1
    aquarius atom coco electron gp32 pegasus socrates tutor vis
    bk c128 cassettevision dice enterprise
    p2000t pet thomson
    fmtowns
    bios
)
for dir in "${ROM_DIRS[@]}"; do mkdir -p "$ROMS/$dir"; done

# Art Book Next does not provide artwork for many standalone ports/engines.
# Keep those entries inside the generic ES-DE "ports" system so the theme stays
# clean, while the launchers below still call the bundled AppImages.
write_port_launcher() {
    local label="$1" pattern="$2"; shift 2
    local out="$ROMS/ports/${label}.sh"
    local tmp="$out.tmp.$$"
    cat > "$tmp" <<PORT_LAUNCHER
#!/usr/bin/env bash
set -euo pipefail
BASE="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/../.." && pwd)"
EMUS="\$BASE/Emulators"
export HOME="\$BASE"
export XDG_CONFIG_HOME="\$BASE/.config"
export XDG_DATA_HOME="\$BASE/.local/share"
export XDG_STATE_HOME="\$BASE/.local/state"
export XDG_CACHE_HOME="\$BASE/.cache"
mkdir -p "\$XDG_CONFIG_HOME" "\$XDG_DATA_HOME" "\$XDG_STATE_HOME" "\$XDG_CACHE_HOME"
mapfile -t matches < <(find "\$EMUS" -mindepth 2 -maxdepth 2 -type f -iname "$pattern" 2>/dev/null | sort)
# Fallback: also accept a still-flat AppImage from an older install layout.
if [[ \${#matches[@]} -eq 0 ]]; then
    mapfile -t matches < <(find "\$EMUS" -maxdepth 1 -type f -iname "$pattern" 2>/dev/null | sort)
fi
if [[ \${#matches[@]} -eq 0 ]]; then
    echo "Missing AppImage: $pattern" >&2
    echo "Run the ES-DE Portable setup again, or place the AppImage in: \$EMUS" >&2
    exit 1
fi
app="\${matches[0]}"
chmod +x "\$app" 2>/dev/null || true
# The AppImage lives in its OWN folder, Emulators/<Port>/. Run the engine from
# that folder so it finds user-supplied game data placed right beside it
# (Commander Genius -> Keen game files, Cave Story -> data/, OpenTyrian -> Tyrian
# data, etc.). These engines look next to their own binary, which is why a flat
# Emulators/ layout forced data into the shared root. Same folder = found.
DATA="\$(dirname "\$app")"
if [[ ! -e "\$DATA/_PUT-GAME-DATA-HERE.txt" ]]; then
    cat > "\$DATA/_PUT-GAME-DATA-HERE.txt" <<'PORTNOTE'
Put this port's game data in THIS folder — right beside the AppImage — e.g.:
  Commander Genius      -> Commander Keen episode game files
  OpenTyrian 2000       -> Tyrian data files (freely redistributable)
  Cave Story (NXEngine) -> the Cave Story data/ folder (freeware)
The launcher runs the engine from this folder, so files here are found
automatically. Preserved across setup re-runs and update.sh.
PORTNOTE
fi
cd "\$DATA"
exec "\$app" "\$@"
PORT_LAUNCHER
    backup_file_if_changed "$out" "$tmp" "port: ${label}.sh"
    chmod +x "$out"
}

write_port_launcher "Commander Genius" "Commander-Genius*.AppImage"
write_port_launcher "C-Dogs SDL" "C-Dogs_SDL*.AppImage"
write_port_launcher "OpenTyrian 2000" "OpenTyrian2000*.AppImage"
write_port_launcher "OpenRA" "OpenRA*.AppImage"
write_port_launcher "Cave Story (NXEngine)" "NXEngine*.AppImage"
write_port_launcher "OpenTTD (Transport Tycoon)" "OpenTTD*.AppImage"

ok "Directory tree created"


# Clean up orphaned files from older builds. verify-bios.sh, install-core.sh
# and install-emulator.sh were once separate bundle scripts (now folded into
# import-collection.sh); dosbox-x-portable.sh was the DOSBox-X wrapper
# (DOSBox-X is no longer bundled — DOS uses the DOSBox Pure core). On a
# re-run over an older bundle, remove these stale files.
for orphan in verify-bios.sh install-core.sh install-emulator.sh dosbox-x-portable.sh; do
    if [[ -f "$BASE/$orphan" ]]; then
        RETIRED_DIR="$BASE/.retired-setup-files"
        mkdir -p "$RETIRED_DIR"
        stamp=$(date +%Y%m%d-%H%M%S)
        mv "$BASE/$orphan" "$RETIRED_DIR/$orphan.$stamp"
        info "Retired old $orphan to .retired-setup-files/"
    fi
done

#=============================================================================
# STEP 2: PORTABLE.TXT
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Creating portable.txt..."
touch "$BASE/portable.txt"
# Record the install location. launch.sh compares this to its own runtime
# directory and heals baked absolute paths (retroarch.cfg, es_find_rules.xml)
# when the bundle has been moved to a different drive or folder.
printf '%s\n' "$BASE" > "$BASE/.bundle-path"
ok "portable.txt created"

#=============================================================================
# STEP 3: ES_FIND_RULES.XML
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing es_find_rules.xml..."

# Write find rules with absolute paths baked in at setup time.
# %ESPATH% cannot be used — it resolves to the AppImage's internal temp mount,
# not the bundle directory on disk.
FIND_RULES_FILE="$ESDE_DATA/custom_systems/es_find_rules.xml"
FIND_RULES_TMP="$FIND_RULES_FILE.tmp.$$"
python3 - "$FIND_RULES_TMP" "$EMUS" << 'PYEOF'
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
emu('PCSX2', [fp('pcsx2-portable.sh'), fp('pcsx2*.AppImage'), fp('PCSX2*.AppImage'),
    '/var/lib/flatpak/exports/bin/net.pcsx2.PCSX2'], ['pcsx2-qt']),
'',
emu('RPCS3', [fp('rpcs3-portable.sh'), fp('rpcs3*.AppImage'), fp('RPCS3*.AppImage'),
    '/var/lib/flatpak/exports/bin/net.rpcs3.RPCS3'], ['rpcs3']),
'',
# PS3LAUNCH: bundle wrapper that dispatches by extension (.psn/.m3u read
# the payload + launch the resolved dev_hdd0 EBOOT.BIN; .squashfs mounts
# via squashfuse then launches the inner EBOOT.BIN; .iso/.pkg pass through).
emu('PS3LAUNCH', [fp('ps3-launch.sh')], []),
'',
emu('DUCKSTATION', [fp('DuckStation*.AppImage'), fp('duckstation*.AppImage'),
    '/var/lib/flatpak/exports/bin/org.duckstation.DuckStation'], ['duckstation-qt']),
'',
emu('PPSSPP', [fp('ppsspp-portable.sh'), fp('PPSSPP*.AppImage'), fp('ppsspp*.AppImage'),
    '/var/lib/flatpak/exports/bin/org.ppsspp.PPSSPP'], ['PPSSPPQt']),
'',
emu('MELONDS', [fp('melonds-portable.sh'), fp('melonDS*.AppImage'),
    '/var/lib/flatpak/exports/bin/net.kuribo64.melonDS'], ['melonDS']),
'',
emu('MGBA', [fp('mGBA*.AppImage'), fp('mgba*')], ['mgba-qt']),
'',
emu('CEMU', [fp('cemu-portable.sh'), fp('Cemu*.AppImage'), fp('cemu*.AppImage'),
    '/var/lib/flatpak/exports/bin/info.cemu.Cemu'], ['cemu']),
'',
emu('RMG', [fp('RMG*.AppImage'),
    '/var/lib/flatpak/exports/bin/com.github.Rosalie241.RMG'], ['RMG']),
'',
'',
emu('MAME', [fp('mame*.AppImage')], ['mame']),
'',
emu('FLYCAST', [fp('flycast*.AppImage')], ['flycast']),
'',
emu('RYUBING', [fp('Ryubing*.AppImage'), fp('ryubing*.AppImage'), fp('ryujinx*.AppImage')], ['Ryubing']),
'',
emu('EDEN', [fp('eden-portable.sh'), fp('Eden*.AppImage'), fp('eden*.AppImage')], ['eden']),
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
emu('XEMU', [fp('xemu-portable.sh'), fp('xemu*.AppImage'),
    '/var/lib/flatpak/exports/bin/app.xemu.xemu'], ['xemu']),
'',
emu('XENIA', [fp('xenia*.AppImage'), fp('xenia_canary')], ['xenia_canary']),
'',
emu('AZAHAR', [fp('azahar-portable.sh'), fp('azahar*.AppImage'), fp('Azahar*.AppImage')], ['azahar']),
'',
emu('GEARGRAFX', [fp('Geargrafx*.AppImage')], ['geargrafx']),
'',
# MESEN: handled via mesen_libretro core in RetroArch — no standalone needed
'',
emu('SIMCOUPE', [fp('simcoupe-portable.sh'), fp('SimCoupe*.AppImage'), fp('simcoupe')], ['simcoupe', 'SimCoupe']),
'',
emu('CGENIUS', [fp('Commander-Genius*.AppImage'), fp('Commander_Genius*.AppImage'), fp('cgenius*.AppImage')], ['CommanderGenius', 'cgenius']),
'',
emu('CDOGS', [fp('C-Dogs_SDL*.AppImage'), fp('C-Dogs*.AppImage'), fp('cdogs*.AppImage')], ['cdogs-sdl', 'cdogs']),
'',
emu('OPENTYRIAN', [fp('OpenTyrian2000*.AppImage'), fp('OpenTyrian*.AppImage'), fp('opentyrian*.AppImage')], ['opentyrian2000', 'opentyrian']),
'',
emu('OPENRA', [fp('OpenRA*.AppImage'), fp('openra*.AppImage')], ['openra']),
'',
emu('SUPERMODEL', [fp('supermodel-portable.sh'), fp('supermodel*.AppImage'), fp('Supermodel*.AppImage'), fp('supermodel')], ['supermodel']),
'',
emu('SOLARUS', [fp('solarus-run*.AppImage'), fp('solarus-portable.sh'), fp('solarus-run')], ['solarus-run']),
'',
'',
'',
emu('OPENTTD', [fp('OpenTTD*.AppImage'), fp('openttd*.AppImage')], ['openttd']),
'',
emu('RUFFLE', [fp('ruffle-portable.sh'), fp('ruffle*.AppImage'), fp('ruffle')], ['ruffle']),
'',
emu('EKA2L1', [fp('eka2l1-portable.sh'), fp('eka2l1*.AppImage'), fp('eka2l1')], ['eka2l1']),
'',
emu('VPINBALL',
    [fp('VPinball/vpinball-portable.sh'), fp('VPinball/VPinballX_BGFX'), fp('VPinball/VPinballX_GL')],
    ['vpinball-portable.sh', 'VPinballX_BGFX', 'VPinballX_GL']),
'',
'</ruleList>']

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w') as f:
    f.write('\n'.join(xml) + '\n')
print(f"Written: {out_path}")
PYEOF
backup_file_if_changed "$FIND_RULES_FILE" "$FIND_RULES_TMP" "es_find_rules.xml"

# ── Write custom es_systems.xml: portable overrides + custom systems ──
# Portable overrides replace selected built-in systems so they call bundled emulators/cores;
# split-out custom systems still use the parent platform/theme where appropriate.
CUSTOM_SYSTEMS_FILE="$ESDE_DATA/custom_systems/es_systems.xml"
CUSTOM_SYSTEMS_TMP="$CUSTOM_SYSTEMS_FILE.tmp.$$"
cat > "$CUSTOM_SYSTEMS_TMP" << 'CUSTOMSYSTEMS'
<?xml version="1.0"?>
<systemList>
  <!-- Portable overrides: Sega CD / Mega-CD use the bundled RetroArch
       and bundled libretro cores instead of whatever ES-DE finds on the host.
       This also exposes .m3u and .chd explicitly for multi-disc CD sets. -->
  <system>
    <name>segacd</name>
    <fullname>Sega CD</fullname>
    <path>%ROMPATH%/segacd</path>
    <extension>.m3u .M3U .chd .CHD .cue .CUE .iso .ISO .bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="Genesis Plus GX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/genesis_plus_gx_libretro.so %ROM%</command>
    <command label="PicoDrive">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/picodrive_libretro.so %ROM%</command>
    <platform>segacd</platform>
    <theme>segacd</theme>
  </system>

  <system>
    <name>megacd</name>
    <fullname>Sega Mega-CD</fullname>
    <path>%ROMPATH%/megacd</path>
    <extension>.m3u .M3U .chd .CHD .cue .CUE .iso .ISO .bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="Genesis Plus GX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/genesis_plus_gx_libretro.so %ROM%</command>
    <command label="PicoDrive">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/picodrive_libretro.so %ROM%</command>
    <platform>segacd</platform>
    <theme>megacd</theme>
  </system>

  <system>
    <name>ps3</name>
    <fullname>Sony PlayStation 3</fullname>
    <path>%ROMPATH%/ps3</path>
    <extension>.m3u .M3U .squashfs .SQUASHFS .pkg .PKG .iso .ISO .zip .ZIP</extension>
    <!-- Default command uses the bundled ps3-launch.sh wrapper, which knows
         how to handle the .psn/.m3u text-payload pointers, mount .squashfs
         disc images via squashfuse, and pass .iso/.pkg straight through.
         The raw RPCS3 command is kept as an alternative for sources where
         the user wants the emulator to handle the file directly. -->
    <command label="RPCS3 (auto)">%EMULATOR_PS3LAUNCH% %ROM%</command>
    <command label="RPCS3 (raw)">%EMULATOR_RPCS3% %ROM%</command>
    <platform>ps3</platform>
    <theme>ps3</theme>
  </system>

  <system>
    <name>ps3psn</name>
    <fullname>PlayStation 3 (PSN / Digital)</fullname>
    <path>%ROMPATH%/ps3psn</path>
    <extension>.m3u .M3U .pkg .PKG .rap .RAP</extension>
    <command label="RPCS3 (auto)">%EMULATOR_PS3LAUNCH% %ROM%</command>
    <command label="RPCS3 (raw)">%EMULATOR_RPCS3% %ROM%</command>
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
    <extension>.exe .EXE .com .COM .bat .BAT .conf .CONF .zip .ZIP .7z .7Z .dosz .DOSZ</extension>
    <!-- DOSBox Pure (libretro) auto-mounts and auto-runs a .zip / .dosz /
         game folder with no per-game dosbox.conf — this is what ES-DE
         itself defaults to for dos and is the experience the bundle is
         after. Standalone DOSBox-X is intentionally not bundled. -->
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

  <!-- Art Book Next safe Ports system. Standalone ports/engines are exposed
       as executable .sh launchers under ROMs/ports instead of separate themed
       systems, so unsupported logos/artwork do not appear broken. -->
  <system>
    <name>ports</name>
    <fullname>Ports</fullname>
    <path>%ROMPATH%/ports</path>
    <extension>.sh .SH .desktop .DESKTOP</extension>
    <command label="Launch">bash %ROM%</command>
    <platform>pc</platform>
    <theme>ports</theme>
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

  <!-- Cartridge-based MAME micro-consoles (added batch 1 of the Easy roadmap).
       Same proven -cart template as gamate/scv/pv1000 above; mame core is bundled. -->
  <system>
    <name>advision</name>
    <fullname>Entex Adventure Vision</fullname>
    <path>%ROMPATH%/advision</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "advision -rompath \"%GAMEDIRRAW%;%ROMPATH%/advision;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "advision -rompath \"%GAMEDIRRAW%;%ROMPATH%/advision;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>advision</platform>
    <theme>advision</theme>
  </system>

  <system>
    <name>apfm1000</name>
    <fullname>APF Imagination Machine / M1000</fullname>
    <path>%ROMPATH%/apfm1000</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "apfm1000 -rompath \"%GAMEDIRRAW%;%ROMPATH%/apfm1000;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "apfm1000 -rompath \"%GAMEDIRRAW%;%ROMPATH%/apfm1000;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>apfm1000</platform>
    <theme>apfm1000</theme>
  </system>

  <system>
    <name>astrocade</name>
    <fullname>Bally Astrocade</fullname>
    <path>%ROMPATH%/astrocade</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "astrocde -rompath \"%GAMEDIRRAW%;%ROMPATH%/astrocade;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "astrocde -rompath \"%GAMEDIRRAW%;%ROMPATH%/astrocade;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>astrocde</platform>
    <theme>astrocade</theme>
  </system>

  <system>
    <name>gamepock</name>
    <fullname>Epoch Game Pocket Computer</fullname>
    <path>%ROMPATH%/gamepock</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "gamepock -rompath \"%GAMEDIRRAW%;%ROMPATH%/gamepock;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "gamepock -rompath \"%GAMEDIRRAW%;%ROMPATH%/gamepock;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>gamepock</platform>
    <theme>gamepock</theme>
  </system>

  <system>
    <name>loopy</name>
    <fullname>Casio Loopy</fullname>
    <path>%ROMPATH%/loopy</path>
    <extension>.bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "casloopy -rompath \"%GAMEDIRRAW%;%ROMPATH%/loopy;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "casloopy -rompath \"%GAMEDIRRAW%;%ROMPATH%/loopy;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <platform>loopy</platform>
    <theme>loopy</theme>
  </system>

  <!-- ── Logo de-merge: systems split out from combined folders so each
       uses its own Art Book Next logo instead of borrowing the parent's.
       <theme> is set to the theme's logo name; emulator/core matches the
       parent system the games actually run on. ── -->
  <system>
    <name>gx4000</name>
    <fullname>Amstrad GX4000</fullname>
    <path>%ROMPATH%/gx4000</path>
    <extension>.dsk .DSK .cpr .CPR .cdt .CDT .zip .ZIP .7z .7Z</extension>
    <command label="Caprice32">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/cap32_libretro.so %ROM%</command>
    <platform>amstradcpc</platform>
    <theme>gx4000</theme>
  </system>

  <system>
    <name>markiii</name>
    <fullname>Sega Mark III</fullname>
    <path>%ROMPATH%/markiii</path>
    <extension>.sms .SMS .bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="Genesis Plus GX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/genesis_plus_gx_libretro.so %ROM%</command>
    <platform>mastersystem</platform>
    <theme>mark3</theme>
  </system>

  <system>
    <name>multivision</name>
    <fullname>Tsukuda Original Othello Multivision</fullname>
    <path>%ROMPATH%/multivision</path>
    <extension>.sg .SG .bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="Genesis Plus GX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/genesis_plus_gx_libretro.so %ROM%</command>
    <platform>sg-1000</platform>
    <theme>multivision</theme>
  </system>

  <system>
    <name>amigacdtv</name>
    <fullname>Commodore CDTV</fullname>
    <path>%ROMPATH%/amigacdtv</path>
    <extension>.adf .ADF .hdf .HDF .lha .LHA .iso .ISO .cue .CUE .ccd .CCD .nrg .NRG .m3u .M3U .zip .ZIP .7z .7Z</extension>
    <command label="PUAE">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/puae_libretro.so %ROM%</command>
    <platform>cdtv</platform>
    <theme>cdtv</theme>
  </system>

  <system>
    <name>nes-msu</name>
    <fullname>Nintendo Entertainment System (ProjectNested MSU-1)</fullname>
    <path>%ROMPATH%/nes/nes-msu</path>
    <extension>.sfc .smc .bs .st .SFC .SMC</extension>
    <command label="Snes9x">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/snes9x_libretro.so %ROM%</command>
    <platform>nes</platform>
    <theme>nes</theme>
  </system>

  <system>
    <name>sufami</name>
    <fullname>SNES Sufami Turbo</fullname>
    <path>%ROMPATH%/sufami</path>
    <extension>.sfc .smc .st .bs .zip .7z .SFC .SMC .ZIP .7Z</extension>
    <command label="Snes9x">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/snes9x_libretro.so %ROM%</command>
    <platform>snes</platform>
    <theme>sufami</theme>
  </system>

  <system>
    <name>msx1</name>
    <fullname>MSX1</fullname>
    <path>%ROMPATH%/msx1</path>
    <extension>.rom .ri .mx1 .mx2 .col .dsk .cas .sg .sc .m3u .zip .7z .ROM .RI .MX1 .MX2 .COL .DSK .CAS .SG .SC .M3U .ZIP .7Z</extension>
    <command label="blueMSX">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/bluemsx_libretro.so %ROM%</command>
    <platform>msx</platform>
    <theme>msx1</theme>
  </system>

  <system>
    <name>fbneo</name>
    <fullname>FinalBurn Neo</fullname>
    <path>%ROMPATH%/fbneo</path>
    <extension>.zip .ZIP .7z .7Z .chd .CHD</extension>
    <command label="FB Neo">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/fbneo_libretro.so %ROM%</command>
    <command label="MAME">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "%BASENAME% -rompath \"%GAMEDIRRAW%;%ROMPATH%/fbneo;%ROMPATH%/bios\""</command>
    <platform>arcade</platform>
    <theme>fbneo</theme>
  </system>


  <!-- ── EASY systems batch: 9 MAME-driver computers/consoles.
       core: mame (already bundled). Multi-media machines get one
       labelled command per slot (Tape/Diskette/Cartridge/...). ── -->

  <system>
    <name>aquarius</name>
    <fullname>Mattel Aquarius</fullname>
    <path>%ROMPATH%/aquarius</path>
    <extension>.bin .BIN .rom .ROM .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "aquarius -rompath \"%GAMEDIRRAW%;%ROMPATH%/aquarius;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "aquarius -rompath \"%GAMEDIRRAW%;%ROMPATH%/aquarius;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (Standalone)">%EMULATOR_MAME% aquarius -rompath "%GAMEDIRRAW%;%ROMPATH%/aquarius;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <platform>aquarius</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>atom</name>
    <fullname>Acorn Atom</fullname>
    <path>%ROMPATH%/atom</path>
    <extension>.atm .ATM .tap .TAP .uef .UEF .wav .WAV .csw .CSW .dsk .DSK .40t .40T .bin .BIN .rom .ROM .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Tape]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "atom -rompath \"%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios\" -cass \"%ROMRAW%\""</command>
    <command label="MAME [Tape] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "atom -rompath \"%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios\" -cass \"%ROMRAW%\""</command>
    <command label="MAME [Tape] (Standalone)">%EMULATOR_MAME% atom -rompath "%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios" -cass "%ROMRAW%"</command>
    <command label="MAME [Diskette]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "atom -rompath \"%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Diskette] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "atom -rompath \"%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Diskette] (Standalone)">%EMULATOR_MAME% atom -rompath "%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <command label="MAME [Quickload]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "atom -rompath \"%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios\" -quik \"%ROMRAW%\""</command>
    <command label="MAME [Quickload] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "atom -rompath \"%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios\" -quik \"%ROMRAW%\""</command>
    <command label="MAME [Quickload] (Standalone)">%EMULATOR_MAME% atom -rompath "%GAMEDIRRAW%;%ROMPATH%/atom;%ROMPATH%/bios" -quik "%ROMRAW%"</command>
    <platform>atom</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>coco</name>
    <fullname>TRS-80 Color Computer</fullname>
    <path>%ROMPATH%/coco</path>
    <extension>.ccc .CCC .rom .ROM .bin .BIN .dsk .DSK .dmk .DMK .jvc .JVC .os9 .OS9 .vdk .VDK .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "coco -rompath \"%GAMEDIRRAW%;%ROMPATH%/coco;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "coco -rompath \"%GAMEDIRRAW%;%ROMPATH%/coco;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (Standalone)">%EMULATOR_MAME% coco -rompath "%GAMEDIRRAW%;%ROMPATH%/coco;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <command label="MAME [Diskette]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "coco -rompath \"%GAMEDIRRAW%;%ROMPATH%/coco;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Diskette] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "coco -rompath \"%GAMEDIRRAW%;%ROMPATH%/coco;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Diskette] (Standalone)">%EMULATOR_MAME% coco -rompath "%GAMEDIRRAW%;%ROMPATH%/coco;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <platform>coco</platform>
    <theme>coco</theme>
  </system>

  <system>
    <name>electron</name>
    <fullname>Acorn Electron</fullname>
    <path>%ROMPATH%/electron</path>
    <extension>.uef .UEF .csw .CSW .wav .WAV .ssd .SSD .bbc .BBC .img .IMG .dsd .DSD .adf .ADF .rom .ROM .bin .BIN .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Tape]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "electron -rompath \"%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios\" -cass \"%ROMRAW%\""</command>
    <command label="MAME [Tape] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "electron -rompath \"%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios\" -cass \"%ROMRAW%\""</command>
    <command label="MAME [Tape] (Standalone)">%EMULATOR_MAME% electron -rompath "%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios" -cass "%ROMRAW%"</command>
    <command label="MAME [Diskette]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "electron -rompath \"%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Diskette] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "electron -rompath \"%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Diskette] (Standalone)">%EMULATOR_MAME% electron -rompath "%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "electron -rompath \"%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios\" -cart1 \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "electron -rompath \"%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios\" -cart1 \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (Standalone)">%EMULATOR_MAME% electron -rompath "%GAMEDIRRAW%;%ROMPATH%/electron;%ROMPATH%/bios" -cart1 "%ROMRAW%"</command>
    <platform>electron</platform>
    <theme>electron</theme>
  </system>

  <system>
    <name>gp32</name>
    <fullname>Game Park 32</fullname>
    <path>%ROMPATH%/gp32</path>
    <extension>.smc .SMC .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "gp32 -rompath \"%GAMEDIRRAW%;%ROMPATH%/gp32;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "gp32 -rompath \"%GAMEDIRRAW%;%ROMPATH%/gp32;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (Standalone)">%EMULATOR_MAME% gp32 -rompath "%GAMEDIRRAW%;%ROMPATH%/gp32;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <platform>gp32</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>pegasus</name>
    <fullname>Aamber Pegasus</fullname>
    <path>%ROMPATH%/pegasus</path>
    <extension>.bin .BIN .rom .ROM .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "pegasus -rompath \"%GAMEDIRRAW%;%ROMPATH%/pegasus;%ROMPATH%/bios\" -cart1 \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "pegasus -rompath \"%GAMEDIRRAW%;%ROMPATH%/pegasus;%ROMPATH%/bios\" -cart1 \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (Standalone)">%EMULATOR_MAME% pegasus -rompath "%GAMEDIRRAW%;%ROMPATH%/pegasus;%ROMPATH%/bios" -cart1 "%ROMRAW%"</command>
    <command label="MAME [ROM]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "pegasus -rompath \"%GAMEDIRRAW%;%ROMPATH%/pegasus;%ROMPATH%/bios\" -rom1 \"%ROMRAW%\""</command>
    <command label="MAME [ROM] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "pegasus -rompath \"%GAMEDIRRAW%;%ROMPATH%/pegasus;%ROMPATH%/bios\" -rom1 \"%ROMRAW%\""</command>
    <command label="MAME [ROM] (Standalone)">%EMULATOR_MAME% pegasus -rompath "%GAMEDIRRAW%;%ROMPATH%/pegasus;%ROMPATH%/bios" -rom1 "%ROMRAW%"</command>
    <platform>pegasus</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>socrates</name>
    <fullname>VTech Socrates</fullname>
    <path>%ROMPATH%/socrates</path>
    <extension>.bin .BIN .rom .ROM .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "socrates -rompath \"%GAMEDIRRAW%;%ROMPATH%/socrates;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "socrates -rompath \"%GAMEDIRRAW%;%ROMPATH%/socrates;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (Standalone)">%EMULATOR_MAME% socrates -rompath "%GAMEDIRRAW%;%ROMPATH%/socrates;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <platform>socrates</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>tutor</name>
    <fullname>Tomy Tutor</fullname>
    <path>%ROMPATH%/tutor</path>
    <extension>.bin .BIN .rom .ROM .zip .ZIP .7z .7Z</extension>
    <command label="MAME [Cartridge]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "tutor -rompath \"%GAMEDIRRAW%;%ROMPATH%/tutor;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "tutor -rompath \"%GAMEDIRRAW%;%ROMPATH%/tutor;%ROMPATH%/bios\" -cart \"%ROMRAW%\""</command>
    <command label="MAME [Cartridge] (Standalone)">%EMULATOR_MAME% tutor -rompath "%GAMEDIRRAW%;%ROMPATH%/tutor;%ROMPATH%/bios" -cart "%ROMRAW%"</command>
    <platform>tutor</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>vis</name>
    <fullname>Tandy VIS</fullname>
    <path>%ROMPATH%/vis</path>
    <extension>.chd .CHD .iso .ISO .cue .CUE .zip .ZIP .7z .7Z</extension>
    <command label="MAME [CD-ROM]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "vis -rompath \"%GAMEDIRRAW%;%ROMPATH%/vis;%ROMPATH%/bios\" -cdrom \"%ROMRAW%\""</command>
    <command label="MAME [CD-ROM] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "vis -rompath \"%GAMEDIRRAW%;%ROMPATH%/vis;%ROMPATH%/bios\" -cdrom \"%ROMRAW%\""</command>
    <command label="MAME [CD-ROM] (Standalone)">%EMULATOR_MAME% vis -rompath "%GAMEDIRRAW%;%ROMPATH%/vis;%ROMPATH%/bios" -cdrom "%ROMRAW%"</command>
    <platform>vis</platform>
    <theme>pc</theme>
  </system>

  <!-- ── EASY systems batch: 14 single-libretro-core systems.
       Each core verified present on the libretro Linux x86_64
       buildbot. Plain -L <core> %ROM% launch. ── -->

  <system>
    <name>bk</name>
    <fullname>Elektronika BK</fullname>
    <path>%ROMPATH%/bk</path>
    <extension>.zip .ZIP .7z .7Z .bin .BIN</extension>
    <command label="bk-emulator">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/bk_libretro.so %ROM%</command>
    <platform>bk</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>c128</name>
    <fullname>Commodore 128</fullname>
    <path>%ROMPATH%/c128</path>
    <extension>.zip .ZIP .7z .7Z .d64 .D64 .d71 .D71 .d80 .D80 .d81 .D81 .d82 .D82 .g64 .G64 .x64 .X64 .t64 .T64 .tap .TAP .prg .PRG .crt .CRT .d6z .D6Z .d7z .D7Z .d8z .D8Z .m3u .M3U</extension>
    <command label="VICE x128">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/vice_x128_libretro.so %ROM%</command>
    <platform>c128</platform>
    <theme>c64</theme>
  </system>

  <system>
    <name>cassettevision</name>
    <fullname>Epoch Cassette Vision</fullname>
    <path>%ROMPATH%/cassettevision</path>
    <extension>.zip .ZIP .7z .7Z .zip .ZIP .bin .BIN .7z .7Z</extension>
    <command label="pd777">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/pd777_libretro.so %ROM%</command>
    <platform>cassettevision</platform>
    <theme>pv1000</theme>
  </system>

  <system>
    <name>dice</name>
    <fullname>DICE (discrete arcade)</fullname>
    <path>%ROMPATH%/dice</path>
    <extension>.zip .ZIP .7z .7Z .zip .ZIP .dice .DICE .7z .7Z</extension>
    <command label="DICE">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/dice_libretro.so %ROM%</command>
    <platform>dice</platform>
    <theme>arcade</theme>
  </system>

  <system>
    <name>enterprise</name>
    <fullname>Enterprise 64/128</fullname>
    <path>%ROMPATH%/enterprise</path>
    <extension>.zip .ZIP .7z .7Z .img .IMG .dsk .DSK .tap .TAP .dtf .DTF .com .COM .trn .TRN .128 .128 .bas .BAS .cas .CAS .cdt .CDT .tzx .TZX .wav .WAV</extension>
    <command label="ep128emu">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/ep128emu_core_libretro.so %ROM%</command>
    <platform>enterprise</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>p2000t</name>
    <fullname>Philips P2000T</fullname>
    <path>%ROMPATH%/p2000t</path>
    <extension>.zip .ZIP .7z .7Z .cas .CAS</extension>
    <command label="M2000">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/m2000_libretro.so %ROM%</command>
    <platform>p2000t</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>pet</name>
    <fullname>Commodore PET</fullname>
    <path>%ROMPATH%/pet</path>
    <extension>.zip .ZIP .7z .7Z .d64 .D64 .d71 .D71 .d80 .D80 .d81 .D81 .d82 .D82 .g64 .G64 .x64 .X64 .t64 .T64 .tap .TAP .prg .PRG .crt .CRT .d6z .D6Z .d7z .D7Z .d8z .D8Z .m3u .M3U</extension>
    <command label="VICE xpet">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/vice_xpet_libretro.so %ROM%</command>
    <platform>pet</platform>
    <theme>pc</theme>
  </system>

  <system>
    <name>thomson</name>
    <fullname>Thomson MO/TO</fullname>
    <path>%ROMPATH%/thomson</path>
    <extension>.zip .ZIP .7z .7Z .fd .FD .sap .SAP .k7 .K7 .m7 .M7 .m5 .M5 .rom .ROM</extension>
    <command label="Theodore">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/theodore_libretro.so %ROM%</command>
    <platform>thomson</platform>
    <theme>moto</theme>
  </system>


  <!-- ── IN PROGRESS batch: fmtowns (MAME fmtownsux driver). ──
       bennugd removed: bennugd_libretro.so has no Linux x86_64 buildbot
       binary, so the system could never launch. Re-add a <system> here
       AND the SYS_TO_CORE/ROM-dir entries if/when a binary ships. ── -->

  <system>
    <name>fmtowns</name>
    <fullname>FM Towns</fullname>
    <path>%ROMPATH%/fmtowns</path>
    <extension>.m3u .M3U .d88 .D88 .d77 .D77 .xdf .XDF .cue .CUE .iso .ISO .chd .CHD .zip .ZIP .7z .7Z</extension>
    <command label="MAME [CD-ROM]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "fmtownsux -rompath \"%GAMEDIRRAW%;%ROMPATH%/fmtowns;%ROMPATH%/bios\" -cdrom \"%ROMRAW%\""</command>
    <command label="MAME [CD-ROM] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "fmtownsux -rompath \"%GAMEDIRRAW%;%ROMPATH%/fmtowns;%ROMPATH%/bios\" -cdrom \"%ROMRAW%\""</command>
    <command label="MAME [CD-ROM] (Standalone)">%EMULATOR_MAME% fmtownsux -rompath "%GAMEDIRRAW%;%ROMPATH%/fmtowns;%ROMPATH%/bios" -cdrom "%ROMRAW%"</command>
    <command label="MAME [Floppy]">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame_libretro.so "fmtownsux -rompath \"%GAMEDIRRAW%;%ROMPATH%/fmtowns;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Floppy] (MAME 2010)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/mame2010_libretro.so "fmtownsux -rompath \"%GAMEDIRRAW%;%ROMPATH%/fmtowns;%ROMPATH%/bios\" -flop1 \"%ROMRAW%\""</command>
    <command label="MAME [Floppy] (Standalone)">%EMULATOR_MAME% fmtownsux -rompath "%GAMEDIRRAW%;%ROMPATH%/fmtowns;%ROMPATH%/bios" -flop1 "%ROMRAW%"</command>
    <platform>fmtowns</platform>
    <theme>fmtowns</theme>
  </system>

</systemList>
CUSTOMSYSTEMS
# Safety net: validate the generated es_systems.xml before installing it.
# A system with an empty <name>, a duplicate <name>, or a <path> pointing at
# the ROMs root would make ES-DE skip systems or scan the whole ROM tree.
# (This is the exact failure class that previously shipped silently.)
if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$CUSTOM_SYSTEMS_TMP" << 'VALIDATE_ES'
import sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as e:
    print(f"   es_systems.xml is not well-formed XML: {e}"); sys.exit(1)
names, bad = [], []
for s in root.iter('system'):
    n = (s.findtext('name') or '').strip()
    p = (s.findtext('path') or '').strip()
    if not n: bad.append("empty <name>")
    if p in ('%ROMPATH%/', '%ROMPATH%'): bad.append(f"'{n or '?'}' path is the ROMs root")
    names.append(n)
dupes = sorted({n for n in names if n and names.count(n) > 1})
if dupes: bad.append("duplicate <name>: " + ", ".join(dupes))
if bad:
    print("   es_systems.xml validation FAILED:")
    for b in bad: print(f"     - {b}")
    sys.exit(1)
sys.exit(0)
VALIDATE_ES
    then
        fail "Generated es_systems.xml is invalid — NOT installing it."
        warn "Existing custom_systems/es_systems.xml (if any) left untouched."
        rm -f "$CUSTOM_SYSTEMS_TMP"
        exit 1
    fi
fi
backup_file_if_changed "$CUSTOM_SYSTEMS_FILE" "$CUSTOM_SYSTEMS_TMP" "custom es_systems.xml"

# Add ROM directories for all custom systems
for CUSTOM_SYS in ps3psn xbla \
    sfc n64dd wiiware megadrivejp saturnjp amiga500 amiga1200 videopacplus vpinball; do
    mkdir -p "$ROMS/$CUSTOM_SYS"
done

# MSU content folds into its parent system (snes/megadrive) as a nested folder
# rather than a standalone ES-DE system, so these paths are no longer in
# es_systems.xml. Create them explicitly so the importer and manual drops have
# a landing spot (nes-msu remains its own system and is covered below).
mkdir -p "$ROMS/snes/snes-msu" "$ROMS/megadrive/msu-md"

# Romhack/homebrew content folds into a "hacks" folder inside each parent
# system (same console, same core), not a standalone ES-DE system. Create the
# landing folders so the importer and manual drops have a target.
mkdir -p "$ROMS/snes/hacks" "$ROMS/nes/hacks" "$ROMS/gb/hacks" \
         "$ROMS/gbc/hacks" "$ROMS/gba/hacks" "$ROMS/megadrive/hacks" \
         "$ROMS/n64/hacks" "$ROMS/gamegear/hacks"

# Self-maintaining safety net: create a ROM folder for every <path>%ROMPATH%/...
# entry in the custom es_systems.xml we just wrote. This guarantees that any
# custom (or future) system has a landing folder even if it was never added to
# ROM_DIRS or the explicit loop above. %ROMPATH% maps to $ROMS; nested paths
# (e.g. snes/snes-msu, megadrive/msu-md) are created via mkdir -p.
while IFS= read -r _custom_path; do
    [[ -n "$_custom_path" ]] && mkdir -p "$ROMS/$_custom_path"
done < <(grep -oE '<path>%ROMPATH%/[^<]+</path>' "$CUSTOM_SYSTEMS_FILE" 2>/dev/null \
    | sed -E 's#<path>%ROMPATH%/##; s#</path>##')

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

if [[ -f "$BASE/.config/retroarch/retroarch.cfg" ]]; then
    info "retroarch.cfg already exists — preserved (your settings)"
else
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

# Joypad autoconfig dir. Quirk of the RetroArch AppImage build: its SDL2
# joypad driver internally uses UDEV-format autoconfigs, not the sdl2/ ones.
# (See https://docs.libretro.com/guides/controller-autoconfiguration/ —
# "the SDL2 controller driver utilizes UDEV rather than SDL2 in the RetroArch
# Appimage package".) The libretro/retroarch-joypad-autoconfig repo has ~200
# profiles under udev/ vs only ~6 under sdl2/, so pointing here is also where
# the useful coverage lives. The ":" prefix is RetroArch's "relative to
# retroarch.cfg's directory" — resolves to $BASE/.config/retroarch/autoconfig/udev/.
# Step 5 populates this directory from the libretro repo.
joypad_autoconfig_dir = ":/autoconfig/udev"

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
    ok "retroarch.cfg written (first-run defaults)"
fi

# Use a neutral wording — the inner block above already says either "preserved"
# or "written (first-run defaults)". The old final line claimed "written"
# unconditionally, which contradicted the preserve path on re-runs.
ok "retroarch.cfg location: $BASE/.config/retroarch/retroarch.cfg"
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
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
export XDG_STATE_HOME="$BASE_DIR/.local/state"
export XDG_CACHE_HOME="$BASE_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'rpcs3*.AppImage' -o -name 'RPCS3*.AppImage' | head -1)
if [[ -z "$BIN" ]]; then
    echo "rpcs3-portable.sh: no RPCS3 AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" "$@"
RPCS3WRAP
chmod +x "$EMUS/rpcs3-portable.sh"

# PCSX2 — needs -portable flag passed to the AppImage. Without it, PCSX2
# writes config to ~/.config/PCSX2/ regardless of XDG_CONFIG_HOME (the
# AppImage runs from a squashfs in /tmp, so its own portable.ini detection
# doesn't see anything alongside the binary either). The -portable CLI
# flag is the supported way to force portable mode for the AppImage.
cat > "$EMUS/pcsx2-portable.sh" << 'PCSX2WRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
export XDG_STATE_HOME="$BASE_DIR/.local/state"
export XDG_CACHE_HOME="$BASE_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -iname 'pcsx2*.AppImage' -o -iname 'PCSX2*.AppImage' | head -1)
if [[ -z "$BIN" ]]; then
    echo "pcsx2-portable.sh: no PCSX2 AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" -portable "$@"
PCSX2WRAP
chmod +x "$EMUS/pcsx2-portable.sh"

# PS3 launcher — dispatches by ROM file extension because PS3 collections
# ship games in several formats that RPCS3 cannot run with a plain
# 'rpcs3 <file>' command:
#   .psn / .m3u — tiny text files containing a Windows-style path to an
#                 installed PSN game's EBOOT.BIN under dev_hdd0/. We read
#                 the path, normalise the slashes, prefix with the bundle's
#                 .config/rpcs3/, and pass the resolved EBOOT.BIN to RPCS3.
#   .squashfs   — compressed PS3 disc image. Mounted via squashfuse (system
#                 package — apt install squashfuse) to a temp dir, then the
#                 inner PS3_GAME/USRDIR/EBOOT.BIN is passed to RPCS3.
#                 Unmounted on RPCS3 exit.
#   .iso / .pkg — passed straight to RPCS3 (which handles them natively).
cat > "$EMUS/ps3-launch.sh" << 'PS3LAUNCH'
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Mirror everything we print on stderr to a log file so an ES-DE-launched
# silent failure can still be diagnosed afterwards. ES-DE does not surface
# emulator stderr in its UI; without this, every non-zero exit looks
# identical (the game window simply doesn't open).
LOG="$BASE_DIR/.config/rpcs3/ps3-launch.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec 2> >(tee -a "$LOG" >&2)
echo "─── $(date '+%Y-%m-%d %H:%M:%S') ──────────────────────────────────────" >&2
echo "ps3-launch.sh invoked: $*" >&2

ROM="${1:-}"
if [[ -z "$ROM" || ! -e "$ROM" ]]; then
    echo "ps3-launch.sh: no ROM passed (or path does not exist): $ROM" >&2
    exit 1
fi
RPCS3="$SCRIPT_DIR/rpcs3-portable.sh"
[[ -x "$RPCS3" ]] || { echo "ps3-launch.sh: rpcs3-portable.sh missing or not executable" >&2; exit 1; }
RPCS3_HOME="$BASE_DIR/.config/rpcs3"

ext="${ROM##*.}"; ext="${ext,,}"
case "$ext" in
    psn|m3u)
        # Read the single-line backslash path inside; convert to a real path
        # under the bundle's dev_hdd0. Strip CR (Windows line endings) and
        # any leading slash/backslash.
        raw="$(tr -d '\r\n' < "$ROM")"
        raw="${raw//\\//}"           # backslashes -> forward
        raw="${raw#/}"               # drop leading slash
        # Two payload shapes seen in the wild:
        #   ".psn": "NPUB30024/dev_hdd0/game/NPUB30024/USRDIR/EBOOT.BIN"
        #          (TITLE_ID prefix, then dev_hdd0 path)
        #   ".m3u": "dev_hdd0/game/NPUB30024/USRDIR/EBOOT.BIN"
        #          (starts at dev_hdd0)
        # Either way, slice from "dev_hdd0/" onward and prefix with the
        # bundle's RPCS3 home.
        rel="${raw#*dev_hdd0/}"
        target="$RPCS3_HOME/dev_hdd0/$rel"
        if [[ ! -f "$target" ]]; then
            echo "ps3-launch.sh: EBOOT not found at $target" >&2
            echo "  payload from $ROM:" >&2
            echo "  $raw" >&2
            exit 1
        fi
        exec "$RPCS3" "$target"
        ;;
    squashfs)
        command -v squashfuse >/dev/null 2>&1 || {
            echo "ps3-launch.sh: squashfuse is not installed." >&2
            echo "  Install it with: sudo apt install squashfuse" >&2
            echo "  (or your distro's equivalent)" >&2
            exit 1
        }
        MOUNT="$(mktemp -d --tmpdir=/tmp ps3-squashfs.XXXXXX)" || exit 1
        # Best-effort cleanup; if the user kills RPCS3 we still try to unmount.
        trap 'fusermount -u "$MOUNT" 2>/dev/null || umount "$MOUNT" 2>/dev/null; rmdir "$MOUNT" 2>/dev/null' EXIT INT TERM
        if ! squashfuse "$ROM" "$MOUNT" 2>/dev/null; then
            echo "ps3-launch.sh: squashfuse failed to mount $ROM" >&2
            exit 1
        fi
        # Find the inner EBOOT.BIN — usually PS3_GAME/USRDIR/EBOOT.BIN at top
        EBOOT=$(find "$MOUNT" -maxdepth 4 -type f -iname EBOOT.BIN -path '*USRDIR*' | head -1)
        if [[ -z "$EBOOT" ]]; then
            echo "ps3-launch.sh: no EBOOT.BIN found inside $ROM" >&2
            exit 1
        fi
        "$RPCS3" "$EBOOT"
        # trap will unmount + clean up MOUNT on exit
        ;;
    iso|pkg)
        exec "$RPCS3" "$ROM"
        ;;
    *)
        # Unknown extension — let RPCS3 try anyway, in case it handles it.
        exec "$RPCS3" "$ROM"
        ;;
esac
PS3LAUNCH
chmod +x "$EMUS/ps3-launch.sh"

# PPSSPP — memstick flag, pointing to $BASE/.config/ppsspp/
# (PSP saves imported here, emulator reads from here)
cat > "$EMUS/ppsspp-portable.sh" << 'PPSSPPWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
mkdir -p "$BASE_DIR/.config/ppsspp"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'PPSSPP*.AppImage' -o -name 'ppsspp*.AppImage' | head -1)
if [[ -z "$BIN" ]]; then
    echo "ppsspp-portable.sh: no PPSSPP AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" --memstick "$BASE_DIR/.config/ppsspp" "$@"
PPSSPPWRAP
chmod +x "$EMUS/ppsspp-portable.sh"

# melonDS
cat > "$EMUS/melonds-portable.sh" << 'MELONDSWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
export XDG_STATE_HOME="$BASE_DIR/.local/state"
export XDG_CACHE_HOME="$BASE_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'melonDS*.AppImage' | head -1)
if [[ -z "$BIN" ]]; then
    echo "melonds-portable.sh: no melonDS AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" "$@"
MELONDSWRAP
chmod +x "$EMUS/melonds-portable.sh"

# Azahar (3DS)
cat > "$EMUS/azahar-portable.sh" << 'AZAHARWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
export XDG_STATE_HOME="$BASE_DIR/.local/state"
export XDG_CACHE_HOME="$BASE_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'azahar*.AppImage' -o -name 'Azahar*.AppImage' | head -1)
if [[ -z "$BIN" ]]; then
    echo "azahar-portable.sh: no Azahar AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" "$@"
AZAHARWRAP
chmod +x "$EMUS/azahar-portable.sh"

# Cemu
cat > "$EMUS/cemu-portable.sh" << 'CEMUWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
export XDG_STATE_HOME="$BASE_DIR/.local/state"
export XDG_CACHE_HOME="$BASE_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'Cemu*.AppImage' -o -name 'cemu*.AppImage' | head -1)
if [[ -z "$BIN" ]]; then
    echo "cemu-portable.sh: no Cemu AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" "$@"
CEMUWRAP
chmod +x "$EMUS/cemu-portable.sh"

# xemu — eeprom.bin and hdd image found in $BASE/.config/xemu/
cat > "$EMUS/xemu-portable.sh" << 'XEMUWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
export XDG_STATE_HOME="$BASE_DIR/.local/state"
export XDG_CACHE_HOME="$BASE_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'xemu*.AppImage' | head -1)
if [[ -z "$BIN" ]]; then
    echo "xemu-portable.sh: no xemu AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" "$@"
XEMUWRAP
chmod +x "$EMUS/xemu-portable.sh"

# Eden (Switch) — NAND/keys read from $BASE/.local/share/eden/
cat > "$EMUS/eden-portable.sh" << 'EDENWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
export XDG_STATE_HOME="$BASE_DIR/.local/state"
export XDG_CACHE_HOME="$BASE_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
BIN=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'Eden*.AppImage' -o -name 'eden*.AppImage' | head -1)
if [[ -z "$BIN" ]]; then
    echo "eden-portable.sh: no Eden AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" "$@"
EDENWRAP
chmod +x "$EMUS/eden-portable.sh"

# shadPS4 — config in $BASE/.config/shadps4/
cat > "$EMUS/shadps4-portable.sh" << 'SHADWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
export XDG_STATE_HOME="$BASE_DIR/.local/state"
export XDG_CACHE_HOME="$BASE_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
if [[ ! -x "$SCRIPT_DIR/shadps4" ]]; then
    echo "shadps4-portable.sh: shadps4 binary not found or not executable at $SCRIPT_DIR/shadps4" >&2
    exit 1
fi
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
if [[ -z "$BOX" ]]; then
    echo "86box-portable.sh: no 86Box AppImage found in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BOX" --vmpath "$BASE_DIR/.config/86box" "$@"
BOXWRAP
chmod +x "$EMUS/86box-portable.sh"

# VPinball — uses portable HOME/XDG paths plus an explicit PinMAME tree
# TABLES_PATH is read by some community VPX Standalone forks (and a few
# helper scripts) to locate tables outside the cwd. Upstream VPinball
# Standalone resolves tables from argv (`-play <path>`) and sidecars from
# the table's own directory, so this export is a no-op for stock builds but
# stays here as a stable hook for forks/helpers — and as a documented
# convention pointing at the bundle's table folder.
# PinMAME (machine ROMs) and Music are kept inside ROMs/vpinball so the
# whole bundle survives drive moves and Linux reinstalls.
mkdir -p "$EMUS/VPinball"
cat > "$EMUS/VPinball/vpinball-portable.sh" << 'VPINWRAP'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This wrapper lives in Emulators/VPinball/ alongside the VPinball binary, its
# shared libs and support dirs, so SCRIPT_DIR IS that contained folder. BASE_DIR
# climbs two levels (VPinball -> Emulators -> bundle root).
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
export HOME="$BASE_DIR"
export XDG_CONFIG_HOME="$BASE_DIR/.config"
export XDG_DATA_HOME="$BASE_DIR/.local/share"
# Hook for community forks / helper scripts; see setup comment.
export TABLES_PATH="$BASE_DIR/ROMs/vpinball"
export LD_LIBRARY_PATH="$SCRIPT_DIR:${LD_LIBRARY_PATH:-}"

VPI_DIR="$BASE_DIR/.vpinball"
VPI="$VPI_DIR/VPinballX.ini"
PINMAME_PATH="$BASE_DIR/ROMs/vpinball/pinmame"
PINMAME_INI_PATH="$PINMAME_PATH/ini"
VPREG_PATH="$VPI_DIR"
MUSIC_PATH="$BASE_DIR/ROMs/vpinball/music"

mkdir -p "$VPI_DIR" \
         "$PINMAME_PATH/roms" "$PINMAME_PATH/nvram" "$PINMAME_PATH/altcolor" \
         "$PINMAME_PATH/altsound" "$PINMAME_PATH/cfg" "$PINMAME_PATH/samples" \
         "$PINMAME_INI_PATH" "$MUSIC_PATH"

# Compatibility links. Never replace a real existing directory because it may
# contain user data from an older run.
if [[ -L "$BASE_DIR/.pinmame" ]]; then
    ln -sfn "$PINMAME_PATH" "$BASE_DIR/.pinmame"
elif [[ ! -e "$BASE_DIR/.pinmame" ]]; then
    ln -s "$PINMAME_PATH" "$BASE_DIR/.pinmame" 2>/dev/null || true
fi

# VPX Standalone reads music from THREE places, in order:
#   1. The table-local Music/ folder (cwd-relative to the .vpx file)
#   2. $HOME/.vpinball/music/ (because HOME is redirected to $BASE_DIR)
#   3. ./Music/ relative to cwd (= $SCRIPT_DIR = Emulators/VPinball/)
# The bundle stores music canonically at ROMs/vpinball/music. Bridge all
# three lookup points with relative symlinks that never replace a real dir.
if [[ -L "$BASE_DIR/.vpinball/music" ]]; then
    ln -sfn "../ROMs/vpinball/music" "$BASE_DIR/.vpinball/music"
elif [[ ! -e "$BASE_DIR/.vpinball/music" ]]; then
    ln -s "../ROMs/vpinball/music" "$BASE_DIR/.vpinball/music" 2>/dev/null || true
fi
if [[ -L "$SCRIPT_DIR/Music" ]]; then
    ln -sfn "../../ROMs/vpinball/music" "$SCRIPT_DIR/Music"
elif [[ ! -e "$SCRIPT_DIR/Music" ]]; then
    ln -s "../../ROMs/vpinball/music" "$SCRIPT_DIR/Music" 2>/dev/null || true
fi

ensure_ini_key() {
    # Set key=value *within* the named section. Section-aware: the same key may
    # live in two sections (e.g. PinMAMEPath under both [Standalone] and
    # [Plugin.PinMAME]) without one clobbering the other. Updates in place if
    # present in that section, adds under the header if the section exists, or
    # appends a new section otherwise.
    local section="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)" || return 0
    awk -v s="$section" -v k="$key" -v v="$value" '
        function ishdr(l){ return (l ~ /^[[:space:]]*\[.*\][[:space:]]*$/) }
        BEGIN{ insec=0; done=0 }
        {
          if (ishdr($0)) {
            if (insec && !done){ print k" = "v; done=1 }
            cur=$0; sub(/^[[:space:]]*\[/,"",cur); sub(/\][[:space:]]*$/,"",cur)
            insec=(cur==s); print; next
          }
          if (insec && !done && $0 ~ "^[[:space:]]*"k"[[:space:]]*="){ print k" = "v; done=1; next }
          print
        }
        END{
          if (insec && !done){ print k" = "v; done=1 }
          if (!done){ print "["s"]"; print k" = "v }
        }
    ' "$VPI" > "$tmp" 2>/dev/null && mv "$tmp" "$VPI" || rm -f "$tmp"
}

if [[ ! -f "$VPI" ]]; then
    cat > "$VPI" << EOF
[Standalone]
VPRegPath = $VPREG_PATH
PinMAMEPath = $PINMAME_PATH
[Plugin.PinMAME]
PinMAMEPath = $PINMAME_PATH
PinMAMEIniPath = $PINMAME_INI_PATH
EOF
else
    ensure_ini_key "Standalone" "VPRegPath" "$VPREG_PATH"
    ensure_ini_key "Standalone" "PinMAMEPath" "$PINMAME_PATH"
    ensure_ini_key "Plugin.PinMAME" "PinMAMEPath" "$PINMAME_PATH"
    ensure_ini_key "Plugin.PinMAME" "PinMAMEIniPath" "$PINMAME_INI_PATH"
fi

cd "$SCRIPT_DIR" || exit 1
BIN="$SCRIPT_DIR/VPinballX_BGFX"
[[ ! -f "$BIN" ]] && BIN="$SCRIPT_DIR/VPinballX_GL"
[[ ! -f "$BIN" ]] && BIN="$SCRIPT_DIR/VPinballX"
if [[ ! -x "$BIN" ]]; then
    echo "VPinball binary not found or not executable in $SCRIPT_DIR" >&2
    exit 1
fi
exec "$BIN" "$@"
VPINWRAP
chmod +x "$EMUS/VPinball/vpinball-portable.sh"

mkdir -p "$ROMS/vpinball/pinmame/roms" "$ROMS/vpinball/pinmame/nvram" \
         "$ROMS/vpinball/pinmame/altcolor" "$ROMS/vpinball/pinmame/altsound" \
         "$ROMS/vpinball/pinmame/cfg" "$ROMS/vpinball/pinmame/samples" \
         "$ROMS/vpinball/pinmame/ini" "$ROMS/vpinball/music"
if [[ -L "$BASE/.pinmame" ]]; then
    ln -sfn "$ROMS/vpinball/pinmame" "$BASE/.pinmame"
elif [[ ! -e "$BASE/.pinmame" ]]; then
    ln -s "$ROMS/vpinball/pinmame" "$BASE/.pinmame" 2>/dev/null || true
fi
if [[ -L "$EMUS/Music" ]]; then
    ln -sfn "../ROMs/vpinball/music" "$EMUS/Music"
elif [[ ! -e "$EMUS/Music" ]]; then
    ln -s "../ROMs/vpinball/music" "$EMUS/Music" 2>/dev/null || true
fi

ok "XDG portable wrappers written (all pointing to \$BASE/.config/ and \$BASE/.local/share/)"

# Emulator configs (Dolphin, DuckStation, PCSX2, Cemu) are NOT pre-written.
# Each emulator creates its own config on first launch with version-appropriate
# defaults; pre-seeding them caused values to be silently overwritten and locked
# users into stale key names from older releases. Users set their video
# preferences in each emulator on first launch — the preserve-configs guards
# (In Progress #20) keep those choices intact on every setup re-run.

#=============================================================================
# STEP 5: DOWNLOAD JOYPAD AUTOCONFIG PROFILES
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
# STEP 6: LAUNCH SCRIPT
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing launch.sh..."

LAUNCH_FILE="$BASE/launch.sh"
LAUNCH_TMP="${LAUNCH_FILE}.tmp.$$"
cat > "${LAUNCH_TMP}" << 'LAUNCHER'
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
# Redirect XDG base dirs into the bundle too. HOME alone is not enough: many
# desktops preset XDG_CONFIG_HOME/XDG_DATA_HOME in the session, which child
# emulators (launched by ES-DE from the raw AppImage) would otherwise inherit
# and write to the user's real home — breaking portability. Setting them here
# covers every emulator uniformly, not just the ones with *-portable.sh wrappers.
export XDG_CONFIG_HOME="$SCRIPT_DIR/.config"
export XDG_DATA_HOME="$SCRIPT_DIR/.local/share"
export XDG_STATE_HOME="$SCRIPT_DIR/.local/state"
export XDG_CACHE_HOME="$SCRIPT_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

# GPU shader/compute disk caches don't honor HOME or XDG_CACHE_HOME — the
# NVIDIA driver writes ~/.nv/ComputeCache and ~/.nv/GLCache via its own vars,
# and Mesa uses its own. Point them into the bundle explicitly so they don't
# leak into the user's real home.
export __GL_SHADER_DISK_CACHE_PATH="$SCRIPT_DIR/.cache/nv"
export CUDA_CACHE_PATH="$SCRIPT_DIR/.cache/nv/ComputeCache"
export MESA_SHADER_CACHE_DIR="$SCRIPT_DIR/.cache/mesa"
mkdir -p "$__GL_SHADER_DISK_CACHE_PATH" "$CUDA_CACHE_PATH" "$MESA_SHADER_CACHE_DIR"

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

# ── Portable path healing ──────────────────────────────────────────────
# Setup bakes ABSOLUTE bundle paths into retroarch.cfg and es_find_rules.xml.
# If the bundle is moved to another drive/folder (the whole point of a
# portable bundle, and external-drive mount points differ per machine),
# those stale paths break emulator, core, BIOS and save resolution.
# es_settings.xml ROM/media paths are handled by apply_paths above; this
# heals the other two on every launch.
RA_CFG="$SCRIPT_DIR/.config/retroarch/retroarch.cfg"
FIND_RULES="$SCRIPT_DIR/ES-DE/custom_systems/es_find_rules.xml"
BUNDLE_MARK="$SCRIPT_DIR/.bundle-path"

heal_paths() {
    # retroarch.cfg: rewrite the known bundle-relative path keys to the
    # CURRENT location. Idempotent; only the path keys are touched so all
    # real user settings (video/audio/input) are preserved. This also fixes
    # the case where retroarch.cfg is preserved (first-run-only) across a move.
    if [[ -f "$RA_CFG" ]]; then
        local esc; esc=$(printf '%s' "$SCRIPT_DIR" | sed -e 's/[#&\\]/\\&/g')
        sed -i \
            -e "s#^[[:space:]]*libretro_directory[[:space:]]*=.*#libretro_directory = \"$esc/Emulators/retroarch-cores\"#" \
            -e "s#^[[:space:]]*system_directory[[:space:]]*=.*#system_directory = \"$esc/ROMs/bios\"#" \
            -e "s#^[[:space:]]*savefile_directory[[:space:]]*=.*#savefile_directory = \"$esc/Saves/files\"#" \
            -e "s#^[[:space:]]*savestate_directory[[:space:]]*=.*#savestate_directory = \"$esc/Saves/states\"#" \
            -e "s#^[[:space:]]*screenshot_directory[[:space:]]*=.*#screenshot_directory = \"$esc/Saves/screenshots\"#" \
            -e "s#^[[:space:]]*log_dir[[:space:]]*=.*#log_dir = \"$esc/Saves/logs\"#" \
            -e "s#^[[:space:]]*cheat_database_path[[:space:]]*=.*#cheat_database_path = \"$esc/.config/retroarch/cheats\"#" \
            "$RA_CFG" 2>/dev/null || true
    fi

    # es_find_rules.xml: entries interleave bundle paths with system/flatpak
    # fallbacks, so we replace ONLY the old bundle base with the new one,
    # tracked via .bundle-path. Literal replace via python3 (no escaping
    # pitfalls); sed fallback if python3 is absent.
    if [[ -f "$FIND_RULES" && -f "$BUNDLE_MARK" ]]; then
        local old; old=$(cat "$BUNDLE_MARK" 2>/dev/null || true)
        if [[ -n "$old" && "$old" != "$SCRIPT_DIR" ]]; then
            if command -v python3 >/dev/null 2>&1; then
                OLD_BASE="$old" NEW_BASE="$SCRIPT_DIR" python3 - "$FIND_RULES" <<'PYHEAL' 2>/dev/null || true
import os, sys
f = sys.argv[1]; old = os.environ["OLD_BASE"]; new = os.environ["NEW_BASE"]
with open(f, encoding="utf-8", errors="replace") as fh: s = fh.read()
with open(f, "w", encoding="utf-8") as fh: fh.write(s.replace(old, new))
PYHEAL
            else
                local oe ne
                oe=$(printf '%s' "$old" | sed -e 's/[][\\.^$*/]/\\&/g')
                ne=$(printf '%s' "$SCRIPT_DIR" | sed -e 's/[&\\/]/\\&/g')
                sed -i "s/$oe/$ne/g" "$FIND_RULES" 2>/dev/null || true
            fi
        fi
    fi

    # Record current location so the next move is detectable.
    printf '%s\n' "$SCRIPT_DIR" > "$BUNDLE_MARK" 2>/dev/null || true
}

apply_theme
apply_paths
heal_paths

"$ESDE_BIN" --home "$SCRIPT_DIR" "$@"
EXIT_CODE=$?

apply_theme
apply_paths

exit $EXIT_CODE
LAUNCHER
backup_file_if_changed "${LAUNCH_FILE}" "${LAUNCH_TMP}" "launch.sh"

chmod +x "$BASE/launch.sh"
ok "launch.sh written"

#=============================================================================
# STEP 7: BIOS + MAIN README
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

README_FILE="$BASE/README.md"
README_TMP="${README_FILE}.tmp.$$"
cat > "${README_TMP}" << 'MAINREADME'
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

> On its first launch ES-DE creates the full `ROMs/<system>/` folder tree for
> every supported system (including custom ones not pre-created by setup), so
> run `./launch.sh` once before dropping ROMs in if a folder is missing. The
> importer also creates any needed system folder on demand.

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
| Maintenance | Update script for ES-DE/emulator AppImages and RetroArch cores |

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
| Ports | Commander Keen, C-Dogs, OpenTTD, Tyrian 2000, OpenRA, Cave Story |

</details>

<details>
<summary><strong>Ports and engines — where to put game data</strong></summary>

Each port appears in the ES-DE **Ports** system. Every port lives in its own folder `Emulators/<Port>/` — the AppImage *and* its game data go there together, because these engines look for data right beside their own binary. Drop the port's user-supplied game data into that folder (a `_PUT-GAME-DATA-HERE.txt` reminder is created there on first launch); it is found automatically and is preserved across setup re-runs and `update.sh`.

| Port (in ES-DE "Ports") | Put game data in | You provide |
|---|---|---|
| OpenTTD | `Emulators/OpenTTD/` | Nothing required — downloads free base graphics/sound on first run |
| Commander Genius (Keen) | `Emulators/Commander-Genius/` | Commander Keen episode game files |
| C-Dogs SDL | `Emulators/C-Dogs_SDL/` | Nothing — ships with free campaigns |
| OpenTyrian 2000 | `Emulators/OpenTyrian2000/` | Tyrian data files (freely redistributable) |
| OpenRA | `Emulators/OpenRA/` | Nothing required — fetches C&C/Red Alert assets via its in-app installer |
| Cave Story (NXEngine) | `Emulators/NXEngine/` | Cave Story `data/` folder (freeware) |

</details>
<!-- PORTS_DATA_TABLE_END -->


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
│   │   ├── OpenRA.sh
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
- Visual Pinball Standalone uses a portable `ROMs/vpinball/pinmame` tree, a safe `.pinmame` compatibility symlink, and `ROMs/vpinball/music` for imported table music.

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

The update helper checks ES-DE and emulator AppImages, and can refresh all RetroArch cores from the buildbot. It keeps existing files unless you choose to replace them.

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
- Source ports such as Commander Genius, OpenTyrian 2000, and Cave Story (NXEngine) may need original game data.

## Legal

This project downloads open source emulator software, source ports, and helper assets. It does not include commercial games, ROMs, BIOS files, firmware, keys, or copyrighted game data.

Only import or use software and data you are legally allowed to use.

---

Made with ❤️ for the Linux retro gaming community
MAINREADME
backup_file_if_changed "${README_FILE}" "${README_TMP}" "README.md"

ok "READMEs written"

#=============================================================================
# STEP 8: DOWNLOAD ES-DE
#=============================================================================
STEP=$((STEP + 1))
echo ""
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading ES-DE..."
download_esde "$BASE" || true

#=============================================================================
# STEP 9: DOWNLOAD RETROARCH
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
# STEP 10: DOWNLOAD RETROARCH CORES
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
# Used by both the main install flow below AND by import-collection.sh,
# which carries a folded-in copy of these functions for on-demand
# installation when it imports a system whose emulator
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
    # Match ONLY the regular SSE4.1 build DuckStation-x64.AppImage, never
    # DuckStation-x64-SSE2.AppImage (legacy fallback for pre-2008 CPUs).
    # The old ".*x64.*" pattern matched both and grabbed SSE2 first,
    # triggering DuckStation's legacy-SSE2 hardware-check warning.
    github_appimage "stenzek/duckstation" \
        "DuckStation-x64\.AppImage$" \
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
    VPDIR="$EMUS/VPinball"
    if [[ -f "$VPDIR/VPinballX_BGFX" ]]; then
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
                mkdir -p "$VPDIR"
                # Copy binaries — search at any depth after extraction
                for BIN in VPinballX_BGFX VPinballX_GL VPinballX; do
                    FOUND=$(find "$VPINBALL_TMP" -name "$BIN" -type f 2>/dev/null | head -1)
                    if [[ -n "$FOUND" ]]; then
                        cp "$FOUND" "$VPDIR/$BIN"
                        chmod +x "$VPDIR/$BIN"
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
                    [[ ! -d "$VPDIR/$DNAME" ]] && mkdir -p "$VPDIR/$DNAME"
                    cp -rn "$D/." "$VPDIR/$DNAME/" 2>/dev/null || true
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
                    [[ -f "$VPDIR/$LIBNAME" ]] && continue
                    cp "$LIB" "$VPDIR/$LIBNAME" 2>/dev/null && VP_LIBS=$((VP_LIBS + 1))
                done < <(find "$EXTRACT_ROOT" -type f -name '*.so*' 2>/dev/null)
                # Synthesize SONAME symlinks (libFOO.so.1.2.3 -> libFOO.so.1).
                # find -type f copies only the real versioned files; the binary
                # links against the major-version SONAME. Without these links
                # the loader fails with "libSDL3.so.0: cannot open shared
                # object file". This mini-ldconfig pass makes it work whether
                # or not the archive shipped the symlinks.
                ( cd "$VPDIR" && for real in lib*.so.*; do
                    [[ -f "$real" && ! -L "$real" ]] || continue
                    soname=$(printf '%s' "$real" | sed -E 's/(\.so\.[0-9]+)\..*/\1/')
                    [[ "$soname" != "$real" && ! -e "$soname" ]] && ln -s "$real" "$soname"
                done )
                # VPinball Standalone auto-detects a pinmame/ folder next to the
                # .vpx files; create it so PinMAME-based tables (real solid-state
                # / DMD machines) have a ROM directory. Users drop romset zips
                # into ROMs/vpinball/pinmame/roms/ themselves (copyrighted, like
                # arcade ROMs — not bundled).
                mkdir -p "$ROMS/vpinball/pinmame/roms" "$ROMS/vpinball/pinmame/nvram" "$ROMS/vpinball/pinmame/altcolor" "$ROMS/vpinball/pinmame/altsound" "$ROMS/vpinball/pinmame/cfg" "$ROMS/vpinball/pinmame/samples" "$ROMS/vpinball/pinmame/ini" "$ROMS/vpinball/music"
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


# Ports / engines AppImage batch




install_openttd() {
    github_appimage "pkgforge-dev/OpenTTD-AppImage" \
        ".*\.AppImage$" \
        "$EMUS/OpenTTD/OpenTTD-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}


install_cgenius() {
    github_appimage "pkgforge-dev/Commander-Genius-AppImage" \
        ".*\.AppImage$" \
        "$EMUS/Commander-Genius/Commander-Genius-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_cdogs() {
    github_appimage "pkgforge-dev/C-Dogs_SDL-AppImage" \
        ".*\.AppImage$" \
        "$EMUS/C-Dogs_SDL/C-Dogs_SDL-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}








install_opentyrian() {
    github_appimage "pkgforge-dev/OpenTyrian2000-AppImage" \
        ".*\.AppImage$" \
        "$EMUS/OpenTyrian2000/OpenTyrian2000-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}



install_openra() {
    github_appimage "pkgforge-dev/OpenRA-AppImage-Enhanced" \
        ".*\.AppImage$" \
        "$EMUS/OpenRA/OpenRA-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}







install_nxengine() {
    github_appimage "pkgforge-dev/NXEngine-evo-AppImage-Enhanced" \
        ".*\.AppImage$" \
        "$EMUS/NXEngine/NXEngine-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}


install_engine_by_key() {
    case "$1" in
        cgenius)     install_cgenius ;;
        cdogs)       install_cdogs ;;
        openttd)     install_openttd ;;
        opentyrian)  install_opentyrian ;;
        openra)      install_openra ;;
        nxengine)    install_nxengine ;;
        *)           fail "Unknown engine/AppImage key: $1"; return 1 ;;
    esac
}

#=============================================================================
# STEP 11: DOWNLOAD STANDALONE EMULATORS
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
# STEP 12: DOWNLOAD ADDITIONAL STANDALONE EMULATORS
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Downloading additional standalone emulators..."

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


echo ""
echo "   ── Ports / Engines AppImages ──"
# ── Migrate any flat port AppImages into per-port folders ──
# Ports now live in Emulators/<Port>/ so each engine finds game data placed
# beside its own binary (Commander Genius->Keen files, NXEngine->data/, etc.). Older
# installs placed them flat in Emulators/; move them so re-runs don't re-download
# and the Emulators/ listing stays tidy. Game data dropped flat must be moved
# into the matching Emulators/<Port>/ folder by hand (see the README ports table).
for _pf in OpenTTD-latest.AppImage Commander-Genius-latest.AppImage \
           C-Dogs_SDL-latest.AppImage OpenTyrian2000-latest.AppImage \
           OpenRA-latest.AppImage NXEngine-latest.AppImage; do
    _pdir="${_pf%-latest.AppImage}"
    if [[ -f "$EMUS/$_pf" && ! -f "$EMUS/$_pdir/$_pf" ]]; then
        mkdir -p "$EMUS/$_pdir"
        mv "$EMUS/$_pf" "$EMUS/$_pdir/$_pf"
        info "Moved $_pf into Emulators/$_pdir/"
    fi
done

for engine_key in openttd cgenius cdogs opentyrian openra nxengine; do
    if emu_selected "$engine_key"; then
        install_engine_by_key "$engine_key" || true
    else
        info "Skipped $engine_key (deselected)"
    fi
done

# ── PICO-8 — retro8 is the libretro core (downloaded in STEP 10). fake08 was
#    dropped as an alt-emu: it has no Linux x86_64 buildbot binary, so the
#    entry could only ever fail. retro8 is the single PICO-8 emulator. ──
if [[ -f "$EMUS/retroarch-cores/retro8_libretro.so" ]]; then
    ok "PICO-8: retro8 core ready"
fi

ok "Additional standalone emulators done"
echo ""

#=============================================================================
# STEP 13: DOWNLOAD DEFAULT THEME + WRITE ES_SETTINGS.XML
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

    # First install writes the preferred theme cache. Re-runs preserve it so a
    # user's existing ES-DE theme preference is not silently reset by setup.
    if [[ -n "$THEME_NAME" ]]; then
        if [[ -f "$ESDE_DATA/.desired_theme" ]]; then
            ok "Existing theme preference preserved"
        else
            echo "$THEME_NAME" > "$ESDE_DATA/.desired_theme"
            ok "Theme preference saved (launch.sh will enforce it on launch)"
        fi
    fi
else
    ok "Using ES-DE's built-in Slate theme"
fi

# ── Port covers artwork ──
# Download pre-made covers for bundled port launchers from the project repo.
# Skipped entirely if the covers directory already has files (user may have
# their own artwork or a prior download).
PORT_COVERS_DIR="$BASE/downloaded_media/ports/covers"
if [[ -d "$PORT_COVERS_DIR" ]] && [[ -n "$(find "$PORT_COVERS_DIR" -maxdepth 1 -type f 2>/dev/null | head -1)" ]]; then
    ok "Port covers already present, skipping download"
else
    info "Downloading port covers from project repo..."
    PORT_COVERS_TMP=$(mktemp -d)
    PORT_COVERS_URL="https://github.com/flexcrush420/portable-esde-linux/archive/refs/heads/main.zip"
    if curl -sfL -o "$PORT_COVERS_TMP/repo.zip" "$PORT_COVERS_URL"; then
        mkdir -p "$PORT_COVERS_DIR"
        # Try the clean path first (media/ports/covers/), fall back to repo
        # root if the images were uploaded there instead.
        EXTRACTED=""
        if unzip -qo "$PORT_COVERS_TMP/repo.zip" "*/media/ports/covers/*" -d "$PORT_COVERS_TMP" 2>/dev/null; then
            CANDIDATE=$(find "$PORT_COVERS_TMP" -type d -name covers -path "*/media/ports/covers" | head -1)
            # Only use this path if it actually has image files (not just .gitkeep)
            if [[ -n "$CANDIDATE" ]] && find "$CANDIDATE" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" \) | grep -q .; then
                EXTRACTED="$CANDIDATE"
            fi
        fi
        if [[ -z "$EXTRACTED" ]]; then
            # Covers are at repo root — extract everything, then pick out images
            unzip -qo "$PORT_COVERS_TMP/repo.zip" -d "$PORT_COVERS_TMP" 2>/dev/null || true
            EXTRACTED=$(find "$PORT_COVERS_TMP" -maxdepth 1 -type d -name "portable-esde-linux-*" | head -1)
        fi
        if [[ -n "$EXTRACTED" ]] && [[ -d "$EXTRACTED" ]]; then
            # Copy only image files (png/jpg/jpeg/webp), skip .sh/.md/.cfg etc.
            find "$EXTRACTED" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) \
                -exec cp -n {} "$PORT_COVERS_DIR/" \; 2>/dev/null || true
            COVER_COUNT=$(find "$PORT_COVERS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
            ok "Port covers installed ($COVER_COUNT images)"
        else
            warn "Port covers not found in repo archive"
        fi
    else
        warn "Could not download port covers — cosmetic only, ports still work"
    fi
    rm -rf "$PORT_COVERS_TMP"
fi

# ── ES-DE settings ──
# First run writes sane defaults. Re-runs preserve the user's existing ES-DE
# settings and only repair the bundle-critical path keys.
SETTINGS_FILE="$ESDE_DATA/settings/es_settings.xml"
mkdir -p "$ESDE_DATA/settings"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    SETTINGS_TMP="$SETTINGS_FILE.tmp.$$"
    cat > "$SETTINGS_TMP" << ESSETTINGS
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
    backup_file_if_changed "$SETTINGS_FILE" "$SETTINGS_TMP" "es_settings.xml"
else
    SETTINGS_TMP="$SETTINGS_FILE.tmp.$$"
    python3 - "$SETTINGS_FILE" "$SETTINGS_TMP" "$BASE/downloaded_media" "$ROMS" <<'PYEOF'
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

src, dst, media_dir, rom_dir = map(Path, sys.argv[1:5])
required = {
    ("string", "MediaDirectory"): str(media_dir),
    ("string", "ROMDirectory"): str(rom_dir),
}
default_if_missing = {
    ("int", "ApplicationRelease"): "51",
    ("bool", "ShowHiddenGames"): "false",
}

text = src.read_text(encoding="utf-8", errors="replace")
# Strip the XML declaration if present — wrapping it inside <root> would cause
# "XML or text declaration not at start of entity" and silently destroy every
# user setting (Theme, CollectionSystemsAuto, favourites, history, etc.).
import re as _re
text = _re.sub(r'<\?xml[^?]*\?>\s*', '', text, count=1)
try:
    root = ET.fromstring(f"<root>\n{text}\n</root>")
except ET.ParseError:
    # Preserve the unreadable file before writing a minimal safe settings file.
    root = ET.Element("root")

# Older broken builds may have wrapped the settings in <config>. Flatten one
# level so ES-DE sees bool/int/string nodes as direct document elements.
children = []
for child in list(root):
    if child.tag == "config":
        children.extend(list(child))
    elif child.tag in {"bool", "int", "string", "float"}:
        children.append(child)

seen = {}
for child in children:
    name = child.attrib.get("name")
    if name:
        seen[(child.tag, name)] = child

for key, value in required.items():
    tag, name = key
    elem = seen.get(key)
    if elem is None:
        elem = ET.Element(tag, {"name": name})
        children.append(elem)
        seen[key] = elem
    elem.set("value", value)

for key, value in default_if_missing.items():
    tag, name = key
    if key not in seen:
        children.append(ET.Element(tag, {"name": name, "value": value}))

lines = ['<?xml version="1.0"?>']
for elem in children:
    attrs = " ".join(f'{k}="{v}"' for k, v in elem.attrib.items())
    lines.append(f"<{elem.tag} {attrs} />")
dst.write_text("\n".join(lines) + "\n", encoding="utf-8")
PYEOF
    backup_file_if_changed "$SETTINGS_FILE" "$SETTINGS_TMP" "es_settings.xml"
fi

info "Browse more themes anytime: ES-DE menu → UI Settings → Theme Downloader"
echo ""

#=============================================================================
# STEP 14: (reserved — RetroBat import moved to end of setup)
#=============================================================================
# The setup-time RetroBat importer that used to live here was a stale,
# divergent copy of import-collection.sh logic (Audit F8). It has been
# removed. ROM-collection import is now offered ONCE, at the very end of
# setup, by invoking the single canonical importer (import-collection.sh).
# This guarantees one code path and kills the setup-vs-bundle drift.
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} ROM import deferred to end of setup"
ok "Will offer collection import after the bundle is fully built"

#=============================================================================
# STEP 15: WRITE CONVERSION SCRIPT TO BUNDLE
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing import-collection.sh to bundle..."

IMPORTER_FILE="$BASE/import-collection.sh"
IMPORTER_TMP="${IMPORTER_FILE}.tmp.$$"
cat > "${IMPORTER_TMP}" << 'CONVSCRIPT'
#!/usr/bin/env bash
#=============================================================================
# Portable ES-DE — Collection Importer
# Import a RetroBat install, a ROM-pack collection, or a single-system
# folder into the bundle. Run anytime after setup.
# Usage: ./import-collection.sh [-test]
#   -test   scan sources and report what WOULD be imported;
#           copies/moves/modifies NOTHING.
#=============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
ROMS="$BASE/ROMs"
BIOS_DIR="$ROMS/bios"   # canonical bundle BIOS location — verify_entry reads from here
ESDE_DATA="$BASE/ES-DE"
MEDIA_BASE="$BASE/downloaded_media"
# EMUS must be defined here too — is_emulator_installed / is_core_installed
# below resolve binary/core paths against it. Without this, every check ran
# against an empty path and reported "(NOT installed — would prompt)" even
# when the core/emulator was already in the bundle. (Audit F8 sibling bug.)
EMUS="$BASE/Emulators"

# -test: scan sources and report what WOULD happen, copying/moving nothing.
# --audit: stronger dry-run compatibility report for source-folder checks.
DRY_RUN=false
DRY_VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        -test|--test|-t|--dry-run|--dry|-n) DRY_RUN=true ;;
        --audit|--compat|--compatibility) DRY_RUN=true; DRY_VERBOSE=true ;;
        -v|--verbose) DRY_VERBOSE=true ;;
        -h|--help)
            echo "Usage: ./import-collection.sh [-test] [-v|--verbose] [--audit]"
            echo "  -test       scan sources, report what would import, change nothing"
            echo "  -v          with -test, include source-folder compatibility details"
            echo "  --audit     same as -test -v"
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


# If ES-DE is currently running, its in-memory media-availability index
# was stamped at launch from what was on disk then. New media this import
# puts down will be invisible until ES-DE is fully quit and its cache
# cleared/reread. We don't kill the process (user may have unsaved scrape
# state), but we warn so they understand why media might still look stale.
ESDE_RUNNING=false
if command -v pgrep >/dev/null 2>&1 && pgrep -f 'ES-DE.*\.AppImage' >/dev/null 2>&1; then
    ESDE_RUNNING=true
    warn "ES-DE appears to be running."
    warn "Imported media will not appear until ES-DE is fully quit, then relaunched."
    warn "After import, this script will offer to clear the ES-DE cache."
    echo ""
fi
echo ""
echo -e "${CYAN}Collection Importer → ES-DE${NC}"
$DRY_RUN && echo -e "${YELLOW}── TEST MODE — nothing will be copied, moved, or modified ──${NC}"
$DRY_VERBOSE && echo -e "${YELLOW}── VERBOSE AUDIT — source folders, orphan metadata, and import targets shown ──${NC}"
echo ""

RETROBAT_PATHS=()
# Source -> system-name override for "nested-single-system" sources where
# games live in <source>/roms/<files> rather than at top level. Set at the
# input-add prompt; consulted by enumerate_system_dirs.
declare -A NESTED_SYSTEM_OF=()
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
        # Decide collection vs nested-single-system by what roms/ contains.
        # - subdirectories: classic RetroBat layout, each roms/<system>/ is one system.
        # - flat files only: source is itself a single-system folder whose games
        #   happen to live in roms/ (e.g. /<root>/ps3/roms/*.m3u). The PARENT
        #   folder name (ps3) is the system; roms/ is the game container.
        # Note: when counting subdirs we ignore known non-system folders that
        # may sit alongside the game files at this level (media/, bios/, etc.)
        # — a 'media' sibling does NOT make a flat-file source a "collection".
        _has_subdirs=0; _has_files=0
        for _e in "$INPUT/roms"/*; do
            [[ -e "$_e" ]] || continue
            if [[ -d "$_e" ]]; then
                case "$(basename "$_e")" in
                    media|images|videos|manuals|downloaded_media|bios|.media|.thumbs) continue ;;
                esac
                _has_subdirs=1
            elif [[ -f "$_e" ]]; then
                _has_files=1
            fi
        done
        # If both real subdirs AND flat files exist, prefer nested-single-system:
        # a small number of folder-style game ROMs (multi-disc, extracted .pkg)
        # mixed in with many flat files is far more common than a collection
        # source that also happens to have loose files at the top level.
        if (( _has_files == 1 )); then
            RETROBAT_PATHS+=("$INPUT/roms")
            NESTED_SYSTEM_OF["$INPUT/roms"]="$(basename "$INPUT")"
            echo -e "   ${GREEN}✓${NC} Added (single system '$(basename "$INPUT")', nested in roms/): $INPUT"
        elif (( _has_subdirs == 1 )); then
            RETROBAT_PATHS+=("$INPUT")
            echo -e "   ${GREEN}✓${NC} Added (collection): $INPUT"
        else
            # roms/ exists but is empty (or only contains ignored folders)
            wt_msg "Path not valid" "The roms/ subfolder has no game files or system folders:\n\n$INPUT\n\nSkipping this entry."
        fi
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
    # ── ES-DE canonical folder names (identity — so an already-correct
    #    source folder routes to itself instead of being dropped) ──
    [3dboxes]=3dboxes        [backcovers]=backcovers   [covers]=covers
    [fanart]=fanart         [manuals]=manuals         [marquees]=marquees
    [miximages]=miximages   [physicalmedia]=physicalmedia
    [screenshots]=screenshots                         [titlescreens]=titlescreens
    [videos]=videos
    # ── RetroBat media folder names ──
    # RetroBat splits box art across two folders by convention:
    #   thumbnails/ — angled 3D box render (RetroBat's <boxart> / <thumbnail>)
    #   box2d/      — flat 2D box (RetroBat's <extra1>)
    # Confirmed across multiple RGS packs (PSX, PS3). ES-DE has matching
    # separate slots, so each routes to its own destination — no collision.
    [thumbnails]=3dboxes      [box2d]=covers            [box3d]=3dboxes
    [2dboxes]=covers          # newer RetroBat packs: flat 2D box front → covers
    [boxback]=backcovers    [fanarts]=fanart          [marquee]=marquees
    [images]=screenshots    [titles]=titlescreens     [cartridges]=physicalmedia
    # ── ES / Skraper / Batocera folder-name variants ──
    [box]=covers            [boxart]=covers           [boxfront]=covers
    [box2dfront]=covers     [wheel]=marquees          [wheels]=marquees
    [logo]=marquees         [logos]=marquees          [manual]=manuals
    [image]=screenshots     [screenshot]=screenshots  [ss]=screenshots
    [snap]=screenshots      [snaps]=screenshots       [titleshot]=titlescreens
    [titlescreen]=titlescreens                        [title]=titlescreens
    [fanart_image]=fanart   [video]=videos            [mix]=miximages
    [miximage]=miximages    [cart]=physicalmedia
    [cartridge]=physicalmedia                         [support]=physicalmedia
    [media3d]=3dboxes       [box3dfront]=3dboxes
)
# Source media folders with no ES-DE media-type equivalent — explicitly
# skipped (and reported) rather than silently dropped. bezel/decorations
# are emulator overlays, not ES-DE game media; map/maps are not ES-DE media.
declare -A MEDIA_SKIP=(
    [bezel]=1 [bezels]=1 [decoration]=1 [decorations]=1 [overlay]=1
    [overlays]=1 [map]=1 [maps]=1 [extras]=1
)

# EmulationStation / Batocera-style suffix → ES-DE folder map
declare -A ES_SUFFIX_MAP=(
    [image]=screenshots     [screenshot]=screenshots
    [thumb]=covers          [thumbnail]=3dboxes
    [box]=covers            [boxart]=covers          [box2d]=covers
    [marquee]=marquees
    [fanart]=fanart
    [wheel]=marquees
    [titlescreen]=titlescreens
    [manual]=manuals
    [video]=videos
    [mix]=miximages         [miximage]=miximages
    [cart]=physicalmedia    [cartridge]=physicalmedia
)

# Try to import ES/Batocera-suffix media from a flat folder.
# args: source_dir, dest_root, move_mode (yes=cut, else copy), optional relative media subdir
# returns 0 if ES-style suffixes were detected and routed, 1 if not.
try_import_es_layout() {
    local src="$1" dest="$2" move="$3" rel_subdir="${4:-}"
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
        local target_dir="$dest/$esde_folder"
        [[ -n "$rel_subdir" ]] && target_dir="$target_dir/$rel_subdir"
        mkdir -p "$target_dir"
        local dest_path="$target_dir/$rom_base.$ext"
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
    # NOTE — logo de-merge: sufami, markiii, gx4000, amigacdtv,
    # multivision, msx1 and fbneo stay as their own ES-DE systems.
    # Nested source folders are special: they import into a tidy visual folder
    # while resolving to whichever ES-DE system has the correct launch command.
    # Romhacks / homebrew: fold into the parent system as a nested "hacks"
    # folder (they share the parent's extensions + core), rather than standing
    # as their own ES-DE systems. Resolve each to its base system here; the
    # nested folder name is set in MSU_NESTED_FOLDER below.
    [snesh]=snes            [nesh]=nes              [gbh]=gb
    [gbch]=gbc              [gbah]=gba              [genh]=megadrive
    [n64h]=n64              [ggh]=gamegear
    # SNES
    [snesna]=snes          [snes-msu]=snes
    # NES
    # ProjectNested NES-MSU packs are SNES .sfc wrappers. They live under
    # ROMs/nes/nes-msu for NES theming, but resolve to the custom nes-msu
    # system so ES-DE launches them with Snes9x.
    [nes_aladdin]=nes       [nes_hd]=nes            [nes-msu]=nes-msu
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
    [sg1000]=sg-1000        [sc3000]=sg-1000
    [dreamcast-jp]=dreamcast [saturn-jp]=saturnjp
    # NEC
    [tgcd]=tg-cd
    # SNK
    [neogeomvs]=neogeo
    # Cave (bullet-hell shmups nested as a folder inside arcade)
    [cave]=arcade
    # Philips
    [cdi]=cdimono1
    # Art Book Next safe Ports / Engines — visible under ports/ only
    [cdogs]=ports            [openttd]=ports         [opentyrian]=ports
    [openra]=ports           [nxengine]=ports
    # Easy roadmap: route to already-supported systems
    [hbmame]=mame
    # Bandai
    [wswan]=wonderswan      [wswanc]=wonderswancolor
    # Commodore
    [c20]=vic20             [cplus4]=plus4          [amiga4000]=amiga
    # MSX
    [msx2+]=msx2
    # Arcade
    [gaelco]=arcade         [igspgm]=arcade          [aleck64]=arcade
)
FLAT_ROM_SYSTEMS=(c64 amiga amiga500 amiga1200 amigacd32 msx msx2 msx1 vic20 atarist zxspectrum zx81 dos atari800 pc vpinball)

# Reverse map: canonical ES-DE system → space-separated list of every
# RetroBat/folder alias that resolves to it. Built once from SYS_MAP so the
# per-system audit can show, on its own line, exactly which source folder
# names route into each system (and therefore share its launch command).
declare -A SYS_ALIASES=()
for _alias in "${!SYS_MAP[@]}"; do
    _canon="${SYS_MAP[$_alias]}"
    SYS_ALIASES[$_canon]="${SYS_ALIASES[$_canon]:-}${SYS_ALIASES[$_canon]:+ }$_alias"
done
unset _alias _canon

# Nested source folders land under tidy visual parent folders while preserving
# launch correctness. Most use the parent ES-DE system; nes-msu uses a custom
# ES-DE system whose ROM path is nested under ROMs/nes/nes-msu.
# Example: snes-msu/Game.sfc -> ROMs/snes/snes-msu/Game.sfc
#          media -> downloaded_media/snes/<media_type>/snes-msu/Game.png
# Example: nes-msu/Game.sfc -> ROMs/nes/nes-msu/Game.sfc
#          media -> downloaded_media/nes-msu/<media_type>/Game.png
# Example: neogeomvs/mslug.zip -> ROMs/neogeo/neogeomvs/mslug.zip
#          media -> downloaded_media/neogeo/<media_type>/neogeomvs/mslug.png
declare -A MSU_NESTED_FOLDER=(
    [snes-msu]=snes-msu
    [msu-md]=msu-md
    [megadrive-msu]=msu-md
    [nes-msu]=nes-msu
    [neogeomvs]=neogeomvs
    [cave]=cave
    # Romhacks / homebrew nest as a "hacks" folder inside the parent system
    # (parent resolved via SYS_MAP above; MSU_PARENT then defaults to it).
    [snesh]=hacks
    [nesh]=hacks
    [gbh]=hacks
    [gbch]=hacks
    [gbah]=hacks
    [genh]=hacks
    [n64h]=hacks
    [ggh]=hacks
    # Art Book Next safe Ports / Engines: data folders nest under ROMs/ports,
    # media under downloaded_media/ports/<type>/<engine>, and any launchable
    # menu entry should be a .sh script in ROMs/ports.
    [openttd]=openttd
    [cgenius]=cgenius
    [cdogs]=cdogs
    [opentyrian]=opentyrian
    [openra]=openra
    [cavestory]=nxengine
    [nxengine]=nxengine
)

# Optional physical ROM parent override. Used when a custom ES-DE system
# points at a nested folder under another visual hardware folder.
declare -A MSU_ROM_PARENT=(
    [nes-msu]=nes
    [cave]=arcade
)

# If set, the custom system path itself is the nested folder. Media and
# gamelist paths are therefore rooted at the file, not prefixed by the
# MSU subfolder name.
declare -A MSU_PATH_IS_SYSTEM_ROOT=(
    [nes-msu]=1
)

# Source-folder alias → required AppImage key for entries routed through ports/.
# The visible ES-DE system is always ports, but import/audit can still detect
# which backend should be installed for a given source folder.
declare -A PORT_ENGINE_FOR=(
    [openttd]=openttd
    [cgenius]=cgenius
    [cdogs]=cdogs
    [opentyrian]=opentyrian
    [openra]=openra
    [cavestory]=nxengine
    [nxengine]=nxengine
)

# ES-DE system → required standalone emulator (install_emulator handles it)
declare -A SYS_TO_EMU=(
    [gc]=dolphin           [wii]=dolphin             [wiiware]=dolphin
    [wiiu]=cemu
    [psx]=duckstation
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
    [windows]=_86box       [win98]=_86box
    [flash]=ruffle
    [solarus]=solarus
    [samcoupe]=simcoupe
    [ngage]=eka2l1
    # Ports/engines routed through the visible ports system use PORT_ENGINE_FOR
    # instead of SYS_TO_EMU so individual source folders can still trigger their backend.
    # MAME standalone systems (current MAME for software lists)
    [archimedes]=mame      [apple2gs]=mame          [adam]=mame
    [dragon32]=mame        [fm7]=mame               [ti99]=mame
    [supracan]=mame        [scv]=mame               [pv1000]=mame
    [gamate]=mame          [gmaster]=mame           [gamecom]=mame
    [videopacplus]=mame    [vsmile]=mame            [spectravideo]=mame
    [pico]=mame            [satellaview]=mame
)

# ES-DE system → recommended libretro core (install_core handles it; needs RetroArch)
declare -A SYS_TO_CORE=(
    [psx]=mednafen_psx_hw
    [dos]=dosbox_pure                 # DOS — DOSBox Pure libretro core (default)
    [saturn]=mednafen_saturn          [saturnjp]=kronos
    [snes]=snes9x                     [sfc]=snes9x
    [snesh]=snes9x                    [sgb]=snes9x
    [nes]=mesen                       [famicom]=mesen     [nesh]=fceumm
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
    [supergrafx]=mednafen_supergrafx
    [pcenginecd]=mednafen_pce_fast    [tg-cd]=mednafen_pce_fast
    [pcfx]=mednafen_pcfx
    [virtualboy]=mednafen_vb
    [ngp]=mednafen_ngp                [ngpc]=mednafen_ngp
    [wonderswan]=mednafen_wswan       [wonderswancolor]=mednafen_wswan
    [zxspectrum]=fuse                 [zx81]=81
    [c64]=vice_x64sc                  [vic20]=vice_xvic   [plus4]=vice_xplus4
    [amiga]=puae                      [amiga500]=puae
    [amiga1200]=puae                  [amigacd32]=puae
    [amstradcpc]=cap32
    [msx]=bluemsx                     [msx1]=bluemsx
    [msx2]=bluemsx                    [msxturbor]=bluemsx
    [scummvm]=scummvm
    [pico8]=retro8
    # arcade = FBNeo-curated arcade (es_systems.xml routes arcade to FBNeo by
    # default); mame = full current MAME, the system for modern romsets like
    # RGS 0.2xx sets. They are NOT interchangeable — a 0.265 romset only runs
    # on current MAME, not FBNeo and not mame2010 (each is romset-locked).
    [arcade]=fbneo
    [mame]=mame
    # Split-system and legacy explicit mappings.
    # MSU imports are remapped into nested parent folders by SYS_MAP / MSU_NESTED_FOLDER;
    # these entries remain only as fallback mappings if a top-level MSU system is populated manually.
    [fbneo]=fbneo                     # FinalBurn Neo (split from arcade)
    [gx4000]=cap32                    # Amstrad GX4000 (split from amstradcpc)
    [markiii]=genesis_plus_gx         # Sega Mark III (split from mastersystem)
    [multivision]=genesis_plus_gx     # Tsukuda Multivision (split from sg-1000)
    [amigacdtv]=puae                  # Commodore CDTV (split from amiga)
    [snes-msu]=snes9x                 # SNES MSU-1 fallback; importer nests under snes
    [nes-msu]=snes9x                  # ProjectNested NES-MSU; stored under ROMs/nes/nes-msu
    [sufami]=snes9x                   # SNES Sufami Turbo (split from snes)
    [msu-md]=genesis_plus_gx          # Mega Drive MSU-MD fallback; importer nests under megadrive
    # EASY systems batch — 9 MAME-driver computers/consoles (core: mame).
    [aquarius]=mame   [atom]=mame      [coco]=mame       [electron]=mame
    [gp32]=mame       [pegasus]=mame   [socrates]=mame   [tutor]=mame
    [vis]=mame
    # EASY systems batch — 14 single-libretro-core systems.
    [bk]=bk                           [c128]=vice_x128
    # NOTE: cavestory/nxengine is a STANDALONE port
    # (ROMs/ports/*.sh launcher), not a libretro-core system, so it is
    # intentionally absent here. (Was a malformed '[]=' block that emitted
    # 'bad array subscript' at runtime and silently dropped these keys.)
    [cassettevision]=pd777
    [dice]=dice
    [enterprise]=ep128emu_core
    [p2000t]=m2000
    [pet]=vice_xpet                   [thomson]=theodore
    # IN PROGRESS batch
    [fmtowns]=mame                    # FM Towns — MAME fmtownsux driver
    # bennugd removed — no Linux x86_64 buildbot binary exists.
    # apple2 launches via the mame libretro core (apple2e driver) per its
    # es_systems.xml entry — route it so the importer installs that core.
    [apple2]=mame
    # Cartridge-based MAME micro-consoles (Easy roadmap batch 1)
    [advision]=mame
    [apfm1000]=mame
    [astrocade]=mame
    [gamepock]=mame
    [loopy]=mame
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
    # In Progress #12 — bundled-core systems (ES-DE ships built-in definitions)
    # still need explicit importer mappings so ensure_emulator_for can install
    # the correct libretro core on demand the first time a user imports games
    # for one of these systems. Without these the importer reported
    # "no emulator/core mapping" and silently no-op'd.
    [arcadia]=amiarcadia              [atari800]=atari800
    [fds]=fceumm                      [gameandwatch]=mame
    [lcdgames]=gw                     [lowresnx]=lowresnx
    [lutro]=lutro                     [megaduck]=sameduck
    [pc88]=quasi88                    [supervision]=potator
    [wasm4]=wasm4
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
        ruffle)      compgen -G "$EMUS/ruffle*" > /dev/null || [[ -f "$EMUS/ruffle" ]] ;;
        eka2l1)      compgen -G "$EMUS/[eE]ka2l1*" > /dev/null || compgen -G "$EMUS/EKA2L1*" > /dev/null ;;
        solarus)     compgen -G "$EMUS/solarus*" > /dev/null ;;
        simcoupe)    compgen -G "$EMUS/[sS]im[cC]oupe*" > /dev/null ;;
        supermodel)  compgen -G "$EMUS/[sS]upermodel*" > /dev/null ;;
        mame)        compgen -G "$EMUS/mame*" > /dev/null || compgen -G "$EMUS/MAME*" > /dev/null ;;
        openttd)     compgen -G "$EMUS/[oO]pen[Tt][Tt][Dd]*" > /dev/null ;;
        cgenius)     compgen -G "$EMUS/[cC]ommander-[gG]enius*" > /dev/null || compgen -G "$EMUS/[cC]genius*" > /dev/null ;;
        cdogs)       compgen -G "$EMUS/C-Dogs*" > /dev/null || compgen -G "$EMUS/[cC]dogs*" > /dev/null ;;
        opentyrian)  compgen -G "$EMUS/[oO]pen[Tt]yrian*" > /dev/null || compgen -G "$EMUS/OpenTyrian2000*" > /dev/null ;;
        openra)      compgen -G "$EMUS/[oO]pen[Rr][Aa]*" > /dev/null ;;
        *)           return 1 ;;
    esac
}

is_retroarch_installed() {
    compgen -G "$EMUS/[rR]etroArch*" > /dev/null || compgen -G "$EMUS/retroarch*" > /dev/null
}

is_core_installed() {
    [[ -f "$EMUS/retroarch-cores/${1}_libretro.so" ]]
}

# ===========================================================================
# EMULATOR / CORE INSTALLATION  (folded in from install-emulator.sh +
# install-core.sh, which are no longer emitted as separate bundle files)
# ---------------------------------------------------------------------------
# These let the importer fetch a missing emulator or libretro core on demand
# during an import. Keeping them here — instead of in separate scripts —
# means the importer is the only tool that mutates the bundle, so nothing
# can change the install state behind setup's .setup-selections.cfg.
# ===========================================================================
DOWNLOAD_ERRORS=0

CORE_BASE_URL="https://buildbot.libretro.com/nightly/linux/x86_64/latest"

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

github_appimage() {
    local repo="$1" pattern="$2" outfile="$3"
    if [[ -f "$outfile" ]]; then
        ok "$(basename "$outfile") already exists, skipping"
        return 0
    fi
    info "Querying GitHub: $repo ..."
    local resp url
    resp=$(curl -sfL -H "Accept: application/vnd.github+json" \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$repo/releases?per_page=10" 2>/dev/null) || true
    if [[ -z "$resp" ]]; then
        fail "Could not reach GitHub for $repo (offline or network blocked)"
        return 1
    fi
    if printf '%s' "$resp" | grep -q 'API rate limit exceeded'; then
        fail "GitHub API rate-limited (anonymous limit is 60/hour) — could not check $repo"
        warn "Wait ~1h and re-run, or 'export GITHUB_TOKEN=<token>' to raise the limit, then re-run."
        return 2
    fi
    url=$(printf '%s' "$resp" \
        | grep -oP '"browser_download_url":\s*"\K[^"]*' \
        | grep -P "$pattern" \
        | grep -ivE 'aarch|arm64|armv7|zsync|sha256|\.sig$|\.asc$' \
        | head -1) || true
    if [[ -z "$url" ]]; then
        fail "No matching asset for pattern in $repo releases (release exists, asset does not)"
        return 1
    fi
    info "Downloading $(basename "$url") ..."
    mkdir -p "$(dirname "$outfile")"
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
    if find "$outdir" -maxdepth 1 -iname 'rpcs3*.AppImage' 2>/dev/null | grep -q .; then
        ok "RPCS3 already exists, skipping"
    else
        info "Downloading RPCS3 (latest nightly) ..."
        if (cd "$outdir" && curl -#fJLO "https://rpcs3.net/latest-linux-x64"); then
            chmod +x "$outdir"/rpcs3*.AppImage 2>/dev/null || true
            ok "RPCS3 downloaded"
        else
            fail "RPCS3 download failed"
            return 1
        fi
    fi
    # squashfuse: needed by ps3-launch.sh to mount .squashfs disc images.
    # It is a system package — call the helper only if it exists in this
    # context (setup defines it; the importer's folded copy of this function
    # does not, hence the existence check).
    declare -F ensure_squashfuse_for_ps3 >/dev/null && ensure_squashfuse_for_ps3 || true
}

#=============================================================================
# Emulator install functions
# Used by both the main install flow below AND by import-collection.sh,
# which carries a folded-in copy of these functions for on-demand
# installation when it imports a system whose emulator
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
    # Match ONLY the regular SSE4.1 build DuckStation-x64.AppImage, never
    # DuckStation-x64-SSE2.AppImage (legacy fallback for pre-2008 CPUs).
    # The old ".*x64.*" pattern matched both and grabbed SSE2 first,
    # triggering DuckStation's legacy-SSE2 hardware-check warning.
    github_appimage "stenzek/duckstation" \
        "DuckStation-x64\.AppImage$" \
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
    VPDIR="$EMUS/VPinball"
    if [[ -f "$VPDIR/VPinballX_BGFX" ]]; then
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
                mkdir -p "$VPDIR"
                # Copy binaries — search at any depth after extraction
                for BIN in VPinballX_BGFX VPinballX_GL VPinballX; do
                    FOUND=$(find "$VPINBALL_TMP" -name "$BIN" -type f 2>/dev/null | head -1)
                    if [[ -n "$FOUND" ]]; then
                        cp "$FOUND" "$VPDIR/$BIN"
                        chmod +x "$VPDIR/$BIN"
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
                    [[ ! -d "$VPDIR/$DNAME" ]] && mkdir -p "$VPDIR/$DNAME"
                    cp -rn "$D/." "$VPDIR/$DNAME/" 2>/dev/null || true
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
                    [[ -f "$VPDIR/$LIBNAME" ]] && continue
                    cp "$LIB" "$VPDIR/$LIBNAME" 2>/dev/null && VP_LIBS=$((VP_LIBS + 1))
                done < <(find "$EXTRACT_ROOT" -type f -name '*.so*' 2>/dev/null)
                # Synthesize SONAME symlinks (libFOO.so.1.2.3 -> libFOO.so.1).
                # find -type f copies only the real versioned files; the binary
                # links against the major-version SONAME. Without these links
                # the loader fails with "libSDL3.so.0: cannot open shared
                # object file". This mini-ldconfig pass makes it work whether
                # or not the archive shipped the symlinks.
                ( cd "$VPDIR" && for real in lib*.so.*; do
                    [[ -f "$real" && ! -L "$real" ]] || continue
                    soname=$(printf '%s' "$real" | sed -E 's/(\.so\.[0-9]+)\..*/\1/')
                    [[ "$soname" != "$real" && ! -e "$soname" ]] && ln -s "$real" "$soname"
                done )
                # VPinball Standalone auto-detects a pinmame/ folder next to the
                # .vpx files; create it so PinMAME-based tables (real solid-state
                # / DMD machines) have a ROM directory. Users drop romset zips
                # into ROMs/vpinball/pinmame/roms/ themselves (copyrighted, like
                # arcade ROMs — not bundled).
                mkdir -p "$ROMS/vpinball/pinmame/roms" "$ROMS/vpinball/pinmame/nvram" "$ROMS/vpinball/pinmame/altcolor" "$ROMS/vpinball/pinmame/altsound" "$ROMS/vpinball/pinmame/cfg" "$ROMS/vpinball/pinmame/samples" "$ROMS/vpinball/pinmame/ini" "$ROMS/vpinball/music"
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

# install_emulator <name> — dispatch to the right install_<emu> function.
# (Folded in from the former standalone install-emulator.sh; the importer is
# now the single tool that installs emulators on demand during an import.)

# Ports / engines AppImage batch


install_cgenius() {


    github_appimage "pkgforge-dev/Commander-Genius-AppImage" \
        ".*\.AppImage$" \

install_openttd() {
    github_appimage "pkgforge-dev/OpenTTD-AppImage" \
        ".*\.AppImage$" \
        "$EMUS/OpenTTD/OpenTTD-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

        "$EMUS/Commander-Genius/Commander-Genius-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}

install_cdogs() {
    github_appimage "pkgforge-dev/C-Dogs_SDL-AppImage" \
        ".*\.AppImage$" \
        "$EMUS/C-Dogs_SDL/C-Dogs_SDL-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}








install_opentyrian() {
    github_appimage "pkgforge-dev/OpenTyrian2000-AppImage" \
        ".*\.AppImage$" \
        "$EMUS/OpenTyrian2000/OpenTyrian2000-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}



install_openra() {
    github_appimage "pkgforge-dev/OpenRA-AppImage-Enhanced" \
        ".*\.AppImage$" \
        "$EMUS/OpenRA/OpenRA-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}







install_nxengine() {
    github_appimage "pkgforge-dev/NXEngine-evo-AppImage-Enhanced" \
        ".*\.AppImage$" \
        "$EMUS/NXEngine/NXEngine-latest.AppImage" || DOWNLOAD_ERRORS=$((DOWNLOAD_ERRORS + 1)) || true
}


install_emulator() {
    case "$1" in
        rpcs3)        install_rpcs3 ;;
        retroarch)    install_retroarch ;;
        pcsx2)        install_pcsx2 ;;
        duckstation)  install_duckstation ;;
        ppsspp)       install_ppsspp ;;
        melonds)      install_melonds ;;
        dolphin)      install_dolphin ;;
        cemu)         install_cemu ;;
        azahar)       install_azahar ;;
        xemu)         install_xemu ;;
        xenia)        install_xenia ;;
        ryujinx)      install_ryujinx ;;
        eden)         install_eden ;;
        shadps4)      install_shadps4 ;;
        _86box)       install__86box ;;
        vpinball)     install_vpinball ;;
        ruffle)       install_ruffle ;;
        eka2l1)       install_eka2l1 ;;
        solarus)      install_solarus ;;
        simcoupe)     install_simcoupe ;;
        supermodel)   install_supermodel ;;
        mame)         install_mame ;;
        openttd)      install_openttd ;;
        cgenius)      install_cgenius ;;
        cdogs)        install_cdogs ;;
        opentyrian)   install_opentyrian ;;
        openra)       install_openra ;;
        nxengine)     install_nxengine ;;
        *)            fail "Unknown emulator: $1"; return 1 ;;
    esac
}


# ===========================================================================
# BIOS VERIFICATION  (folded in from the former standalone verify-bios.sh)
# ---------------------------------------------------------------------------
# verify-bios.sh is no longer emitted as a separate bundle file. Its table
# and verify_* functions live here so the importer is the single tool that
# touches the bundle — there is no separate script whose state could drift
# from .setup-selections.cfg. BIOS verification runs only as part of an
# import (per-system after each import, and a final sweep at the end).
# ===========================================================================

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
    # ── Sony PlayStation 2 (ps2) — PCSX2 ──
    # PCSX2 doesn't enforce filename — it scans bios/ and picks anything that
    # looks like a PS2 BIOS by content. So users end up with all sorts of
    # names. The entries below cover the common per-region SCPH-NNNNN naming
    # (lowercase or mixed case, per PCSX2 wiki / Batocera / RetroBat) plus
    # the descriptor-prefixed Redump-style names. Any ONE of these satisfies
    # the region group — REQ_ANY:region. Hashes from RetroBat/Batocera wikis.
    "ps2|scph10000.bin|REQ_ANY:region|LOW|-|PS2 BIOS Japan v1.00 (SCPH-10000, fat)"
    "ps2|SCPH30004R.bin|REQ_ANY:region|HIGH|28922c703cc7d2cf856f177f2985b3a9|PS2 BIOS Europe (SCPH-30004R, fat)"
    "ps2|scph30004r.bin|REQ_ANY:region|HIGH|28922c703cc7d2cf856f177f2985b3a9|PS2 BIOS Europe (SCPH-30004R, fat) — lowercase"
    "ps2|scph39001.bin|REQ_ANY:region|HIGH|d5ce2c7d119f563ce04bc04dbc3a323e|PS2 BIOS USA v1.60 (SCPH-39001, fat)"
    "ps2|scph50001.bin|REQ_ANY:region|LOW|-|PS2 BIOS USA v1.90 (SCPH-50001, fat)"
    "ps2|scph70004.bin|REQ_ANY:region|LOW|-|PS2 BIOS Europe (SCPH-70004, slim)"
    "ps2|scph70012.bin|REQ_ANY:region|LOW|-|PS2 BIOS USA (SCPH-70012, slim)"
    "ps2|scph77001.bin|REQ_ANY:region|LOW|-|PS2 BIOS USA (SCPH-77001, slim)"
    "ps2|scph90001.bin|REQ_ANY:region|LOW|-|PS2 BIOS USA (SCPH-90001, slim)"
    # Descriptor-prefixed Redump-style names (less common in the wild)
    "ps2|ps2-0230a-20080220.bin|REQ_ANY:region|MED|9b0fcab1ee9e74c20efde6aebd96e80b|PS2 BIOS USA v2.30 (Redump style)"
    "ps2|ps2-0220a-20060905.bin|REQ_ANY:region|MED|9c0d3dcdde9b1e4ac3f08fa1f3a36f0e|PS2 BIOS USA v2.20 (Redump style)"
    "ps2|ps2-0190a-20030822.bin|REQ_ANY:region|LOW|-|PS2 BIOS USA v1.90 (Redump style)"
    "ps2|SCPH-70012_BIOS_V12_USA_200.BIN|REQ_ANY:region|LOW|-|PS2 BIOS slim USA (Redump style)"
    "ps2|SCPH-77001_BIOS_V14_USA_220.BIN|REQ_ANY:region|LOW|-|PS2 BIOS slim USA alt (Redump style)"

    # ── Sega Saturn (saturn, saturnjp) — Beetle Saturn ──
    "saturn|sega_101.bin|REQ_ANY:region|HIGH|85ec9ca47d8f6807718151cbcca8b964|Saturn BIOS NTSC-J"
    "saturn|mpr-17933.bin|REQ_ANY:region|HIGH|3240872c70984b6cbfda1586cab68dbe|Saturn BIOS NTSC-U/PAL"
    "saturnjp|sega_101.bin|REQ_ANY:region|HIGH|85ec9ca47d8f6807718151cbcca8b964|Saturn BIOS NTSC-J"
    "saturnjp|mpr-17933.bin|REQ_ANY:region|HIGH|3240872c70984b6cbfda1586cab68dbe|Saturn BIOS NTSC-U/PAL (fallback)"

    # ── Sega CD / Mega-CD (segacd, megacd) — Genesis Plus GX / Picodrive ──
    "segacd|bios_CD_J.bin|REQ_ANY:region|HIGH|278a9397d192149e84e820ac621a8edd|Sega CD BIOS Japan"
    "segacd|bios_CD_U.bin|REQ_ANY:region|HIGH|854b9150240a198070150e4566ae1290,2efd74e3232ff260e371b99f84024f7f|Sega CD BIOS USA (model 2 or 1.10 Rev B)"
    "segacd|bios_CD_E.bin|REQ_ANY:region|HIGH|e66fa1dc5820d254611fdcdba0662372|Mega-CD BIOS Europe"
    "megacd|bios_CD_J.bin|REQ_ANY:region|HIGH|278a9397d192149e84e820ac621a8edd|Mega-CD BIOS Japan"
    "megacd|bios_CD_U.bin|REQ_ANY:region|HIGH|854b9150240a198070150e4566ae1290,2efd74e3232ff260e371b99f84024f7f|Sega CD BIOS USA (model 2 or 1.10 Rev B)"
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
    "x68000|keropi/iplrom.dat|REQ|MED|-|X68000 IPL ROM"
    "x68000|keropi/cgrom.dat|REQ|MED|-|X68000 Character Generator ROM"

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
    "apple2|apple2e.zip|REQ|MED|-|Apple IIe ROM (MAME-style zip, apple2e driver)"
    "channelf|sl31253.bin|REQ|HIGH|-|Fairchild Channel F BIOS - PSU 1 (FreeChaF core, required)"
    "channelf|sl31254.bin|REQ|HIGH|-|Fairchild Channel F BIOS - PSU 2 (FreeChaF core, required)"
    "odyssey2|o2rom.bin|REQ|HIGH|-|Magnavox Odyssey2 / Videopac BIOS (O2EM core, required)"

    # ── Funtech Super A'Can (supracan) — MAME standalone ──
    "supracan|supracan.zip|OPT|LOW|-|Super A'Can BIOS (optional, MAME-style zip)"

    # ── Epoch Super Cassette Vision (scv) — MAME standalone ──
    "scv|scv.zip|OPT|LOW|-|Super Cassette Vision BIOS (optional, MAME-style zip)"

    # ── Casio PV-1000 (pv1000) — MAME standalone ──
    "pv1000|pv1000.zip|OPT|LOW|-|PV-1000 BIOS (optional, MAME-style zip)"

    # ── Nintendo Famicom Disk System / NES disk addon ──
    "nes|disksys.rom|OPT|HIGH|ca30b50f880eb660a320674ed365ef7a|FDS BIOS (required only for .fds games)"
    "famicom|disksys.rom|OPT|HIGH|ca30b50f880eb660a320674ed365ef7a|FDS BIOS (required only for .fds games)"
    "fds|disksys.rom|REQ|HIGH|ca30b50f880eb660a320674ed365ef7a|Famicom Disk System BIOS (required for all FDS disk images)"

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
# BIOS import helpers
#
# Real BIOS filenames come from BIOS_TABLE. If one of these files appears
# beside ROMs, it is routed to ROMs/bios instead of being shown as a game.
# Required MAME-style BIOS zips such as neogeo.zip, awbios.zip, naomi.zip,
# apple2gs.zip, etc. are preserved as zip files because RetroArch/MAME cores
# expect the archive itself. Generic BIOS bundles such as bios.zip,
# bios.7z, firmware.rar are extracted into ROMs/bios without overwriting.
#=============================================================================

declare -A BIOS_FILE_BY_NAME=()      # lowercased name -> 1 (known marker)
declare -A BIOS_CANON_NAME=()        # lowercased name -> canonical-cased name ("" if ambiguous)
for _bios_entry in "${BIOS_TABLE[@]}"; do
    IFS='|' read -r _bios_sys _bios_file _bios_req _bios_conf _bios_md5 _bios_desc <<< "$_bios_entry"
    [[ -n "$_bios_file" ]] || continue
    _bios_lk="${_bios_file,,}"
    BIOS_FILE_BY_NAME["$_bios_lk"]=1
    # Track the canonical case. If the table lists the SAME filename under
    # two different cases on purpose (e.g. SCPH30004R.bin AND scph30004r.bin),
    # mark it ambiguous ("") so import does NOT rename — the user's own case
    # is then preserved for those entries.
    if [[ -z "${BIOS_CANON_NAME[$_bios_lk]+x}" ]]; then
        BIOS_CANON_NAME["$_bios_lk"]="$_bios_file"
    elif [[ "${BIOS_CANON_NAME[$_bios_lk]}" != "$_bios_file" ]]; then
        BIOS_CANON_NAME["$_bios_lk"]=""
    fi
done
unset _bios_entry _bios_sys _bios_file _bios_req _bios_conf _bios_md5 _bios_desc _bios_lk

is_known_bios_file() {
    local base="${1##*/}"
    [[ -n "${BIOS_FILE_BY_NAME[${base,,}]:-}" ]]
}

# Canonical (table-cased) filename for a known BIOS file, or empty if the
# table is case-ambiguous for that name. Used so a user's wrong-cased dump
# (SCPH5501.BIN, BIOS_CD_U.BIN, ...) lands in ROMs/bios under the exact name
# the libretro core expects on a case-sensitive filesystem.
canonical_bios_name() {
    local base="${1##*/}"
    printf '%s' "${BIOS_CANON_NAME[${base,,}]:-}"
}

is_archive_file() {
    local lower="${1,,}"
    [[ "$lower" == *.zip || "$lower" == *.7z || "$lower" == *.rar ]]
}

looks_like_generic_bios_archive() {
    local base="${1##*/}" lower="${base,,}"
    is_archive_file "$base" || return 1
    # Anchored generic BIOS archive detection. Only triggers outside the
    # source's own bios/ folder (inside bios/ allow_unknown=true covers
    # everything). Must not match game archives that happen to contain
    # a keyword — "Battlezone (System 16).zip", "Kickstart (homebrew).zip",
    # "Sound System.zip", etc. Known BIOS filenames (neogeo.zip, naomi.zip,
    # dragon32.zip, etc.) are handled separately by is_known_bios_file via
    # BIOS_TABLE and are not affected by this filter.
    #
    # Allowed shapes:
    #   bios.zip, bios-eu.zip, bios_amiga.7z, bios.eu.zip
    #   firmware.zip, firmware_v1.rar
    #   kickstart.zip, kickstart-3.1.zip
    #   system-bios.zip, system_bios.zip, systembios.zip, system bios.zip
    #
    # Rejected:
    #   system.zip, system.7z  (plain "system" is too broad)
    #   Sound System.zip       (does not START with keyword)
    #   Kickstart (homebrew).zip  (paren is not a valid separator)
    #   Battlezone (System 16).zip  (does not start with keyword)
    [[ "$lower" =~ ^(bios|firmware|kickstart|system[-\ _]?bios)([._-].*)?\.(zip|7z|rar)$ ]]
}

_extract_bios_archive() {
    local archive="$1" lower="${archive,,}"
    mkdir -p "$BIOS_DIR"

    if [[ "$lower" == *.zip ]]; then
        if command -v unzip >/dev/null 2>&1; then
            unzip -qn "$archive" -d "$BIOS_DIR" >/dev/null 2>&1 && return 0
        elif command -v 7z >/dev/null 2>&1; then
            7z x -aos -o"$BIOS_DIR" "$archive" >/dev/null 2>&1 && return 0
        else
            warn "Cannot extract BIOS zip, install unzip or p7zip-full: $(basename "$archive")"
            return 1
        fi
    elif [[ "$lower" == *.rar ]]; then
        if command -v unrar >/dev/null 2>&1; then
            unrar x -o- -idq "$archive" "$BIOS_DIR/" >/dev/null 2>&1 && return 0
        elif command -v 7z >/dev/null 2>&1; then
            7z x -aos -o"$BIOS_DIR" "$archive" >/dev/null 2>&1 && return 0
        else
            warn "Cannot extract BIOS rar, install unrar or p7zip-full: $(basename "$archive")"
            return 1
        fi
    elif [[ "$lower" == *.7z ]]; then
        if command -v 7z >/dev/null 2>&1; then
            7z x -aos -o"$BIOS_DIR" "$archive" >/dev/null 2>&1 && return 0
        else
            warn "Cannot extract BIOS 7z, install p7zip-full: $(basename "$archive")"
            return 1
        fi
    fi

    return 1
}

_import_bios_file() {
    local src="$1"
    local allow_unknown="${2:-false}"   # true only for files inside a source bios/ tree
    [[ -f "$src" ]] || return 1

    local base lower dest
    base="$(basename "$src")"
    lower="${base,,}"
    dest="$BIOS_DIR/$base"
    mkdir -p "$BIOS_DIR"

    # Preserve required BIOS archives exactly as archives, e.g. neogeo.zip.
    if is_known_bios_file "$base"; then
        # Normalise case to what the core expects. canonical_bios_name returns
        # "" when the table is intentionally case-ambiguous for this name —
        # in that case keep the user's original filename.
        local canon; canon="$(canonical_bios_name "$base")"
        [[ -z "$canon" ]] && canon="$base"
        dest="$BIOS_DIR/$canon"
        if [[ -e "$dest" ]]; then
            return 0
        fi
        if [[ "$RETROBAT_MOVE" == "yes" ]]; then
            mv -n "$src" "$dest" 2>/dev/null || cp -n "$src" "$dest" 2>/dev/null || true
        else
            cp -n "$src" "$dest" 2>/dev/null || true
        fi
        return 0
    fi

    # Generic archives are extraction bundles, not BIOS archives required by a core.
    if is_archive_file "$base"; then
        if [[ "$allow_unknown" == "true" ]] || looks_like_generic_bios_archive "$base"; then
            _extract_bios_archive "$src"
            return $?
        fi
        return 1
    fi

    # Inside bios/ we keep loose unknown files too. RetroArch BIOS naming is not
    # always predictable, and PCSX2 in particular accepts many valid names.
    if [[ "$allow_unknown" == "true" ]]; then
        [[ -e "$dest" ]] && return 0
        if [[ "$RETROBAT_MOVE" == "yes" ]]; then
            mv -n "$src" "$BIOS_DIR/" 2>/dev/null || cp -n "$src" "$BIOS_DIR/" 2>/dev/null || true
        else
            cp -n "$src" "$BIOS_DIR/" 2>/dev/null || true
        fi
        return 0
    fi

    return 1
}

_is_bios_junk() {
    # True for files that are clearly NOT BIOS and must never be copied into
    # ROMs/bios on import. RetroBat's bios/ ships a lot of these alongside the
    # real BIOS (.map files, readmes, images, manuals, OS cruft); the keep-
    # unknown import rule has no other way to tell them apart, so they pile up
    # as clutter. Deliberately does NOT exclude .xml/.dat/.cfg — blueMSX-style
    # core trees legitimately use those (e.g. bios/Databases/*.xml).
    local b="${1,,}"
    case "$b" in
        *.txt|*.md|*.nfo|*.diz|*.htm|*.html|*.pdf|*.doc|*.docx|*.rtf|*.url|*.log|*.csv) return 0 ;;
        *.jpg|*.jpeg|*.png|*.gif|*.bmp|*.webp|*.ico|*.svg|*.tga) return 0 ;;
        *.map|*.m3u|*.cue|*.toc|*.sav|*.srm|*.state|*.bak|*.old) return 0 ;;
        readme*|read.me|license*|licence*|changelog*|authors*|copying*|history*|whatsnew*) return 0 ;;
        thumbs.db|desktop.ini|.ds_store|*.lnk) return 0 ;;
    esac
    return 1
}

_import_bios_tree() {
    local src_dir="$1"
    [[ -d "$src_dir" ]] || return 0
    src_dir="${src_dir%/}"

    local imported=0 extracted=0 skipped=0 nested=0 junk=0 f base rel before_count after_count
    mkdir -p "$BIOS_DIR"

    while IFS= read -r -d '' f; do
        base="$(basename "$f")"
        rel="${f#"$src_dir"/}"

        # Skip obvious non-BIOS clutter (maps, docs, images, OS cruft) so it
        # never lands in ROMs/bios — at any depth. Recognized BIOS files are
        # always kept, even if their extension looks junky.
        if _is_bios_junk "$base" && ! is_known_bios_file "$base"; then
            junk=$((junk + 1)); continue
        fi

        # Files inside a SUBFOLDER of the source bios tree must keep their
        # relative path under ROMs/bios. Several cores ship their system files
        # as a directory tree, not loose files — e.g. blueMSX (ColecoVision,
        # MSX, SVI) needs bios/Machines/<machine>/ and bios/Databases/. The old
        # code flattened everything to the basename, which silently broke those
        # systems (ColecoVision wouldn't launch). Replicate the structure as-is;
        # never extract or rename nested files.
        if [[ "$rel" == */* ]]; then
            local ddest="$BIOS_DIR/$rel"
            if [[ -e "$ddest" ]]; then
                skipped=$((skipped + 1)); continue
            fi
            mkdir -p "$(dirname "$ddest")"
            if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                mv -n "$f" "$ddest" 2>/dev/null || cp -n "$f" "$ddest" 2>/dev/null || true
            else
                cp -n "$f" "$ddest" 2>/dev/null || true
            fi
            nested=$((nested + 1))
            continue
        fi

        # Root-level files: flat / case-canonical / archive-extract handling.
        if is_archive_file "$base" && ! is_known_bios_file "$base"; then
            before_count=$(find "$BIOS_DIR" -type f 2>/dev/null | wc -l)
            if _import_bios_file "$f" true; then
                after_count=$(find "$BIOS_DIR" -type f 2>/dev/null | wc -l)
                extracted=$((extracted + 1))
                (( after_count == before_count )) && skipped=$((skipped + 1))
            fi
        else
            if [[ -e "$BIOS_DIR/$base" ]]; then
                skipped=$((skipped + 1))
            fi
            _import_bios_file "$f" true && imported=$((imported + 1))
        fi
    done < <(find "$src_dir" -type f -print0 2>/dev/null)

    echo -e " ${GREEN}done${NC} ($imported file(s), $nested nested, $extracted archive(s), $junk non-BIOS skipped, existing files skipped)"
}

_bios_sidecars_for_system_folder() {
    local sys_dir="$1" f base lower hits=0
    while IFS= read -r -d '' f; do
        base="$(basename "$f")"
        lower="${base,,}"
        if is_known_bios_file "$base"; then
            echo "     BIOS sidecar:    $base → ROMs/bios (known BIOS file, hidden from game folder)"
            hits=$((hits + 1))
        elif looks_like_generic_bios_archive "$base"; then
            echo "     BIOS archive:    $base → extract to ROMs/bios (existing files skipped)"
            hits=$((hits + 1))
        fi
    done < <(find "$sys_dir" -maxdepth 1 -type f -print0 2>/dev/null)
    return 0
}


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
    [fds]=fds                # Famicom Disk System — needs disksys.rom (REQ)
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
    [atarijaguarcd]=jaguarcd
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
    [apple2]=apple2
    [channelf]=channelf
    [odyssey2]=odyssey2
    [videopac]=odyssey2
    [videopacplus]=odyssey2
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
    # Defensive: if BIOS_DIR is unset/empty (e.g. a future refactor inlines
    # this elsewhere without bringing BIOS_DIR with it) resolve from ROMS.
    # Without this, "$BIOS_DIR/$file" would expand to "/$file" and look at
    # the filesystem root — every BIOS would report MISSING.
    local bdir="${BIOS_DIR:-${ROMS:+$ROMS/bios}}"
    [[ -z "$bdir" ]] && { echo "MISSING"; return; }
    local path="$bdir/$file"
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

# Detect missing emulator/core for an ES-DE system, prompt to install, dispatch.
# Called right after each system's import block finishes.
ensure_emulator_for() {
    local esde_sys="$1" rb_sys="${2:-$1}"
    local emu="${PORT_ENGINE_FOR[$rb_sys]:-${SYS_TO_EMU[$esde_sys]:-}}"
    local core="${SYS_TO_CORE[$esde_sys]:-}"

    if [[ -n "$emu" ]] && ! is_emulator_installed "$emu"; then
        echo ""
        if wt_yesno "Missing emulator: $emu" \
"$esde_sys ROMs were imported but the $emu emulator is not installed.

Install $emu now?"; then
            install_emulator "$emu" || warn "install of $emu failed"
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
                install_emulator retroarch || warn "install of retroarch failed"
                install_core "$core" || warn "install of core $core failed"
            else
                info "Skipped RetroArch + $core install — $esde_sys games will not launch until you install them"
            fi
            echo ""
        elif ! is_core_installed "$core"; then
            echo ""
            if wt_yesno "Missing libretro core: $core" \
"$esde_sys ROMs were imported but the $core libretro core is not installed.

Install $core now?"; then
                install_core "$core" || warn "install of core $core failed"
            else
                info "Skipped $core install — $esde_sys games will not launch until you install it"
            fi
            echo ""
        fi
    fi
}

# ── MAME folder-romset normaliser ─────────────────────────────────────────
# Systems whose ROMs are MAME-style (mame core / mame2010 / fbneo arcade).
# A CHD-based game often arrives from a RetroBat pack as ONE folder per game
# holding the parent .zip AND its .chd image(s) together, e.g.
#     blitz2k/blitz2k.zip
#     blitz2k/blitz2k.chd
# If that folder is copied wholesale into ROMs/mame/ two problems result:
#   1. ES-DE shows it as a *browsable folder*, not a game. %GAMEDIRRAW% then
#      resolves to ROMs/mame/blitz2k (the subfolder) — the wrong rompath —
#      and scraped media keys to the folder instead of the game.
#   2. Multi-CHD romsets fail to launch.
#
# What MAME actually wants. The mame/arcade launch command is
#   "%BASENAME% -rompath \"%GAMEDIRRAW%;%ROMPATH%/<sys>;%ROMPATH%/bios\""
# MAME resolves a game by looking, inside each rompath dir, for a .zip/.7z
# archive OR a folder matching the romset SHORT NAME, with CHD images living
# in a folder named after that short name. So the correct on-disk layout is
# two SIBLINGS sitting flat in ROMs/<system>/ :
#     ROMs/mame/blitz2k.zip          ← parent archive = the ES-DE game entry
#     ROMs/mame/blitz2k/blitz2k.chd  ← short-name folder holding the CHD(s)
#
# normalise_mame_folder() converts a copied per-game folder into that form:
#   • Case A — folder has a parent archive: the archive is moved FLAT to
#     ROMs/<system>/<romset>.<ext> (becoming the real game entry, correct
#     %BASENAME%); any CHD(s) stay in the short-name folder, which is then
#     marked <hidden> in the gamelist so it does not show as an empty entry.
#   • Case B — CHD-only set (no archive, pure software-list): the bare
#     short-name folder IS the correct MAME romset directory and is kept; a
#     real (non-hidden) <game> entry pointing at the folder is written so
#     ES-DE has something to launch.
# The COUNT of CHDs is irrelevant — MAME reads them all from the rompath
# directory. An inner CHD's filename is never adopted as the entry name,
# because CHDs are frequently named differently from the romset short name.
declare -A MAME_FAMILY=( [mame]=1 [arcade]=1 [hbmame]=1 )
normalise_mame_folder() {
    # $1 = full path to a romset folder already copied into ROMs/<system>/
    # $2 = (optional) gamelist dir for this system — used to hide a leftover
    #      CHD short-name folder, or to register a CHD-only set as a game.
    #
    # The MAME libretro core launch command uses %BASENAME% (romset short
    # name) and a rompath of %ROMPATH%/<system>. MAME then resolves a game by
    # looking — inside each rompath dir — for a folder OR a .zip/.7z archive
    # matching the romset SHORT NAME (no extension), and for CHD images in a
    # FOLDER named after that short name.
    #
    # So the correct on-disk layout for a CHD game 'blitz2k' is two SIBLINGS
    # sitting flat in ROMs/mame/ :
    #     ROMs/mame/blitz2k.zip          ← parent ROM archive (the game entry)
    #     ROMs/mame/blitz2k/blitz2k.chd  ← short-name folder holding the CHD(s)
    #
    # A RetroBat-style pack instead ships ONE folder per game containing both
    # the .zip and the .chd(s). If we just copy that folder wholesale, ES-DE
    # shows it as a browsable folder, %GAMEDIRRAW% resolves to the subfolder
    # (rompath becomes ROMs/mame/blitz2k — wrong) and multi-CHD games fail.
    #
    # This function SPLITS such a folder into the correct layout:
    #   • the .zip / .7z parent archive is moved FLAT into ROMs/<system>/
    #     — this becomes the ES-DE game entry (a real file, correct BASENAME);
    #   • the .chd file(s) stay in a folder named exactly the romset short
    #     name (the folder is renamed if needed and stripped of the archive);
    #   • a CHD-only folder (no archive — pure software-list set) is left as
    #     a short-name folder, which MAME treats as a valid romset directory.
    local dir="$1" gldir="${2:-}"
    [[ -d "$dir" ]] || return 0
    local parent rom; parent=$(dirname "$dir"); rom=$(basename "$dir")
    # Folder already carries an archive extension from an older (buggy) run?
    # Strip it back to the bare short name so we land on the correct layout.
    case "$rom" in
        *.zip|*.7z|*.ZIP|*.7Z)
            local stripped="${rom%.*}"
            if [[ ! -e "$parent/$stripped" ]] && mv -n "$dir" "$parent/$stripped" 2>/dev/null; then
                dir="$parent/$stripped"; rom="$stripped"
            fi ;;
        *.chd|*.CHD)
            # A '<name>.chd' DIRECTORY is the old-format mistake. Rename to
            # the bare short name — MAME wants the CHD folder un-suffixed.
            local stripped="${rom%.*}"
            if [[ ! -e "$parent/$stripped" ]] && mv -n "$dir" "$parent/$stripped" 2>/dev/null; then
                dir="$parent/$stripped"; rom="$stripped"
            fi ;;
    esac

    # Inventory the folder.
    local -a zips=() chds=()
    shopt -s nullglob nocaseglob
    zips=("$dir"/*.zip "$dir"/*.7z)
    chds=("$dir"/*.chd)
    shopt -u nullglob nocaseglob

    if [[ ${#zips[@]} -eq 0 && ${#chds[@]} -eq 0 ]]; then
        warn "MAME: $rom/ holds no .zip/.7z/.chd — left as folder (nothing launchable inside)"
        return 0
    fi

    # _mame_hide_folder <gamelist_dir> <romset>
    # Append a hidden <folder> entry so a short-name CHD directory that MAME
    # needs on disk does not surface as an empty browsable folder in ES-DE.
    # Idempotent: skips if an entry for that path already exists.
    _mame_hide_folder() {
        local gldir="$1" name="$2"
        [[ -n "$gldir" ]] || return 0
        mkdir -p "$gldir"
        local gl="$gldir/gamelist.xml"
        local entry="  <folder>
    <path>./$name</path>
    <name>$name</name>
    <hidden>true</hidden>
  </folder>"
        if [[ -f "$gl" ]]; then
            grep -qF "<path>./$name</path>" "$gl" 2>/dev/null && return 0
            # Insert before the closing tag; create a minimal file if malformed.
            if grep -q '</gameList>' "$gl" 2>/dev/null; then
                local tmp; tmp=$(mktemp)
                awk -v e="$entry" '/<\/gameList>/{print e} {print}' "$gl" > "$tmp" && mv "$tmp" "$gl"
            else
                printf '%s\n%s\n%s\n' '<?xml version="1.0"?>' '<gameList>' "$entry" >> "$gl"
                echo '</gameList>' >> "$gl"
            fi
        else
            printf '%s\n%s\n%s\n%s\n' '<?xml version="1.0"?>' '<gameList>' "$entry" '</gameList>' > "$gl"
        fi
    }

    # Case A — folder has a parent archive (with or without CHDs).
    # Move the FIRST archive flat as <rom>.<ext>; that file is the game entry.
    if [[ ${#zips[@]} -gt 0 ]]; then
        local arc="${zips[0]}" arcext
        arcext="${arc##*.}"; arcext="${arcext,,}"
        local flat="$parent/$rom.$arcext"
        if [[ -e "$flat" ]]; then
            warn "MAME: $rom — '$rom.$arcext' already exists flat; folder left as-is"
        else
            mv -n "$arc" "$flat" 2>/dev/null || warn "MAME: could not flatten $rom archive"
        fi
        # Any further archives in the folder are clones/alts — leave them
        # inside the short-name folder; MAME finds them via the rompath dir.
        if [[ ${#chds[@]} -gt 0 ]]; then
            # CHDs remain in the short-name folder beside the flat archive.
            # MAME resolves them via the rompath; ES-DE would otherwise show
            # the folder as an empty entry, so mark it hidden in the gamelist.
            _mame_hide_folder "$gldir" "$rom"
            ok "MAME: $rom — archive flattened, ${#chds[@]} CHD(s) kept in $rom/ (folder hidden)"
        else
            # No CHDs: the folder now holds only stray/clone files. If it is
            # empty, drop it; otherwise keep it (MAME reads it via rompath).
            if rmdir "$dir" 2>/dev/null; then
                ok "MAME: $rom — archive flattened (folder emptied)"
            else
                _mame_hide_folder "$gldir" "$rom"
                ok "MAME: $rom — archive flattened ($rom/ kept for extra files, hidden)"
            fi
        fi
        return 0
    fi

    # Case B — no parent archive INSIDE the folder. Two sub-cases:
    #
    #   B1 (State A) — a flat <romset>.zip/.7z ALREADY sits in the system
    #      dir, as a sibling of this folder. This is the common RetroBat
    #      layout: ROMs/mame/blitz2k.zip (parent ROM, the real game entry)
    #      + ROMs/mame/blitz2k/blitz2k.chd (the CHD container). Nothing to
    #      move — the flat zip is already correct. The folder must NOT get
    #      its own <game> entry (that is what makes ES-DE launch the folder
    #      with %GAMEDIRRAW%=ROMs/mame/blitz2k). Just hide the folder so it
    #      does not surface as a browsable entry; MAME finds the CHD via the
    #      rompath because the folder name equals the romset short name.
    #
    #   B2 — genuinely CHD-only (no flat archive anywhere): the bare
    #      short-name folder IS the romset directory and must be kept, AND
    #      it needs a real <game> entry pointing at it so ES-DE has
    #      something to launch.
    local flat_zip="" _fz
    for _fz in "$parent/$rom.zip" "$parent/$rom.7z" "$parent/$rom.ZIP" "$parent/$rom.7Z"; do
        [[ -f "$_fz" ]] && { flat_zip="$_fz"; break; }
    done
    if [[ -n "$flat_zip" ]]; then
        # B1 — flat parent archive already present. Hide the CHD folder.
        _mame_hide_folder "$gldir" "$rom"
        ok "MAME: $rom — flat $(basename "$flat_zip") already present; CHD folder hidden (${#chds[@]} CHD(s))"
        return 0
    fi

    # B2 — CHD-only set (no parent archive anywhere). MAME treats a rompath
    # subfolder matching the short name as a valid romset directory, so the
    # bare short-name folder IS the correct on-disk form and must be kept.
    # With no flat archive there is no ES-DE game entry — the romset is
    # launchable only if a gamelist entry points at it. Write a real (not
    # hidden) <game> entry whose <path> is the folder itself: ES-DE passes
    # the folder, %BASENAME% resolves to the short name, MAME loads the CHD.
    local gl="$gldir/gamelist.xml"
    if [[ -n "$gldir" ]]; then
        mkdir -p "$gldir"
        if ! { [[ -f "$gl" ]] && grep -qF "<path>./$rom</path>" "$gl" 2>/dev/null; }; then
            local entry="  <game>
    <path>./$rom</path>
    <name>$rom</name>
  </game>"
            if [[ -f "$gl" ]] && grep -q '</gameList>' "$gl" 2>/dev/null; then
                local tmp; tmp=$(mktemp)
                awk -v e="$entry" '/<\/gameList>/{print e} {print}' "$gl" > "$tmp" && mv "$tmp" "$gl"
            elif [[ -f "$gl" ]]; then
                printf '%s\n' "$entry" >> "$gl"; echo '</gameList>' >> "$gl"
            else
                printf '%s\n%s\n%s\n%s\n' '<?xml version="1.0"?>' '<gameList>' "$entry" '</gameList>' > "$gl"
            fi
        fi
    fi
    ok "MAME: $rom/ — CHD-only set (${#chds[@]} CHD(s)), kept as short-name folder + gamelist entry"
    return 0
}

# ── Per-system launch-command audit ─────────────────────────────────────
# Prints, for ONE system, on its own lines: the resolved emulator/core, the
# exact launch-command pattern ES-DE will run, and every folder alias that
# routes into the same canonical system (all sharing that command). Used by
# BOTH the dry-run reporter and the real import loop so the two never drift
# — a wrong rompath or folder-vs-flat mismatch is visible at a glance during
# an actual import, not only under -test (Audit F-launch / Step A).
# Args: $1 = RB_SYS (source folder name)   $2 = ESDE_SYS (canonical name)
# Optionally appends to needs_install / unknown_systems if those arrays are
# in scope (dry-run); harmless when they are not (real import) because the
# appends are guarded.
print_launch_audit() {
    local rb_sys="$1" esde_sys="$2"
    local emu core launch_cmd=""
    emu="${PORT_ENGINE_FOR[$rb_sys]:-${SYS_TO_EMU[$esde_sys]:-}}"
    core="${SYS_TO_CORE[$esde_sys]:-}"
    if [[ -n "$emu" ]]; then
        launch_cmd="standalone: $emu   →   %EMULATOR_${emu^^}% %ROM%"
        if is_emulator_installed "$emu"; then
            echo -e "     Launches: $emu ${GREEN}(installed)${NC}"
        else
            echo -e "     Launches: $emu ${YELLOW}(NOT installed — would prompt to install)${NC}"
            declare -p needs_install &>/dev/null && needs_install+=("$esde_sys → $emu (standalone)")
        fi
    elif [[ -n "$core" ]]; then
        # MAME-family cores take the rompath-bearing launch form; all other
        # libretro cores take the plain -L <core> %ROM% form.
        if [[ -n "${MAME_FAMILY[$esde_sys]:-}" ]]; then
            launch_cmd="core: $core   →   RetroArch -L ${core}_libretro.so \"%BASENAME% -rompath %GAMEDIRRAW%;%ROMPATH%/$esde_sys;%ROMPATH%/bios\""
        else
            launch_cmd="core: $core   →   RetroArch -L ${core}_libretro.so %ROM%"
        fi
        if is_core_installed "$core"; then
            echo -e "     Launches: RetroArch / $core ${GREEN}(installed)${NC}"
        else
            echo -e "     Launches: RetroArch / $core ${YELLOW}(NOT installed — would prompt)${NC}"
            declare -p needs_install &>/dev/null && needs_install+=("$esde_sys → $core (libretro core)")
        fi
    else
        launch_cmd="${YELLOW}none — no emulator/core mapping${NC}"
        echo -e "     Launches: ${YELLOW}⚠ no emulator/core mapping for '$esde_sys'${NC}"
        declare -p unknown_systems &>/dev/null && \
            unknown_systems+=("$rb_sys$([ "$rb_sys" != "$esde_sys" ] && echo " (→ $esde_sys)")")
    fi
    echo -e "     Command:  $launch_cmd"
    # Folder aliases that route into this same canonical system — one per
    # line, so each alias is unambiguously tied to the launch command above.
    if [[ -n "${SYS_ALIASES[$esde_sys]:-}" ]]; then
        echo "     Folder aliases that route here (share the command above):"
        local _a _mark
        for _a in ${SYS_ALIASES[$esde_sys]}; do
            _mark=""
            [[ "$_a" == "$rb_sys" ]] && _mark="  ${CYAN}← this source folder${NC}"
            echo -e "        - ${_a}/$_mark"
        done
    fi
}

IMPORT_SYSTEMS=0; IMPORT_MEDIA=0; IMPORT_ROMS=0

# Non-game folders to skip in the system loop (used by both dry-run + real import)
declare -A CONV_SKIP=( [media]=1 [bios]=1 [emulators]=1 [saves]=1
    [screenshots]=1 [cheats]=1 [records]=1 [sounds]=1 [decorations]=1
    [library]=1 [system]=1 [music]=1 )

# Emulator SUPPORT folders that may sit INSIDE a system's ROM dir but are not
# games (In Progress #1). When a non-flat source ships these as top-level
# subdirs they must not be copied into ROMs/<system>/ as if each were a game
# folder. These names are MAME/standalone-emulator support dirs; no real
# romset is named after any of them, so skipping them is safe for every
# system. Game folders proper (CHD romsets, multi-disc sets) are unaffected.
declare -A SUPPORT_SKIP=(
    [samples]=1 [artwork]=1 [cfg]=1 [nvram]=1 [cheat]=1
    [hash]=1 [hi]=1 [inp]=1 [sta]=1 [diff]=1 [comments]=1 [folders]=1
    [ctrlr]=1 [ini]=1 [crosshair]=1 [plugins]=1 [language]=1 [fonts]=1
    [software]=1 [ui]=1 [bgfx]=1 [shader]=1 [glsl]=1 [hlsl]=1
    [memcards]=1 [memcard]=1 [savestates]=1 [savestate]=1 [states]=1
    [patches]=1 [textures]=1 [overlays]=1 )
# Note: 'pgm' is deliberately NOT in this list — it is a real arcade romset.
# Note: 'snap' was removed — although MAME uses snap/ for snapshots, 'snap'
# is also a MEDIA_MAP key ([snap]=screenshots) for ES/Skraper scrape sets,
# and skipping it here would drop a legitimate screenshots media folder.

# Yield system directories for a source path, one per line. A "collection"
# (RetroBat install or ROM pack) has a roms/ subfolder containing system
# subdirs. A "single-system folder" has no roms/ — the folder itself IS the
# system dir, named after the system (e.g. a bare dreamcast/ folder). Both
# the dry-run reporter and the real import loop go through this so all three
# documented input shapes behave identically.
enumerate_system_dirs() {
    local p="$1" d
    # Nested-single-system case: $p is already <source>/roms with flat files
    # inside. Emit $p itself (not its subdirectories) — the per-system loop
    # will then derive the system name via NESTED_SYSTEM_OF below.
    if [[ -n "${NESTED_SYSTEM_OF[$p]:-}" ]]; then
        printf '%s\n' "$p"
        return 0
    fi
    if [[ -d "$p/roms" ]]; then
        for d in "$p/roms"/*/; do
            [[ -d "$d" ]] && printf '%s\n' "$d"
        done
    else
        printf '%s\n' "$p"
    fi
}

# ── Unrecognized-system picker (In Progress #9) ───────────────────────────
# A romset folder whose name is neither an ES-DE system nor a SYS_MAP alias
# has no emulator/core mapping — it would import as bare ROMs with no launch
# command. resolve_system_or_ask() resolves the folder name to a canonical
# ES-DE system; if it cannot, it shows a whiptail menu offering three paths:
#   1. pick a known ES-DE system to import the folder as,
#   2. skip the folder entirely,
#   3. import as-is (ROMs land in ROMs/<foldername>/ with NO launch command).
# The chosen system is remembered for the rest of the run via PICKER_CHOICE
# so the same folder name is not asked twice. In -test/DRY_RUN mode no menu
# is shown (the dry-run report already flags unknowns); the function just
# echoes the unresolved name so the report stays accurate.
declare -A PICKER_CHOICE=()        # rb_sys -> resolved esde_sys (or "__SKIP__")
# Is a name a system the importer can actually route (has emu OR core)?
_is_known_system() {
    local s="$1"
    [[ -n "${SYS_TO_EMU[$s]:-}" || -n "${SYS_TO_CORE[$s]:-}" ]]
}
resolve_system_or_ask() {
    # $1 = RB_SYS (source folder name). Echoes the resolved system name, or
    # the literal __SKIP__ if the user chose to skip this folder.
    local rb="$1" mapped
    mapped="${SYS_MAP[$rb]:-$rb}"
    # Port engines route to the generic 'ports' system, which has no SYS_TO_EMU/
    # SYS_TO_CORE entry (it launches via bash %ROM%). Treat them as routable so
    # they are not flagged unknown. Their data is placed in Emulators/<Port>/
    # by the import loop (see PORT_DATA_DIR).
    if [[ "$mapped" == "ports" && -n "${PORT_ENGINE_FOR[$rb]:-}" ]]; then
        printf 'ports\n'; return 0
    fi
    # Already routable (directly or via SYS_MAP)? Done.
    if _is_known_system "$mapped"; then printf '%s\n' "$mapped"; return 0; fi
    # Remembered from earlier in this run?
    if [[ -n "${PICKER_CHOICE[$rb]:-}" ]]; then
        printf '%s\n' "${PICKER_CHOICE[$rb]}"; return 0
    fi
    # Dry-run: never prompt — echo the name unresolved so the report flags it.
    if $DRY_RUN; then printf '%s\n' "$mapped"; return 0; fi
    # Build the sorted list of routable ES-DE systems for the menu.
    local -a known=()
    local k
    for k in "${!SYS_TO_CORE[@]}" "${!SYS_TO_EMU[@]}"; do known+=("$k"); done
    # de-dup + sort
    local -a sys_sorted=()
    while IFS= read -r k; do [[ -n "$k" ]] && sys_sorted+=("$k"); done \
        < <(printf '%s\n' "${known[@]}" | sort -u)
    # Menu: special actions first, then every known system.
    local -a menu=( "__SKIP__"   "Skip this folder — do not import it"
                    "__ASIS__"   "Copy files into ROMs/$rb/ (won't appear in ES-DE yet)" )
    for k in "${sys_sorted[@]}"; do menu+=( "$k" "Import '$rb' as the $k system" ); done
    local choice
    choice=$(wt_menu "Unrecognized system: '$rb'" \
"The folder '$rb' is not a known ES-DE system and has no SYS_MAP alias, so
it has no emulator/core mapping.

Choose how to import it:
 • pick a system below to import '$rb' as that system, or
 • Skip it, or
 • Copy as-is (files land in ROMs/$rb/, but ES-DE won't show this system
   until you add an es_systems.xml entry AND a SYS_MAP/emulator mapping)." \
        "${menu[@]}") || choice="__SKIP__"
    [[ -z "$choice" ]] && choice="__SKIP__"
    case "$choice" in
        __ASIS__) choice="$rb" ;;   # import under its own name, unmapped
    esac
    PICKER_CHOICE[$rb]="$choice"
    printf '%s\n' "$choice"
}


# ── Verbose dry-run compatibility helpers ──────────────────────────────────
# These helpers make -test -v / --audit useful for source-folder validation.
# They do not mutate the bundle or the source.
_count_files_in() {
    local d="$1"
    [[ -d "$d" ]] || { echo 0; return; }
    find "$d" -type f 2>/dev/null | wc -l | tr -d ' '
}

_count_top_files_in() {
    local d="$1"
    [[ -d "$d" ]] || { echo 0; return; }
    find "$d" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' '
}

_ext_summary_for() {
    local d="$1" out
    [[ -d "$d" ]] || { echo "none"; return; }
    out=$(find "$d" -maxdepth 1 -type f \
        ! -name 'gamelist*' ! -name '*.txt' ! -name '*.xml' ! -name '_*' \
        -printf '%f\n' 2>/dev/null \
        | awk '
            /\./ {
                n=split($0,a,".")
                e=tolower(a[n])
                c[e]++
            }
            END {
                for (e in c) print c[e], e
            }' \
        | sort -rn \
        | head -12 \
        | awk '{ printf "%s:%s ", $2, $1 }')
    [[ -n "$out" ]] && echo "${out% }" || echo "none"
}

_resolved_target_rom_rel() {
    local rb="$1" esde="$2"
    local sub="${MSU_NESTED_FOLDER[$rb]:-}"
    local parent="${MSU_ROM_PARENT[$rb]:-$esde}"
    if [[ -n "$sub" ]]; then
        echo "ROMs/$parent/$sub"
    else
        echo "ROMs/$esde"
    fi
}

_resolved_target_media_rel() {
    local rb="$1" esde="$2" type="${3:-<type>}"
    local sub="${MSU_NESTED_FOLDER[$rb]:-}"
    if [[ -n "$sub" && -z "${MSU_PATH_IS_SYSTEM_ROOT[$rb]:-}" ]]; then
        echo "downloaded_media/$esde/$type/$sub"
    else
        echo "downloaded_media/$esde/$type"
    fi
}

_resolved_target_gamelist_rel() {
    local esde="$1"
    echo "ES-DE/gamelists/$esde/gamelist.xml"
}

_verbose_source_scaffold_audit() {
    local path="$1"
    echo -e "${BOLD}── Source folder audit ──${NC}"

    local shown_any=0
    local d n
    for d in roms bios downloaded_media gamelists emulationstation media images videos manuals; do
        if [[ -d "$path/$d" ]]; then
            n=$(_count_files_in "$path/$d")
            echo "  present: $d/ ($n file(s))"
            shown_any=1
        fi
    done
    (( shown_any == 0 )) && echo "  no common collection folders found at source root"

    if [[ -d "$path/downloaded_media" ]]; then
        warn "Root downloaded_media/ detected. The importer mainly reads media under each system folder, for example roms/<system>/media/ or roms/<system>/images/."
    fi
    if [[ -d "$path/gamelists" ]]; then
        warn "Root gamelists/ detected. The importer reads gamelist.xml inside each source system folder, not global gamelists/<system>/gamelist.xml."
    fi
    echo ""
}

_verbose_system_folder_audit() {
    local sys_dir="$1" rb="$2" esde="$3" rom_count="$4" subdir_count="$5" media_note="$6"
    local target_rom target_media target_gl ext_summary top_files all_files

    target_rom=$(_resolved_target_rom_rel "$rb" "$esde")
    target_media=$(_resolved_target_media_rel "$rb" "$esde")
    target_gl=$(_resolved_target_gamelist_rel "$esde")
    ext_summary=$(_ext_summary_for "$sys_dir")
    top_files=$(_count_top_files_in "$sys_dir")
    all_files=$(_count_files_in "$sys_dir")

    echo "     Target ROMs:      $target_rom"
    echo "     Target media:     $target_media"
    echo "     Target gamelist:  $target_gl"
    echo "     Source totals:    $top_files top-level file(s), $all_files total file(s)"
    echo "     Extensions:       $ext_summary"
    _bios_sidecars_for_system_folder "$sys_dir"

    if (( rom_count == 0 && subdir_count == 0 )); then
        warn "$rb has no top-level ROM files and no game subfolders."
    elif (( rom_count == 0 && subdir_count > 0 )); then
        echo "     Folder games:     $subdir_count subfolder(s) would be copied as folder-style games"
    fi

    if [[ "$media_note" == "none detected" ]]; then
        echo "     Media detail:     none detected in this system folder"
    fi

    local t mapped count target
    if [[ -d "$sys_dir/media" ]]; then
        while IFS= read -r t; do
            [[ -z "$t" ]] && continue
            [[ ! -d "$sys_dir/media/$t" ]] && continue
            mapped="${MEDIA_MAP[$t]:-}"
            if [[ -n "$mapped" ]]; then
                count=$(_count_files_in "$sys_dir/media/$t")
                target=$(_resolved_target_media_rel "$rb" "$esde" "$mapped")
                echo "     Media map:        media/$t/ → $target/ ($count file(s))"
            elif [[ -n "${MEDIA_SKIP[$t]:-}" ]]; then
                count=$(_count_files_in "$sys_dir/media/$t")
                echo "     Media skip:       media/$t/ ($count file(s), no ES-DE media slot)"
            fi
        done < <(find "$sys_dir/media" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
    fi

    for t in images videos manuals; do
        if [[ -d "$sys_dir/$t" ]]; then
            count=$(_count_files_in "$sys_dir/$t")
            case "$t" in
                images) mapped="screenshots" ;;
                videos) mapped="videos" ;;
                manuals) mapped="manuals" ;;
            esac
            target=$(_resolved_target_media_rel "$rb" "$esde" "$mapped")
            echo "     Media map:        $t/ → $target/ ($count file(s))"
        fi
    done

    local skipped=0 weird=0 child base
    while IFS= read -r child; do
        base="$(basename "$child")"
        case "$base" in
            media|images|videos|manuals|system) skipped=$((skipped + 1)); continue ;;
        esac
        [[ -n "${MEDIA_MAP[$base]:-}" || -n "${MEDIA_SKIP[$base]:-}" ]] && { skipped=$((skipped + 1)); continue; }
        weird=$((weird + 1))
    done < <(find "$sys_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

    (( weird > 0 )) && echo "     Extra folders:    $weird folder(s) treated as folder-style ROM/game content"
    (( skipped > 0 )) && echo "     Support folders:  $skipped media/support folder(s) excluded from ROM copy"
}

_verbose_orphan_metadata_audit() {
    local path="$1"
    local -A seen=()
    local sys_dir rb esde root d key found_any=0

    while IFS= read -r sys_dir; do
        [[ -d "$sys_dir" ]] || continue
        if [[ -n "${NESTED_SYSTEM_OF[$sys_dir]:-}" ]]; then
            rb="${NESTED_SYSTEM_OF[$sys_dir]}"
        else
            rb="$(basename "$sys_dir")"
        fi
        [[ -n "${CONV_SKIP[$rb]:-}" ]] && continue
        esde="${SYS_MAP[$rb]:-$rb}"
        seen["$esde"]=1
        seen["$rb"]=1
    done < <(enumerate_system_dirs "$path")

    for root in "$path/downloaded_media" "$path/emulationstation/downloaded_media" "$path/gamelists" "$path/emulationstation/gamelists"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r d; do
            [[ -d "$d" ]] || continue
            key="$(basename "$d")"
            [[ -n "${CONV_SKIP[$key]:-}" ]] && continue
            if [[ -z "${seen[$key]:-}" ]]; then
                (( found_any == 0 )) && echo -e "${BOLD}── Orphan metadata audit ──${NC}"
                warn "$(basename "$root")/$key exists, but no matching source ROM system folder was detected"
                found_any=1
            fi
        done < <(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    done

    (( found_any == 1 )) && echo ""
}


# ── Dry-run reporter ──────────────────────────────────────────────────────
# Scans one source and reports what WOULD be imported. Reuses SYS_MAP /
# MEDIA_MAP / SYS_TO_EMU / SYS_TO_CORE / FLAT_ROM_SYSTEMS / CONV_SKIP and the
# is_*_installed helpers defined above. Copies / moves / writes NOTHING.
dry_run_report() {
    local path="$1"
    echo ""
    echo -e "${BOLD}${CYAN}═══ TEST — $path ═══${NC}"
    echo ""

    if [[ -n "${NESTED_SYSTEM_OF[$path]:-}" ]]; then
        info "Source type: single-system folder ('${NESTED_SYSTEM_OF[$path]}', nested in roms/)"
    elif [[ -d "$path/roms" ]]; then
        info "Source type: collection (roms/ with system subfolders)"
    else
        info "Source type: single-system folder ('$(basename "$path")')"
    fi

    if [[ -d "$path/bios" ]]; then
        local bcount acount
        bcount=$(find "$path/bios" -type f 2>/dev/null | wc -l)
        acount=$(find "$path/bios" -type f \( -iname '*.zip' -o -iname '*.7z' -o -iname '*.rar' \) 2>/dev/null | wc -l)
        info "BIOS: $bcount file(s), $acount archive(s) → ROMs/bios/ (copy/extract, existing files skipped)"
    else
        info "BIOS: no bios/ folder in this source"
    fi
    echo ""

    $DRY_VERBOSE && _verbose_source_scaffold_audit "$path"

    local total_sys=0 total_roms=0 total_media=0
    local -a unknown_systems=() needs_install=() name_remaps=()

    while IFS= read -r SYS_DIR; do
        [[ -d "$SYS_DIR" ]] || continue
        local RB_SYS ESDE_SYS
        # Honor NESTED_SYSTEM_OF for nested-single-system sources
        # (<source>/roms/<files>): the system name is the source's parent
        # folder, not "roms".
        if [[ -n "${NESTED_SYSTEM_OF[$SYS_DIR]:-}" ]]; then
            RB_SYS="${NESTED_SYSTEM_OF[$SYS_DIR]}"
        else
            RB_SYS=$(basename "$SYS_DIR")
        fi
        [[ -n "${CONV_SKIP[$RB_SYS]:-}" ]] && continue
        if [[ "$RB_SYS" == "psn" || "$RB_SYS" == "ps3psn" ]]; then
            total_sys=$((total_sys + 1))
            preview_psn_import "$SYS_DIR"
            echo ""
            continue
        fi
        ESDE_SYS="${SYS_MAP[$RB_SYS]:-$RB_SYS}"
        local MSU_SUBDIR="${MSU_NESTED_FOLDER[$RB_SYS]:-}"
        local MSU_PARENT="${MSU_ROM_PARENT[$RB_SYS]:-$ESDE_SYS}"
        total_sys=$((total_sys + 1))
        if [[ -n "$MSU_SUBDIR" ]]; then
            if [[ "$MSU_PARENT" != "$ESDE_SYS" ]]; then
                name_remaps+=("$RB_SYS → $ESDE_SYS (ROMs/$MSU_PARENT/$MSU_SUBDIR)")
            else
                name_remaps+=("$RB_SYS → $ESDE_SYS/$MSU_SUBDIR")
            fi
        elif [[ "$RB_SYS" != "$ESDE_SYS" ]]; then
            name_remaps+=("$RB_SYS → $ESDE_SYS")
        fi

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
        if [[ -n "$MSU_SUBDIR" ]]; then
            arrow=" ${YELLOW}→ $ESDE_SYS/$MSU_SUBDIR${NC}"
        elif [[ "$RB_SYS" != "$ESDE_SYS" ]]; then
            arrow=" ${YELLOW}→ $ESDE_SYS${NC}"
        fi
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

        $DRY_VERBOSE && _verbose_system_folder_audit "$SYS_DIR" "$RB_SYS" "$ESDE_SYS" "$rom_count" "$subdir_count" "$media_note"

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
                echo "     PinMAME:  $vpmn ROM zip(s) in VPinMAME/ → would import to ROMs/vpinball/pinmame/roms/"
                vproot=$(dirname "$vpm")
                if [[ -d "$vproot/Music" ]]; then
                    local mn
                    mn=$(find "$vproot/Music" -type f 2>/dev/null | wc -l)
                    echo "     Music:    $mn file(s) in Music/ → would import to ROMs/vpinball/music/"
                fi
                local vpscr="$vproot/Scripts"
                [[ ! -d "$vpscr" ]] && vpscr="$vpm/Scripts"
                if [[ -d "$vpscr" ]]; then
                    local sn bsc xn sk _c
                    sn=$(find "$vpscr" -maxdepth 1 -type f -iname '*.vbs' 2>/dev/null | wc -l)
                    bsc=""
                    for _c in "$BASE/Emulators/VPinball/scripts" "$BASE/Emulators/VPinball/Scripts"; do
                        if [[ -d "$_c" ]]; then bsc="$_c"; break; fi
                    done
                    if [[ -n "$bsc" ]]; then
                        sk=$(comm -12 \
                            <(find "$vpscr" -maxdepth 1 -type f -iname '*.vbs' -printf '%f\n' 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u) \
                            <(find "$bsc"   -maxdepth 1 -type f -iname '*.vbs' -printf '%f\n' 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u) \
                            | wc -l)
                        xn=$((sn - sk))
                        echo "     Scripts:  $xn extra .vbs → ROMs/vpinball/ (skipping $sk bundled with the emulator)"
                    else
                        echo "     Scripts:  $sn .vbs library file(s) → would import to ROMs/vpinball/ (emulator scripts dir not found)"
                    fi
                    echo "     Symlinks: .pinmame → ROMs/vpinball/pinmame, Emulators/Music → ROMs/vpinball/music when safe"
                fi
            else
                echo -e "     PinMAME:  ${YELLOW}no VPinMAME folder — solid-state/DMD tables won't run without ROMs${NC}"
            fi
        fi

        # ── Emulator / core resolution + launch-command audit ──
        # Each system prints, on its own lines: the resolved emulator/core,
        # the actual launch-command pattern ES-DE will run, and — if the
        # source folder name is an alias — every other folder alias that
        # routes into the same canonical system (they all share this launch
        # command). This makes a wrong rompath or a folder-vs-flat mismatch
        # visible at a glance (Audit F-launch).
        print_launch_audit "$RB_SYS" "$ESDE_SYS"
        echo ""
    done < <(enumerate_system_dirs "$path")

    $DRY_VERBOSE && _verbose_orphan_metadata_audit "$path"

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
        warn "Unrecognized system(s) — no emulator/core mapping:"
        local u; for u in "${unknown_systems[@]}"; do echo "     - $u"; done
        echo "     During a real import you'll be prompted (per folder) to pick a"
        echo "     system, skip it, or import it as-is. To make the mapping"
        echo "     permanent instead, add it to SYS_MAP / SYS_TO_EMU / SYS_TO_CORE."
    fi
    echo ""
    return 0
}

# ── PSN / PS3 (rpcs3) import helpers ─────────────────────────────────────────
# Resolve a source RetroBat tree's RPCS3 dev_hdd0 (or rpcs3 config root),
# probing RetroBat (system/configs/rpcs3), portable (emulators/rpcs3) and bare
# dev_hdd0 layouts at the system dir and up to two levels above it. Echoes the
# matched path; returns non-zero if none found.
find_rpcs3_src_hdd() {
    local sd="$1" parent gparent _p
    parent="$(dirname "$sd")"
    gparent="$(dirname "$parent")"
    for _p in \
        "$sd/system/configs/rpcs3/dev_hdd0"       "$sd/system/configs/rpcs3" \
        "$sd/emulators/rpcs3/dev_hdd0"            "$sd/emulators/rpcs3" \
        "$sd/dev_hdd0" \
        "$parent/system/configs/rpcs3/dev_hdd0"   "$parent/system/configs/rpcs3" \
        "$parent/emulators/rpcs3/dev_hdd0"        "$parent/emulators/rpcs3" \
        "$parent/dev_hdd0" \
        "$gparent/system/configs/rpcs3/dev_hdd0"  "$gparent/system/configs/rpcs3" \
        "$gparent/emulators/rpcs3/dev_hdd0"       "$gparent/emulators/rpcs3"; do
        [[ -d "$_p" ]] && { printf '%s\n' "$_p"; return 0; }
    done
    return 1
}

# Merge a source RPCS3 dev_hdd0 into the bundle's RPCS3 config home, no-clobber
# (existing saves/installs/RAP licenses always win). Honors RETROBAT_MOVE. No-op
# if no source hdd is found.
# Fold a directory tree into a destination, honouring the user's cut/copy choice
# (RETROBAT_MOVE) — the same contract the generic ROM/media branches use, so
# every system behaves identically. No-clobber: existing files always win, only
# missing ones are added. Never a top-level mv (which can't merge into an
# existing dir). OS/debug cruft that rides along in dumped Windows trees
# (Thumbs.db, .DS_Store, crash dumps) is stripped from the destination.
#   cut  -> per-file move, source ends empty (instant rename on one filesystem)
#   copy -> bulk copy, source left intact
_merge_tree() {
    local src="$1" dest="$2"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dest"
    if [[ "${RETROBAT_MOVE:-no}" == "yes" ]]; then
        ( cd "$src" && find . -mindepth 1 -type f -print0 2>/dev/null \
            | while IFS= read -r -d '' f; do
                  mkdir -p "$dest/$(dirname "$f")" 2>/dev/null || true
                  mv -n "$f" "$dest/$f" 2>/dev/null || true
              done ) || true
        find "$src" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    else
        cp -rn "$src/." "$dest/" 2>/dev/null || true
    fi
    find "$dest" -type f \( -iname 'Thumbs.db' -o -iname '.DS_Store' \
         -o -iname 'desktop.ini' -o -iname '*.dmp' \) -delete 2>/dev/null || true
    return 0
}

relocate_rpcs3_hdd() {
    local sd="$1" src dest
    src="$(find_rpcs3_src_hdd "$sd")" || return 0
    [[ -n "$src" ]] || return 0
    dest="$BASE/.config/rpcs3"
    [[ "$(basename "$src")" == "dev_hdd0" ]] && dest="$dest/dev_hdd0"
    mkdir -p "$dest"
    # Fold the source dev_hdd0 into the bundle's, honouring the user's cut/copy
    # choice (never a top-level mv: the bundle usually already has a dev_hdd0,
    # and `mv -n <dir> dest/` refuses to merge into an existing dir — it skips
    # the whole subtree, silently dropping not-yet-present games + RAP licenses).
    echo -n "      RPCS3 dev_hdd0 → .config/rpcs3 [merging..."
    _merge_tree "$src" "$dest"
    echo -e " ${GREEN}done${NC}"
}

# Read a PS3 game folder's PARAM.SFO TITLE (UTF-8). Echoes nothing on failure.
psn_title() {
    local sfo="${1%/}/PARAM.SFO"
    [[ -f "$sfo" ]] || return 0
    python3 - "$sfo" 2>/dev/null <<'PYSFO'
import sys,struct
try:
    d=open(sys.argv[1],'rb').read()
    assert d[:4]==b'\x00PSF'
    key_off,data_off,num=struct.unpack('<III',d[8:20])
    for i in range(num):
        e=0x14+i*16
        ko,fmt,ln,mx,do=struct.unpack('<HHIII',d[e:e+16])
        k=d[key_off+ko:d.index(b'\x00',key_off+ko)].decode('ascii','ignore')
        if k=='TITLE':
            print(d[data_off+do:data_off+do+ln].split(b'\x00')[0].decode('utf-8','ignore')); break
except Exception:
    pass
PYSFO
}

# Sanitise a title into a safe launcher filename stem.
psn_safe_name() {
    printf '%s' "$1" | tr -d '/\\:*?"<>|' | sed 's/  */ /g; s/ *$//'
}

# Extract a PS3 title ID from a RetroBat .lnk. The file is binary, but the TID
# sits in it as %RPCS3_GAMEID%:<TID> (and again in the icon path); stripping NULs
# collapses UTF-16LE to ASCII so one grep catches either encoding. Deterministic.
psn_tid_from_lnk() {
    tr -d '\000' < "$1" 2>/dev/null \
        | grep -aoiE 'NP[A-Z]{2}[0-9]{5}|B[LC][A-Z]S[0-9]{5}' | head -1
}

# Full ps3psn import: merge the source RPCS3 dev_hdd0, then turn each RetroBat
# .lnk into a stem-matched .m3u launcher and import the stem-named media so the
# theme's cover art binds. .m3u stem == media stem == gamelist <name>.
import_ps3psn() {
    local sd="$1"
    local hdd="$BASE/.config/rpcs3/dev_hdd0/game"
    local dest="$ROMS/ps3psn"
    local mbase="$MEDIA_BASE/ps3psn"
    relocate_rpcs3_hdd "$sd"
    if [[ ! -d "$hdd" ]]; then
        echo -e "   ${YELLOW}PSN: no dev_hdd0 after merge ($hdd) — nothing to emit.${NC}"
        return 0
    fi
    mkdir -p "$dest"
    local n=0 miss=0 f stem tid
    while IFS= read -r -d '' f; do
        stem="$(basename "$f")"; stem="${stem%.[Ll][Nn][Kk]}"
        tid="$(psn_tid_from_lnk "$f")"; tid="${tid^^}"
        if [[ -z "$tid" ]]; then
            echo -e "   ${YELLOW}⚠ no TID in '$stem.lnk' — skipped${NC}"; miss=$((miss + 1)); continue
        fi
        if [[ ! -f "$hdd/$tid/USRDIR/EBOOT.BIN" ]]; then
            echo -e "   ${YELLOW}⚠ '$stem' → $tid not installed in dev_hdd0 — skipped${NC}"; miss=$((miss + 1)); continue
        fi
        printf 'dev_hdd0/game/%s/USRDIR/EBOOT.BIN\n' "$tid" > "$dest/$stem.m3u"
        n=$((n + 1))
    done < <(find "$sd" -maxdepth 1 -type f -iname '*.lnk' -print0 2>/dev/null)
    echo "   PSN: generated $n .m3u launcher(s) in ROMs/ps3psn$([ "$miss" -gt 0 ] && echo " ($miss skipped)")."

    # Media: route each stem-named source media folder into downloaded_media so
    # cover art (2dboxes→covers) binds to the .m3u by filename stem.
    local mdir key dstt mc=0
    for mdir in "$sd"/*/; do
        [[ -d "$mdir" ]] || continue
        key="$(basename "$mdir")"; key="${key,,}"
        dstt="${MEDIA_MAP[$key]:-}"; [[ -z "$dstt" ]] && continue
        mkdir -p "$mbase/$dstt"
        if [[ "${RETROBAT_MOVE:-no}" == "yes" ]]; then
            find "$mdir" -mindepth 1 -maxdepth 1 -exec mv -n {} "$mbase/$dstt/" \; 2>/dev/null || true
        else
            cp -rn "$mdir/." "$mbase/$dstt/" 2>/dev/null || true
        fi
        mc=$((mc + 1))
    done
    [[ "$mc" -gt 0 ]] && echo "   PSN: imported $mc media folder(s) → downloaded_media/ps3psn."

    # Gamelist: rewrite .lnk → .m3u in <path> so metadata binds. Written only when
    # no target gamelist exists (never clobber an existing one).
    local gsrc="$sd/gamelist.xml" gdir="$ESDE_DATA/gamelists/ps3psn" gdst
    gdst="$gdir/gamelist.xml"
    if [[ -f "$gsrc" ]]; then
        mkdir -p "$gdir"
        if [[ -f "$gdst" ]]; then
            echo -e "   ${YELLOW}PSN: gamelist already present — left as-is (no clobber).${NC}"
        else
            sed -E 's#\.lnk</path>#.m3u</path>#g' "$gsrc" > "$gdst" 2>/dev/null || true
            echo "   PSN: gamelist imported (paths rewritten .lnk → .m3u)."
        fi
    fi

    # Reflect this branch's work in the final summary — the caller's early
    # `continue` skips the generic per-system counters.
    IMPORT_SYSTEMS=$((IMPORT_SYSTEMS + 1))
    IMPORT_MEDIA=$((IMPORT_MEDIA + mc))
    IMPORT_ROMS=$((IMPORT_ROMS + n))
}

# Dry-run preview of the ps3psn path: source hdd location, how each .lnk resolves
# to an installed TID, would-emit count, a short sample, and which media folders
# would bind — all without listing every game.
preview_psn_import() {
    local sd="$1"
    local hdd="$BASE/.config/rpcs3/dev_hdd0/game"
    local src_hdd src_game=""
    echo -e "  ${CYAN}ps3psn${NC}"
    if src_hdd="$(find_rpcs3_src_hdd "$sd" 2>/dev/null)" && [[ -n "$src_hdd" ]]; then
        [[ "$(basename "$src_hdd")" == "dev_hdd0" ]] && src_game="$src_hdd/game" || src_game="$src_hdd/dev_hdd0/game"
        echo -e "     Source hdd:   ${src_hdd#"$sd"/}  ${GREEN}(found — merges into .config/rpcs3, no-clobber)${NC}"
    else
        echo -e "     Source hdd:   ${YELLOW}none found — relies on existing bundle hdd${NC}"
    fi
    local total=0 ok=0 miss=0 shown=0 f stem tid found
    echo "     Sample (lnk → launcher):"
    while IFS= read -r -d '' f; do
        total=$((total + 1))
        stem="$(basename "$f")"; stem="${stem%.[Ll][Nn][Kk]}"
        tid="$(psn_tid_from_lnk "$f")"; tid="${tid^^}"
        found=no
        if [[ -n "$tid" ]] && { [[ -f "$hdd/$tid/USRDIR/EBOOT.BIN" ]] || { [[ -n "$src_game" ]] && [[ -f "$src_game/$tid/USRDIR/EBOOT.BIN" ]]; }; }; then
            found=yes; ok=$((ok + 1))
        else
            miss=$((miss + 1))
        fi
        if [[ $shown -lt 6 ]]; then
            if [[ "$found" == yes ]]; then
                echo "                   $stem  ($tid) → $stem.m3u"
            else
                echo -e "                   $stem  (${YELLOW}${tid:-no-TID} not installed${NC}) → skip"
            fi
            shown=$((shown + 1))
        fi
    done < <(find "$sd" -maxdepth 1 -type f -iname '*.lnk' -print0 2>/dev/null)
    [[ $total -gt 6 ]] && echo "                   … (+$((total - 6)) more .lnk)"
    echo "     Launchers:    $ok of $total .lnk resolve to an installed game$([ "$miss" -gt 0 ] && echo "; $miss unresolved")"
    local mlist="" mdir key klc
    for mdir in "$sd"/*/; do
        [[ -d "$mdir" ]] || continue
        key="$(basename "$mdir")"; klc="${key,,}"
        [[ -n "${MEDIA_MAP[$klc]:-}" ]] && mlist+="$key→${MEDIA_MAP[$klc]} "
    done
    [[ -n "$mlist" ]] && echo "     Media:        ${mlist}(stem-matched → binds to .m3u)"
}

if $DRY_RUN; then
    for RETROBAT_PATH in "${RETROBAT_PATHS[@]}"; do
        dry_run_report "$RETROBAT_PATH"
    done
    # BIOS verification is read-only — safe to run in dry-run for a real report.
    echo -e "${CYAN}── BIOS status (read-only check) ──${NC}"
    verify_all || true
    echo ""
    ok "Test complete — nothing was copied, moved, or modified."
    echo "   Re-run without -test to perform the actual import."
    exit 0
fi

# Scan RPCS3's dev_hdd0 for installed PS3/PSN games and emit one .m3u launcher
# per game into ROMs/ps3psn. Linux replacement for RetroBat's Windows .lnk
# shortcuts: ps3-launch.sh reads the .m3u path and resolves EBOOT.BIN under the
# bundle's dev_hdd0. Honors DRY_RUN (reports only, writes nothing).
scan_ps3_hdd() {
    local hdd="$BASE/.config/rpcs3/dev_hdd0/game"
    local dest="$ROMS/ps3psn"
    if [[ ! -d "$hdd" ]]; then
        echo -e "   ${YELLOW}PSN: no RPCS3 dev_hdd0 at $hdd — install/migrate PS3 games into RPCS3 first.${NC}"
        return 0
    fi
    local n=0 gdir tid eboot sfo title safe
    for gdir in "$hdd"/*/; do
        [[ -d "$gdir" ]] || continue
        tid="$(basename "$gdir")"
        # ps3psn is digital-only: emit only for PSN title IDs (NP*). Disc IDs
        # (BL*/BC*/BLJ*) belong to the ps3 system, and *-DATA / *GAMEDATA /
        # install-staging dirs carry no bootable EBOOT of their own.
        [[ "$tid" == NP* ]] || continue
        eboot="${gdir}USRDIR/EBOOT.BIN"
        [[ -f "$eboot" ]] || continue
        title="$(psn_title "$gdir")"
        [[ -z "$title" ]] && title="$tid"
        safe="$(psn_safe_name "$title")"
        [[ -z "$safe" ]] && safe="$tid"
        if [[ "$DRY_RUN" == true ]]; then
            echo "   PSN would add: $safe  ($tid)"
        else
            mkdir -p "$dest"
            printf 'dev_hdd0/game/%s/USRDIR/EBOOT.BIN\n' "$tid" > "$dest/$safe.m3u"
        fi
        n=$((n + 1))
    done
    if [[ "$DRY_RUN" == true ]]; then
        echo "   PSN: $n installed game(s) found in dev_hdd0 (dry-run, nothing written)."
    else
        echo "   PSN: generated $n .m3u launcher(s) in ROMs/ps3psn."
    fi
}

for RETROBAT_PATH in "${RETROBAT_PATHS[@]}"; do
    info "Importing from: $RETROBAT_PATH"
    if [[ -d "$RETROBAT_PATH/bios" ]]; then
        echo -n "   BIOS files → ROMs/bios/ [copying/extracting, no overwrite...]"
        _import_bios_tree "$RETROBAT_PATH/bios"
    fi

    while IFS= read -r SYS_DIR; do
        [[ -d "$SYS_DIR" ]] || continue
        # Same NESTED_SYSTEM_OF override as the dry-run loop above.
        if [[ -n "${NESTED_SYSTEM_OF[$SYS_DIR]:-}" ]]; then
            RB_SYS="${NESTED_SYSTEM_OF[$SYS_DIR]}"
        else
            RB_SYS=$(basename "$SYS_DIR")
        fi
        [[ -n "${CONV_SKIP[$RB_SYS]:-}" ]] && continue
        # RetroBat's "psn" folder holds Windows .lnk shortcuts to PSN games
        # installed in RPCS3's dev_hdd0 — useless on Linux. Instead of copying
        # them, scan dev_hdd0 and emit .m3u launchers into ROMs/ps3psn.
        if [[ "$RB_SYS" == "psn" || "$RB_SYS" == "ps3psn" ]]; then
            # Digital/PSN folder: RetroBat ships .lnk shortcuts, not ROMs. Merge
            # the source RPCS3 dev_hdd0 into the bundle, then turn each .lnk into a
            # stem-matched .m3u launcher (stem = media name; TID read from the .lnk
            # body) and import the stem-named media so cover art binds.
            import_ps3psn "$SYS_DIR"
            continue
        fi
        # Resolve to a canonical ES-DE system. If the folder name is not a
        # known system or SYS_MAP alias, this pops a whiptail picker (skip /
        # import-as-is / choose a system) — In Progress #9.
        ESDE_SYS=$(resolve_system_or_ask "$RB_SYS")
        if [[ "$ESDE_SYS" == "__SKIP__" ]]; then
            echo -e "   ${YELLOW}$RB_SYS — skipped (user choice)${NC}"
            continue
        fi
        MSU_SUBDIR="${MSU_NESTED_FOLDER[$RB_SYS]:-}"
        MSU_PARENT="${MSU_ROM_PARENT[$RB_SYS]:-$ESDE_SYS}"
        ESDE_ROM_DIR="$ROMS/$MSU_PARENT"
        ESDE_MEDIA_DIR="$MEDIA_BASE/$ESDE_SYS"
        ESDE_GAMELIST_DIR="$ESDE_DATA/gamelists/$ESDE_SYS"
        ESDE_MEDIA_SUBDIR=""
        if [[ -n "$MSU_SUBDIR" ]]; then
            ESDE_ROM_DIR="$ESDE_ROM_DIR/$MSU_SUBDIR"
            ESDE_MEDIA_SUBDIR="$MSU_SUBDIR"
            [[ -n "${MSU_PATH_IS_SYSTEM_ROOT[$RB_SYS]:-}" ]] && ESDE_MEDIA_SUBDIR=""
        fi
        mkdir -p "$ESDE_ROM_DIR"
        DISPLAY_TARGET="$ESDE_SYS"
        if [[ -n "$MSU_SUBDIR" ]]; then
            if [[ "$MSU_PARENT" != "$ESDE_SYS" ]]; then
                DISPLAY_TARGET="$ESDE_SYS (ROMs/$MSU_PARENT/$MSU_SUBDIR)"
            else
                DISPLAY_TARGET="$ESDE_SYS/$MSU_SUBDIR"
            fi
        fi
        echo -e "   ${CYAN}$RB_SYS${NC}$([ "$RB_SYS" != "$DISPLAY_TARGET" ] && echo " → $DISPLAY_TARGET")"
        IMPORT_SYSTEMS=$((IMPORT_SYSTEMS + 1))
        # Per-system launch-command audit — same output as the -test report,
        # so during a real import each system and every folder alias is shown
        # on its own line with the exact command ES-DE will run (Step A).
        print_launch_audit "$RB_SYS" "$ESDE_SYS"
        # Reset the deferred-MAME-normalisation list for this system (the
        # non-flat branch repopulates it; resetting here guards against a
        # stale list carrying over from a previous system).
        _mame_pending=()
        # ── PS3: relocate the RPCS3 dev_hdd0 tree ───────────────────────
        # A RetroBat PS3 source ships RPCS3's virtual hard drive at
        #   <ps3>/system/configs/rpcs3/dev_hdd0/{game,home,...}
        # which holds installed PSN games, DLC, updates, trophies, savedata
        # and RAP licenses. The portable bundle runs RPCS3 via
        # rpcs3-portable.sh with XDG_CONFIG_HOME=$BASE/.config, so RPCS3
        # expects that tree at $BASE/.config/rpcs3/dev_hdd0/. Without this
        # step the system/ folder would either be skipped or wrongly copied
        # into ROMs/ps3/system/, and the user's installed games / saves /
        # licenses would be lost. Move (or copy) it to the right place and
        # drop the source system/ dir so the ROM-copy loop ignores it.
        # PS3: merge the source's RPCS3 dev_hdd0 into the bundle config home
        # (no-clobber — saves/installs/RAP licenses preserved). The helper probes
        # RetroBat (system/configs/rpcs3), portable (emulators/rpcs3) and bare
        # dev_hdd0 layouts at the system dir and up to two levels up. The source
        # system/ shell is left in place (the ROM-copy loop skips a top-level
        # 'system' dir); remove by hand after a cut-move.
        if [[ "$ESDE_SYS" == "ps3" || "$ESDE_SYS" == "ps3psn" ]]; then
            relocate_rpcs3_hdd "$SYS_DIR"
        fi
        MEDIA_DIR="$SYS_DIR/media"
        if [[ -d "$MEDIA_DIR" ]]; then
            mkdir -p "$ESDE_MEDIA_DIR"
            # Source-driven: iterate the folders that ACTUALLY exist in the
            # source media/ dir and route each by name. This catches every
            # scraper layout (RetroBat, Skraper, Batocera) and — crucially —
            # reports any folder it can't map instead of silently dropping it
            # (the ColeCovision media-loss bug: bezel/ mix/ screenshots/ were
            # skipped because the old map only knew RetroBat folder names).
            while IFS= read -r -d '' SRC; do
                RB_TYPE=$(basename "$SRC"); RB_KEY="${RB_TYPE,,}"
                if [[ -n "${MEDIA_SKIP[$RB_KEY]:-}" ]]; then
                    echo -e "      $(printf '%-14s' "$RB_TYPE") ${YELLOW}skipped${NC} (no ES-DE media type)"
                    continue
                fi
                ESDE_TYPE="${MEDIA_MAP[$RB_KEY]:-}"
                if [[ -z "$ESDE_TYPE" ]]; then
                    echo -e "      $(printf '%-14s' "$RB_TYPE") ${YELLOW}unmapped${NC} — not imported"
                    continue
                fi
                DST="$ESDE_MEDIA_DIR/$ESDE_TYPE"
                [[ -n "${ESDE_MEDIA_SUBDIR:-}" ]] && DST="$DST/$ESDE_MEDIA_SUBDIR"
                # thumbnails → 3dboxes: if the destination already has files
                # from a dedicated 3dboxes source (or a prior import), skip
                # the thumbnails merge to avoid mixing different-quality renders.
                if [[ "$RB_KEY" == "thumbnails" && "$ESDE_TYPE" == "3dboxes" ]] \
                   && [[ -d "$DST" ]] \
                   && [[ -n "$(find "$DST" -maxdepth 1 -type f 2>/dev/null | head -1)" ]]; then
                    echo -e "      $(printf '%-14s' "$RB_TYPE") → $(printf '%-14s' "$ESDE_TYPE") ${YELLOW}skipped — 3dboxes already populated${NC}"
                    continue
                fi
                mkdir -p "$DST"
                # Respect cut vs copy. The ROM branch already honours
                # $RETROBAT_MOVE; the media branch must too, or a "cut"
                # import moves ROMs but leaves a full copy of the media
                # behind at the source (observed: colecovision cut import).
                _mlabel="copying"
                [[ "$RETROBAT_MOVE" == "yes" ]] && _mlabel="moving"
                [[ "$ESDE_TYPE" == "videos" ]] \
                    && echo "      $(printf '%-14s' "$RB_TYPE") → videos [$_mlabel — large sets take time...]" \
                    || echo -n "      $(printf '%-14s' "$RB_TYPE") → $(printf '%-14s' "$ESDE_TYPE") [$_mlabel...]"
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    # Move files, then drop the now-empty source folder.
                    find "$SRC" -mindepth 1 -maxdepth 1 -exec mv -n {} "$DST/" \; 2>/dev/null || true
                    rmdir "$SRC" 2>/dev/null || true
                else
                    cp -rn "$SRC/." "$DST/" 2>/dev/null || true
                fi
                [[ "$ESDE_TYPE" == "videos" ]] \
                    && echo -e "      ${GREEN}✓${NC} videos done" \
                    || echo -e " ${GREEN}done${NC}"
                IMPORT_MEDIA=$((IMPORT_MEDIA + 1))
            done < <(find "$MEDIA_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
        else
            # Non-RetroBat layouts. Two shapes are common:
            #   (a) ES/Batocera-style with suffixes — images/<rom>-image.png,
            #       images/<rom>-thumb.png, videos/<rom>-Video.mp4
            #   (b) Simple flat with media subfolders directly in ROM dir
            es_detected=0
            [[ -d "$SYS_DIR/images" ]] && try_import_es_layout "$SYS_DIR/images" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" "$ESDE_MEDIA_SUBDIR" && es_detected=1
            [[ -d "$SYS_DIR/videos" ]] && try_import_es_layout "$SYS_DIR/videos" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" "$ESDE_MEDIA_SUBDIR" && es_detected=1
            [[ -d "$SYS_DIR/manuals" ]] && try_import_es_layout "$SYS_DIR/manuals" "$ESDE_MEDIA_DIR" "$RETROBAT_MOVE" "$ESDE_MEDIA_SUBDIR" && es_detected=1
            (( es_detected )) && IMPORT_MEDIA=$((IMPORT_MEDIA + 1))
            if (( ! es_detected )); then
            # Flat media: media-type folders sitting directly in the system
            # dir (no media/ wrapper). Source-driven, same as the media/
            # branch — route by folder name, report anything unmappable.
            while IFS= read -r -d '' SRC; do
                RB_TYPE=$(basename "$SRC"); RB_KEY="${RB_TYPE,,}"
                # images/videos/manuals already handled by try_import_es_layout
                # above; bios is not media.
                case "$RB_KEY" in images|videos|manuals|bios) continue ;; esac
                [[ -n "${MEDIA_SKIP[$RB_KEY]:-}" ]] && continue
                ESDE_TYPE="${MEDIA_MAP[$RB_KEY]:-}"
                [[ -z "$ESDE_TYPE" ]] && continue
                DST="$ESDE_MEDIA_DIR/$ESDE_TYPE"
                [[ -n "${ESDE_MEDIA_SUBDIR:-}" ]] && DST="$DST/$ESDE_MEDIA_SUBDIR"
                # thumbnails → 3dboxes skip (same rule as the RetroBat media/ branch)
                if [[ "$RB_KEY" == "thumbnails" && "$ESDE_TYPE" == "3dboxes" ]] \
                   && [[ -d "$DST" ]] \
                   && [[ -n "$(find "$DST" -maxdepth 1 -type f 2>/dev/null | head -1)" ]]; then
                    echo -e "      $(printf '%-14s' "$RB_TYPE") (flat) → $(printf '%-10s' "$ESDE_TYPE") ${YELLOW}skipped — 3dboxes already populated${NC}"
                    continue
                fi
                mkdir -p "$DST"
                _mlabel="copying"
                [[ "$RETROBAT_MOVE" == "yes" ]] && _mlabel="moving"
                [[ "$ESDE_TYPE" == "videos" ]] \
                    && echo "      $(printf '%-14s' "$RB_TYPE") (flat) → videos [$_mlabel — large sets take time...]" \
                    || echo -n "      $(printf '%-14s' "$RB_TYPE") (flat) → $(printf '%-10s' "$ESDE_TYPE") [$_mlabel...]"
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    find "$SRC" -mindepth 1 -maxdepth 1 -exec mv -n {} "$DST/" \; 2>/dev/null || true
                    rmdir "$SRC" 2>/dev/null || true
                else
                    cp -rn "$SRC/." "$DST/" 2>/dev/null || true
                fi
                [[ "$ESDE_TYPE" == "videos" ]] \
                    && echo -e "      ${GREEN}✓${NC} videos done" \
                    || echo -e " ${GREEN}done${NC}"
                IMPORT_MEDIA=$((IMPORT_MEDIA + 1))
            done < <(find "$SYS_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
            fi  # close: if (( ! es_detected ))
        fi
        GAMELIST_SRC="$SYS_DIR/gamelist.xml"
        if [[ -f "$GAMELIST_SRC" ]]; then
            # GLFIX: gamelist merger. <alternativeEmulator> is written as a
            # sibling of <gameList> (not inside it) to match ES-DE upstream.
            # See the Python-side comment for the compatibility decision.
            printf "      gamelist.xml → cleaning...\n"
            mkdir -p "$ESDE_GAMELIST_DIR"
            FLAT_LIST="${FLAT_ROM_SYSTEMS[*]}" python3 - "$GAMELIST_SRC" "$ESDE_GAMELIST_DIR/gamelist.xml" "$ESDE_SYS" "$ESDE_MEDIA_SUBDIR" 2>/dev/null << 'GLFIX' || warn "gamelist skipped"
import sys, re, os
src, dst, system = sys.argv[1], sys.argv[2], sys.argv[3]
rel_subdir = sys.argv[4].strip('/').strip() if len(sys.argv) > 4 else ''
FLAT_SYSTEMS = set(os.environ.get('FLAT_LIST', '').split())  # single source: bash FLAT_ROM_SYSTEMS
flatten = system in FLAT_SYSTEMS
tags = ['image','thumbnail','marquee','video','fanart','boxart','titleshot','cartridge','mix','wheel','screenshot','boxback','rotation','sortname','genreid','arcadesystemname','hash','crc32','md5','region','languages']
tag_re = re.compile(r'\s*<(?:' + '|'.join(tags) + r')>[^<]*</(?:' + '|'.join(tags) + r')>')
path_re = re.compile(r'(<path>\./)[^/]+/(.+</path>)')
existing_paths = set()
# ES-DE currently stores <alternativeEmulator> as a sibling before <gameList>.
# This is not well-formed XML (two root-level elements), but it matches ES-DE's
# own gamelist output — confirmed via gitlab.com/es-de/emulationstation-de
# issue #1740. Do not move it inside <gameList> unless ES-DE upstream changes
# this behaviour. This decision was made explicitly; see the work queue note
# "GLFIX decision — compatibility first".
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
    if rel_subdir:
        def _prefix_path(match):
            body = match.group(1)
            if body.startswith(rel_subdir + '/'):
                return '<path>./' + body + '</path>'
            return '<path>./' + rel_subdir + '/' + body + '</path>'
        cleaned = re.sub(r'<path>\./([^<]+)</path>', _prefix_path, cleaned)
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
                # vpinball sources are full Windows dumps: the flat ROM dir also
                # carries B2S server binaries/helpers that aren't tables. Scoped
                # to vpinball so DOS/PC systems that legitimately ship .exe ROMs
                # are unaffected; .vpx tables and per-table .ini are kept.
                if [[ "$ESDE_SYS" == "vpinball" ]]; then
                    case "${BASENAME,,}" in *.exe|*.dll|*.config|*.cmd|*.log) continue ;; esac
                fi
                if is_known_bios_file "$BASENAME" || looks_like_generic_bios_archive "$BASENAME"; then
                    _import_bios_file "$ROM" false
                    continue
                fi
                SEEN=$((SEEN + 1))
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    mv -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                else
                    cp -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                fi
                # Progress ping every 50 files so large packs don't look frozen
                (( SEEN % 50 == 0 )) && echo -n " ${SEEN}..."
            # FLAT systems (c64, amiga*, msx*, dos, vpinball, etc.) recursively
            # collect files. The old `-not -path "*/media/*"` only excluded the
            # RetroBat-style media/ wrapper, so a source with ES/Batocera-style
            # images/, videos/, manuals/ at the system root — or any MEDIA_SKIP
            # folder (bezels/, overlays/, decorations/, extras/, maps/) — and any
            # flat scrape-output folder (covers/, marquees/, screenshots/, etc.)
            # would leak its PNGs/MP4s/PDFs straight into ROMs/<system>/.
            # Prune every known media-shaped directory before emitting files.
            done < <(find "$SYS_DIR" \
                        \( -type d \( \
                            -iname media           -o -iname downloaded_media \
                            -o -iname images       -o -iname videos       -o -iname manuals \
                            -o -iname covers       -o -iname backcovers   -o -iname 3dboxes \
                            -o -iname marquees     -o -iname screenshots  -o -iname titlescreens \
                            -o -iname fanart       -o -iname miximages    -o -iname physicalmedia \
                            -o -iname bezel        -o -iname bezels       -o -iname overlay \
                            -o -iname overlays     -o -iname decoration   -o -iname decorations \
                            -o -iname extras       -o -iname map          -o -iname maps \
                            -o -iname thumbnails   -o -iname wheel        -o -iname wheels \
                            -o -iname snap         -o -iname snaps \
                        \) -prune \) \
                        -o -type f -print0)
        else
            # Collect MAME-family romset folders as they are copied; they are
            # normalised in a SECOND pass after the flat-file copy below, so
            # that normalise_mame_folder can see any flat <romset>.zip that
            # arrives in the file pass (State A: flat parent ROM + sibling
            # CHD folder). Normalising inline here would run before the flat
            # zip exists and mis-route the folder as a CHD-only set.
            _mame_pending=()
            while IFS= read -r -d '' SUBDIR; do
                DIRNAME=$(basename "$SUBDIR"); DIRKEY="${DIRNAME,,}"
                # Skip media folders so they aren't copied into the ROM dir as
                # if they were game subfolders: the media/ wrapper, ES/Batocera
                # images|videos|manuals, AND any flat media-type folder that
                # the media branch above already routed (covers, marquees,
                # screenshots, mix, bezel, etc.). 'system' is a RetroBat
                # config tree (e.g. PS3's rpcs3 dev_hdd0, relocated above for
                # ps3/ps3psn) — never game ROMs, so skip it everywhere.
                case "$DIRKEY" in media|images|videos|manuals|system) continue ;; esac
                [[ -n "${MEDIA_MAP[$DIRKEY]:-}" || -n "${MEDIA_SKIP[$DIRKEY]:-}" ]] && continue
                # Skip emulator support folders (samples/artwork/cfg/nvram/...)
                # so they aren't copied as if each were a game folder — #1.
                if [[ -n "${SUPPORT_SKIP[$DIRKEY]:-}" ]]; then
                    echo ""; echo -e "        ${YELLOW}$DIRNAME/ skipped${NC} (emulator support folder, not a game)"
                    continue
                fi
                echo ""; echo -n "        $DIRNAME [$TRANSFER_LABEL...]"
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    mv -n "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || cp -rn "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || true
                else
                    cp -rn "$SUBDIR" "$ESDE_ROM_DIR/" 2>/dev/null || true
                fi
                echo -e " ${GREEN}done${NC}"; COPIED=$((COPIED + 1))
                # Defer MAME normalisation — see note above.
                [[ -n "${MAME_FAMILY[$ESDE_SYS]:-}" ]] && _mame_pending+=("$ESDE_ROM_DIR/$DIRNAME")
            done < <(find "$SYS_DIR" -maxdepth 1 -mindepth 1 -type d -print0)
            while IFS= read -r -d '' ROM; do
                BASENAME=$(basename "$ROM")
                [[ "$BASENAME" == _* || "$BASENAME" == "gamelist"* || "$BASENAME" == *.txt ]] && continue
                # BIOS sidecars beside games must never appear as visible titles.
                # Preserve required BIOS archives such as neogeo.zip/awbios.zip,
                # but extract generic BIOS bundles such as bios.zip/firmware.rar.
                if is_known_bios_file "$BASENAME" || looks_like_generic_bios_archive "$BASENAME"; then
                    _import_bios_file "$ROM" false
                    continue
                fi
                SEEN=$((SEEN + 1))
                if [[ "$RETROBAT_MOVE" == "yes" ]]; then
                    mv -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                else
                    cp -n "$ROM" "$ESDE_ROM_DIR/" 2>/dev/null && COPIED=$((COPIED + 1)) || true
                fi
                (( SEEN % 50 == 0 )) && echo -n " ${SEEN}..."
            done < <(find "$SYS_DIR" -maxdepth 1 -type f -print0)
        fi
        # Second pass — normalise MAME romset folders now that BOTH the
        # subdir and flat-file copies are done. normalise_mame_folder can
        # now correctly see a flat <romset>.zip sibling (State A) and hide
        # the CHD folder instead of mis-creating a folder game entry.
        if [[ -n "${MAME_FAMILY[$ESDE_SYS]:-}" && ${#_mame_pending[@]} -gt 0 ]]; then
            _mp=""
            for _mp in "${_mame_pending[@]}"; do
                normalise_mame_folder "$_mp" "$ESDE_GAMELIST_DIR"
            done
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
                mkdir -p "$ROMS/vpinball/pinmame/roms" "$ROMS/vpinball/pinmame/nvram"                          "$ROMS/vpinball/pinmame/altcolor" "$ROMS/vpinball/pinmame/altsound"                          "$ROMS/vpinball/pinmame/cfg" "$ROMS/vpinball/pinmame/samples"                          "$ROMS/vpinball/pinmame/ini" "$ROMS/vpinball/music"
                if [[ -L "$BASE/.pinmame" ]]; then
                    ln -sfn "$ROMS/vpinball/pinmame" "$BASE/.pinmame"
                elif [[ ! -e "$BASE/.pinmame" ]]; then
                    ln -s "$ROMS/vpinball/pinmame" "$BASE/.pinmame" 2>/dev/null || true
                fi
                for VSUB in roms nvram altcolor altsound cfg samples ini; do
                    [[ -d "$VPM/$VSUB" ]] || continue
                    mkdir -p "$ROMS/vpinball/pinmame/$VSUB"
                    echo -n "        pinmame/$VSUB ..."
                    _merge_tree "$VPM/$VSUB" "$ROMS/vpinball/pinmame/$VSUB"
                    echo -e " ${GREEN}$(find "$ROMS/vpinball/pinmame/$VSUB" -maxdepth 1 -type f 2>/dev/null | wc -l) files${NC}"
                done
                # VPMAlias.txt lives in the VPinMAME ROOT (not a subfolder), so
                # the per-subfolder loop above misses it. It maps mod-table game
                # names to real romsets (e.g. BEASTIEBOYS,barra_l1); without it an
                # aliased table can't resolve its ROM. Union-merge so source
                # aliases accumulate without clobbering ones already present.
                if [[ -f "$VPM/VPMAlias.txt" ]]; then
                    _adst="$ROMS/vpinball/pinmame/VPMAlias.txt"
                    if [[ -f "$_adst" ]]; then
                        cat "$_adst" "$VPM/VPMAlias.txt" | awk 'NF && !seen[$0]++' > "$_adst.tmp" 2>/dev/null \
                            && mv "$_adst.tmp" "$_adst" 2>/dev/null || rm -f "$_adst.tmp"
                    else
                        cp -n "$VPM/VPMAlias.txt" "$_adst" 2>/dev/null || true
                    fi
                    echo "        pinmame/VPMAlias.txt ($(grep -c ',' "$_adst" 2>/dev/null) alias entries)"
                fi
                # VPROOT = emulators/vpinball/ — Music/ and Scripts/ sit beside
                # VPinMAME/. Music is kept in ROMs/vpinball/music for portability;
                # Emulators/Music is created as a compatibility symlink when safe.
                VPROOT=$(dirname "$VPM")
                mkdir -p "$ROMS/vpinball/music" "$ROMS/vpinball/pinmame/ini"
                if [[ -L "$BASE/Emulators/Music" ]]; then
                    ln -sfn "../ROMs/vpinball/music" "$BASE/Emulators/Music"
                elif [[ ! -e "$BASE/Emulators/Music" ]]; then
                    ln -s "../ROMs/vpinball/music" "$BASE/Emulators/Music" 2>/dev/null || true
                fi
                if [[ -d "$VPROOT/Music" ]]; then
                    echo -n "        ROMs/vpinball/music ..."
                    _merge_tree "$VPROOT/Music" "$ROMS/vpinball/music"
                    echo -e " ${GREEN}$(find "$ROMS/vpinball/music" -type f 2>/dev/null | wc -l) files${NC}"
                fi
                # Scripts library: tables do GetTextFile("core.vbs"), resolved from the
                # table dir first, so the .vbs library normally lives beside the .vpx in
                # ROMs/vpinball/. BUT the VPinball Standalone build ships its OWN copy of
                # the standard library (core.vbs, controller.vbs, etc.) in
                # Emulators/VPinball/scripts/, adapted for the plugin-PinMAME/BGFX build
                # (it carries the UsePdbLeds auto-declare guard + IsPluginPinMAME handling
                # that RetroBat's Windows-COM copies lack). Harvesting RetroBat's same-
                # named files into the table dir SHADOWS the build's matched copies
                # (table-dir wins in GetTextFile) and crashes every ROM-running table with
                # "ChangedPDLeds not declared". So skip any .vbs the build already ships;
                # harvest only RetroBat-only extras (genuine table-specific scripts).
                VPSCR="$VPROOT/Scripts"
                [[ ! -d "$VPSCR" ]] && VPSCR="$VPM/Scripts"
                if [[ -d "$VPSCR" ]]; then
                    BLDSCR=""
                    for _c in "$BASE/Emulators/VPinball/scripts" "$BASE/Emulators/VPinball/Scripts"; do
                        if [[ -d "$_c" ]]; then BLDSCR="$_c"; break; fi
                    done
                    unset _bundled 2>/dev/null || true
                    declare -A _bundled=()
                    if [[ -n "$BLDSCR" ]]; then
                        while IFS= read -r -d '' _bf; do
                            _bundled["$(basename "$_bf" | tr '[:upper:]' '[:lower:]')"]=1
                        done < <(find "$BLDSCR" -maxdepth 1 -type f -iname '*.vbs' -print0 2>/dev/null)
                    fi
                    echo -n "        ROMs/vpinball/ (script library) ..."
                    SCRN=0; SKPN=0
                    while IFS= read -r -d '' SVB; do
                        _bn="$(basename "$SVB" | tr '[:upper:]' '[:lower:]')"
                        if [[ -n "${_bundled[$_bn]:-}" ]]; then
                            SKPN=$((SKPN + 1)); continue   # emulator ships its own — never shadow it
                        fi
                        if [[ "${RETROBAT_MOVE:-no}" == "yes" ]]; then
                            mv -n "$SVB" "$ROMS/vpinball/" 2>/dev/null && SCRN=$((SCRN + 1)) || true
                        else
                            cp -n "$SVB" "$ROMS/vpinball/" 2>/dev/null && SCRN=$((SCRN + 1)) || true
                        fi
                    done < <(find "$VPSCR" -maxdepth 1 -type f -iname '*.vbs' -print0 2>/dev/null)
                    if [[ -n "$BLDSCR" ]]; then
                        echo -e " ${GREEN}$SCRN extra .vbs${NC} (skipped $SKPN bundled with the emulator)"
                    else
                        echo -e " ${GREEN}$SCRN .vbs files${NC} ${YELLOW}(emulator scripts dir not found — harvested all; may shadow emulator copies)${NC}"
                    fi
                fi
            else
                warn "vpinball: no VPinMAME folder in source — PinMAME tables will need ROMs added to ROMs/vpinball/pinmame/roms/ manually"
            fi
            # Hide the support subfolders (music/, pinmame/) from ES-DE. They live
            # inside ROMs/vpinball/ for VPinball portability but aren't tables, so
            # ES-DE would otherwise list them as empty browsable folders. Append a
            # hidden <folder> entry to the system gamelist — ES-DE's native hide,
            # same mechanism as the MAME CHD-folder hide. Idempotent.
            mkdir -p "$ESDE_GAMELIST_DIR"
            VPGL="$ESDE_GAMELIST_DIR/gamelist.xml"
            for _hf in music pinmame; do
                [[ -d "$ROMS/vpinball/$_hf" ]] || continue
                _ent="  <folder>
    <path>./$_hf</path>
    <name>$_hf</name>
    <hidden>true</hidden>
  </folder>"
                if [[ -f "$VPGL" ]]; then
                    grep -qF "<path>./$_hf</path>" "$VPGL" 2>/dev/null && continue
                    if grep -q '</gameList>' "$VPGL" 2>/dev/null; then
                        _tmp=$(mktemp)
                        awk -v e="$_ent" '/<\/gameList>/{print e} {print}' "$VPGL" > "$_tmp" && mv "$_tmp" "$VPGL"
                    else
                        printf '%s\n%s\n' "$_ent" '</gameList>' >> "$VPGL"
                    fi
                else
                    printf '%s\n%s\n%s\n%s\n' '<?xml version="1.0"?>' '<gameList>' "$_ent" '</gameList>' > "$VPGL"
                fi
            done
            echo -e "        ${GREEN}music/ + pinmame/ hidden from ES-DE${NC}"
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
        ensure_emulator_for "$ESDE_SYS" "$RB_SYS"
        # Auto-verify BIOS for the system we just imported.
        verify_system "$ESDE_SYS" || true
    done < <(enumerate_system_dirs "$RETROBAT_PATH")
    if [[ "$RETROBAT_MOVE" == "yes" ]]; then
        # Cut mode: each imported file was ALREADY moved out, file-by-file, via
        # `mv -n`. We must NEVER bulk-delete the source tree. Anything still in
        # it was NOT imported — skipped systems, unrecognized files, or name
        # collisions (mv -n won't overwrite) — and is left for the user to review
        # and delete manually. We only prune directories that are now genuinely
        # empty (find -empty -delete cannot touch files or non-empty dirs).
        find "$RETROBAT_PATH" -depth -type d -empty -delete 2>/dev/null || true
        if [[ -e "$RETROBAT_PATH" ]]; then
            warn "Cut mode: imported items were moved out. Anything still under"
            warn "  $RETROBAT_PATH was NOT imported (skipped/unrecognized/collision)."
            warn "  It has been left untouched — review and delete it yourself."
        else
            ok "Source fully imported; empty source folder removed"
        fi
    fi
done
echo ""
ok "Import complete: $IMPORT_SYSTEMS systems, $IMPORT_MEDIA media types, $IMPORT_ROMS items"
echo ""
# Final summary BIOS sweep across everything in the bundle
echo -e "${CYAN}── Final BIOS sweep across all systems ──${NC}"
verify_all || true
echo ""

# Clear ES-DE's media-availability cache so the newly-imported gamelists
# and downloaded_media tree are re-read from disk on next launch.
# Without this, any user who launched ES-DE before importing will see
# stale "no media" tiles even though the files are now in place. This is
# the root cause of the most common 'I imported but nothing shows' bug.
CACHEDIR=""
for c in "$BASE/ES-DE/CACHES" "$BASE/ES-DE/caches" "$BASE/ES-DE/cache"; do
    [[ -d "$c" ]] && CACHEDIR="$c" && break
done
if [[ -n "$CACHEDIR" ]]; then
    if [[ "$ESDE_RUNNING" == "true" ]]; then
        warn "ES-DE is still running. Quit it fully, then run this to refresh tiles:"
        echo "         rm -rf \"$CACHEDIR\"/*"
    else
        rm -rf "$CACHEDIR"/* 2>/dev/null || true
        ok "Cleared ES-DE cache at $CACHEDIR (imported media will appear on next launch)"
    fi
else
    info "ES-DE cache dir not found yet (ES-DE hasn't been launched). Fresh launch will index correctly."
fi
CONVSCRIPT
backup_file_if_changed "${IMPORTER_FILE}" "${IMPORTER_TMP}" "import-collection.sh"

chmod +x "$BASE/import-collection.sh"
ok "import-collection.sh written to bundle"


# Deploy fetch-vpx-patches.sh — pulls VPX Standalone sidecar scripts for
# tables that have a community patch in jsm174/vpx-standalone-scripts.
VPX_FETCH_FILE="$BASE/fetch-vpx-patches.sh"
VPX_FETCH_TMP="${VPX_FETCH_FILE}.tmp.$$"
cat > "${VPX_FETCH_TMP}" << 'FETCHVPXSCRIPT'
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
backup_file_if_changed "${VPX_FETCH_FILE}" "${VPX_FETCH_TMP}" "fetch-vpx-patches.sh"
chmod +x "$BASE/fetch-vpx-patches.sh"
ok "fetch-vpx-patches.sh written to bundle"


#=============================================================================
# STEP 16: WRITE UPDATE SCRIPT TO BUNDLE
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Writing update.sh to bundle..."

UPDATE_FILE="$BASE/update.sh"
UPDATE_TMP="${UPDATE_FILE}.tmp.$$"
cat > "${UPDATE_TMP}" << 'UPDATESCRIPT'
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
    # Args: label   current_glob   latest_url
    local label="$1" current_glob="$2" latest_url="$3"
    local current_file
    current_file=$(find "$EMUS" -maxdepth 2 -name "$current_glob" 2>/dev/null | head -1)
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
        local tmp="$EMUS/$latest_name.tmp.$$"
        if curl -#fL -o "$tmp" "$latest_url"; then
            mv -f "$tmp" "$EMUS/$latest_name"
            chmod +x "$EMUS/$latest_name"
            # Only delete the previous file if its path actually changed —
            # if current_file *was* $EMUS/$latest_name (same basename), the
            # mv above already replaced it, so a delete would orphan the
            # new copy.
            [[ "$current_file" != "$EMUS/$latest_name" ]] && rm -f "$current_file"
            ok "Updated to $latest_name"
        else
            warn "Download failed — keeping current version"
            rm -f "$tmp"
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
    "$(github_latest_url PCSX2/pcsx2 'linux-appimage-x64.*\.AppImage$')"

check_and_update "DuckStation (PS1)" "DuckStation*.AppImage" \
    "$(github_latest_url stenzek/duckstation 'DuckStation.*x64.*\.AppImage$')"

check_and_update "PPSSPP (PSP)" "PPSSPP*.AppImage" \
    "$(github_latest_url hrydgard/ppsspp 'PPSSPP.*x86_64.*\.AppImage$')"

check_and_update "melonDS (DS)" "melonDS*.AppImage" \
    "$(github_latest_url pkgforge-dev/melonDS-AppImage-Enhanced 'melonDS.*x86_64.*\.AppImage$')"

check_and_update "Dolphin (GC/Wii)" "dolphin*.AppImage" \
    "$(github_latest_url pkgforge-dev/Dolphin-emu-AppImage 'Dolphin_Emulator.*x86_64.*\.AppImage$')"

check_and_update "Cemu (Wii U)" "Cemu*.AppImage" \
    "$(github_latest_url cemu-project/Cemu 'Cemu.*\.AppImage$')"

AZAHAR_URL=$(curl -sfL "https://api.github.com/repos/azahar-emu/azahar/releases?per_page=5" \
    | grep -oP '"browser_download_url":\s*"\K[^"]*azahar\.AppImage(?!-)' | head -1) || true
check_and_update "Azahar (3DS)" "azahar*.AppImage" "$AZAHAR_URL"

check_and_update "xemu (Xbox)" "xemu*.AppImage" \
    "$(github_latest_url xemu-project/xemu 'xemu.*x86_64\.AppImage$')"

check_and_update "Eden (Switch)" "Eden*.AppImage" \
    "$(github_latest_url eden-emulator/Releases 'Eden-Linux.*x86_64.*\.AppImage$')"

check_and_update "86Box (Win9x/PC)" "86Box*.AppImage" \
    "$(github_latest_url 86Box/86Box '86Box.*x86_64.*\.AppImage$')"

# shadPS4 — ships as zip/tarball with sibling Qt/SDL shared libs and
# resource subdirs. The old update path moved ONLY the binary, breaking
# plugin discovery for builds that depend on the bundled libs (Qt
# platform plugins, audio backends, translations). Mirror the install
# path: copy the binary, every sibling .so*, and every sibling subdir.
SHADPS4_CURRENT=$(find "$EMUS" -maxdepth 1 -name 'shadps4' -type f 2>/dev/null | head -1)
if [[ -n "$SHADPS4_CURRENT" ]]; then
    printf "   %-32s" "shadPS4 (PS4)"
    echo -e " ${CYAN}[zip release — re-download to update]${NC}"
    if wt_yesno "Update" "Re-download latest?"; then
        SHAD_URL=$(curl -sfL "https://api.github.com/repos/shadps4-emu/shadPS4/releases?per_page=5" \
            | grep -oP '"browser_download_url":\s*"\K[^"]*' \
            | grep -iP "shadps4-linux-sdl.*\.zip$|linux.*x86.?64.*\.(tar\.(gz|xz)|zip)$" \
            | grep -iv "debug\|symbols\|arm" \
            | head -1) || true
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
                SHAD_BIN=$(find "$SHAD_TMP" -type f \( -name "shadps4-qt" -o -name "shadps4" -o -iname "shadps4*.AppImage" -o -iname "Shadps4*.AppImage" \) 2>/dev/null | grep -v "\.so" | head -1)
                if [[ -n "$SHAD_BIN" ]]; then
                    BIN_DIR=$(dirname "$SHAD_BIN")
                    cp -f "$SHAD_BIN" "$EMUS/shadps4"
                    chmod +x "$EMUS/shadps4"
                    # Refresh sibling shared libraries and resource subdirs
                    # (Qt plugins, translations, etc.). cp -f overwrites in
                    # place; -r picks up new subdirs the upstream may add.
                    find "$BIN_DIR" -maxdepth 1 -name "*.so*" -exec cp -f {} "$EMUS/" \; 2>/dev/null || true
                    find "$BIN_DIR" -maxdepth 1 -mindepth 1 -type d -exec cp -rf {} "$EMUS/" \; 2>/dev/null || true
                    ok "shadPS4 updated (binary + support files)"
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
VPDIR="$EMUS/VPinball"
if [[ -f "$VPDIR/VPinballX_BGFX" ]] || [[ -f "$VPDIR/VPinballX_GL" ]]; then
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
                        tar -xzf "$TGZ" -C "$VPIN_TMP/extract" 2>/dev/null || \
                        tar -xJf "$TGZ" -C "$VPIN_TMP/extract" 2>/dev/null || true
                        rm -f "$TGZ"
                    done
                fi
            done <<< "$VPIN_URLS"
            for BIN in VPinballX_BGFX VPinballX_GL; do
                FOUND=$(find "$VPIN_TMP" -name "$BIN" -type f 2>/dev/null | head -1)
                [[ -n "$FOUND" ]] && cp "$FOUND" "$VPDIR/$BIN" && chmod +x "$VPDIR/$BIN"
            done
            rm -rf "$VPIN_TMP"
            ok "VPinball updated"
        else
            warn "Could not find download URL"
        fi
    fi
    echo ""
fi


# Ports / Engines AppImages
check_and_update "OpenTTD" "OpenTTD*.AppImage" \
    "$(github_latest_url pkgforge-dev/OpenTTD-AppImage '\.AppImage$' | grep -ivE 'aarch|arm')"
check_and_update "Commander Genius" "Commander-Genius*.AppImage" \
    "$(github_latest_url pkgforge-dev/Commander-Genius-AppImage '\.AppImage$' | grep -ivE 'aarch|arm')"
check_and_update "C-Dogs SDL" "C-Dogs_SDL*.AppImage" \
    "$(github_latest_url pkgforge-dev/C-Dogs_SDL-AppImage '\.AppImage$' | grep -ivE 'aarch|arm')"
check_and_update "OpenTyrian 2000" "OpenTyrian2000*.AppImage" \
    "$(github_latest_url pkgforge-dev/OpenTyrian2000-AppImage '\.AppImage$' | grep -ivE 'aarch|arm')"
check_and_update "OpenRA" "OpenRA*.AppImage" \
    "$(github_latest_url pkgforge-dev/OpenRA-AppImage-Enhanced '\.AppImage$' | grep -ivE 'aarch|arm')"

# Supermodel
check_and_update "Supermodel (Model 3)" "Supermodel*.AppImage"     "$(github_latest_url pkgforge-dev/Supermodel-AppImage '\.AppImage$' | grep -iv arm)"

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

check_and_update "Ryubing (Switch)" "ryujinx*.AppImage"     "$(github_latest_url Ryubing/Ryujinx 'x64\.AppImage$')"

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
backup_file_if_changed "${UPDATE_FILE}" "${UPDATE_TMP}" "update.sh"

chmod +x "$BASE/update.sh"
ok "update.sh written to bundle"

#=============================================================================
# STEP 17: DESKTOP SHORTCUT
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

    DESKTOP_FILE="$DESKTOP_DIR/es-de-portable.desktop"
DESKTOP_TMP="$DESKTOP_FILE.tmp.$$"
cat > "$DESKTOP_TMP" << DESKTOPFILE
[Desktop Entry]
Version=1.0
Type=Application
Name=ES-DE
Comment=Retro gaming frontend — portable bundle
Exec=${BASE}/launch.sh
Icon=${ICON_PATH}
Terminal=false
Categories=Game;Emulator;
Keywords=retro;emulator;gaming;
StartupNotify=true
DESKTOPFILE
backup_file_if_changed "$DESKTOP_FILE" "$DESKTOP_TMP" "es-de-portable.desktop"

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
# STEP 18: SUMMARY
#=============================================================================
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Summary"
echo ""

# Count what we got.
# Enumerate every downloaded emulator binary ONCE into an array, then reuse it
# for both the count and the listing below so the two can never disagree.
# AppImages may sit flat in $BASE or $EMUS, or nested under $EMUS/<Port>/ and
# $EMUS/VPinball/. A few emulators ship as plain binaries rather than AppImages
# (xenia_canary, VPinballX_*) — include those explicitly. $EMUS lives inside
# $BASE, so search $BASE once to avoid double-counting.
mapfile -t DOWNLOADED_BINS < <(
    find "$BASE" -maxdepth 3 -type f -iname '*.AppImage' 2>/dev/null
    [[ -f "$EMUS/xenia_canary" ]] && printf '%s\n' "$EMUS/xenia_canary"
    find "$EMUS" -maxdepth 2 -type f -name 'VPinballX*' 2>/dev/null
)
APPIMAGE_COUNT=${#DOWNLOADED_BINS[@]}
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
for f in "${DOWNLOADED_BINS[@]}"; do
    [[ -f "$f" ]] && box_line "    - $(basename "$f")"
done
box_blank
box_line "  To start playing:"
box_line "    1. Add ROMs to ROMs/<system>/"
box_line "    2. Add BIOS files to ROMs/bios/"
box_line "    3. Run: ./launch.sh"
box_blank
box_line "  Source ports (Commander Keen, Tyrian, Cave Story, OpenRA...):"
box_line "    Put each port's game data in its OWN folder:"
box_line "      Emulators/<Port>/"
box_line "      e.g. Emulators/Commander-Genius/ (Keen game files)"
box_line "           Emulators/OpenTyrian2000/ (Tyrian data)"
box_line "           Emulators/NXEngine/ (Cave Story data/)"
box_line "    Each folder has a _PUT-GAME-DATA-HERE.txt note;"
box_line "    the README ports table lists what each one needs."
box_blank
box_line "  Bundle location:"
box_line "    $BASE"
box_blank
box_line "  Re-run this script anytime to retry failed downloads"
box_line "  or to update after a new ES-DE release."
box_rule '╚' '╝'

#=============================================================================
# STEP 19: OPTIONAL ROM COLLECTION IMPORT
#=============================================================================
# The bundle is fully built at this point — ES-DE, RetroArch, cores,
# emulators and ALL helper scripts (including import-collection.sh) are on
# disk. Offer the user a one-shot import using the single canonical
# importer. This is the ONLY ROM-import path in the project now; the old
# setup-time importer (former STEP 12) has been removed (Audit F8).
STEP=$((STEP + 1))
echo -e "${CYAN}[$STEP/$TOTAL_STEPS]${NC} Optional ROM collection import"
echo ""

# Defensive wrapper: this is the last step, so any earlier non-zero
# return (caught by set -e) would silently skip the import offer.
# Disable set -e for this block; re-enable before the exec handoff.
set +e

IMPORTER="$BASE/import-collection.sh"
if [[ ! -e "$IMPORTER" ]]; then
    warn "import-collection.sh missing — STEP 15 may have failed; check setup output above"
elif [[ ! -x "$IMPORTER" ]]; then
    info "import-collection.sh present but not executable — chmod +x"
    chmod +x "$IMPORTER" 2>/dev/null || true
fi

if [[ -x "$IMPORTER" ]]; then
    PROMPT_TEXT="Setup is complete.

Would you like to import ROM collections now?

This will run the bundle's importer (import-collection.sh), which can
import a full RetroBat install, a ROM-pack collection, or a single-system
folder, with a -test preview mode and per-system launch reporting.

You can also run it anytime later with:
    ./import-collection.sh        (import)
    ./import-collection.sh -test  (preview only)"

    DO_IMPORT=""
    # Try whiptail first; fall back to a plain read prompt if whiptail
    # is missing, no TTY, or it errors out (any of which silently
    # killed this prompt in the past).
    if command -v whiptail >/dev/null 2>&1 && [[ -t 0 ]]; then
        if whiptail --title "Import ROM collections?" --yesno "$PROMPT_TEXT" "$WT_H" "$WT_W"; then
            DO_IMPORT="yes"
        else
            DO_IMPORT="no"
        fi
    fi
    if [[ -z "$DO_IMPORT" ]]; then
        echo "$PROMPT_TEXT"
        echo ""
        read -r -p "Run importer now? [y/N] " _ans
        case "${_ans,,}" in
            y|yes) DO_IMPORT="yes" ;;
            *)     DO_IMPORT="no" ;;
        esac
    fi

    set -e
    if [[ "$DO_IMPORT" == "yes" ]]; then
        echo ""
        echo -e "${CYAN}Launching collection importer...${NC}"
        echo ""
        # Hand off to the canonical importer. exec replaces this process so
        # the importer's exit status becomes the setup script's exit status.
        cd "$BASE" && exec "$IMPORTER"
    else
        info "Skipped import — run ./import-collection.sh anytime to import later"
    fi
else
    set -e
    warn "import-collection.sh not found or not executable — skipping import offer"
fi
echo ""
