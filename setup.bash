#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log() {
    printf '[\033[1;36mArchSetup\033[0m] %s\n' "$*"
}

set_gsetting_if_needed() {
    local schema="$1"
    local key="$2"
    local value="$3"
    local current

    current="$(gsettings get "$schema" "$key")"
    if [[ "$current" == "'$value'" || "$current" == "$value" ]]; then
        log "$key bereits aktuell"
        return
    fi

    gsettings set "$schema" "$key" "$value"
    log "$key gesetzt"
}

is_extension_installed() {
    local uuid="$1"

    [[ -f "$EXT_BASE/$uuid/metadata.json" ]] ||
        gnome-extensions list 2>/dev/null | grep -Fxq -- "$uuid"
}

install_ext() {
    local uuid="$1"
    local target_dir="$EXT_BASE/$uuid"
    local staging_dir="$TMP_DIR/extensions/$uuid"
    local download_file="$TMP_DIR/$uuid.zip"
    local api_file="$TMP_DIR/$uuid.json"
    local shell_version
    local download_path

    if is_extension_installed "$uuid"; then
        log "Extension vorhanden: $uuid"
        return
    fi

    log "Installiere Extension: $uuid"
    shell_version="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
    curl -fsSL --get \
        --data-urlencode "uuid=$uuid" \
        --data-urlencode "shell_version=$shell_version" \
        "https://extensions.gnome.org/extension-info/" \
        -o "$api_file"
    download_path="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("download_url") or "")' "$api_file")"
    if [[ -z "$download_path" ]]; then
        log "Keine kompatible Version: $uuid"
        return 1
    fi

    mkdir -p "$staging_dir"
    curl -fsSL "https://extensions.gnome.org$download_path" -o "$download_file"
    unzip -q "$download_file" -d "$staging_dir"
    if [[ ! -f "$staging_dir/metadata.json" ]]; then
        log "Ungültiges Extension-Archiv: $uuid"
        return 1
    fi

    mkdir -p "$EXT_BASE"
    if [[ -d "$target_dir" ]]; then
        cp -a "$staging_dir/." "$target_dir/"
    else
        mv "$staging_dir" "$target_dir"
    fi
}

IS_PTYXIS=false

if [[ -n "${KITTY_PID:-}" || "${TERM:-}" == "xterm-kitty" ]]; then
    IS_PTYXIS=false
elif [[ -n "${PTYXIS_PROFILE:-}" || "${COLORTERM:-}" =~ ptyxis ]]; then
    IS_PTYXIS=true
else
    PARENT_PROC="$(ps -p "$PPID" -o comm= 2>/dev/null || true)"
    if [[ "$PARENT_PROC" == "ptyxis" || "$PARENT_PROC" == "org.gnome.Ptyxis" ]]; then
        IS_PTYXIS=true
    fi
fi

if [[ "$IS_PTYXIS" == true ]]; then
    log "Ptyxis erkannt"
else
    CURRENT_TERM="${KITTY_PID:+kitty}"
    CURRENT_TERM="${CURRENT_TERM:-${TERM_PROGRAM:-$(ps -p "$PPID" -o comm= 2>/dev/null || true)}}"
    log "Abbruch: Ptyxis erforderlich (aktuell: '$CURRENT_TERM')"

    if ! command -v ptyxis >/dev/null 2>&1; then
        log "Installiere Ptyxis"
        sudo pacman -S --needed --noconfirm ptyxis
    else
        log "Ptyxis ist installiert"
    fi

    log "Bitte in Ptyxis erneut starten"
    exit 1
fi

REQUIRED_PACKAGES=(git ptyxis extension-manager curl unzip python)
MISSING_PACKAGES=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! pacman -Q "$package" >/dev/null 2>&1; then
        MISSING_PACKAGES+=("$package")
    fi
done

mapfile -t BASE_DEVEL_PACKAGES < <(pacman -Sgq base-devel 2>/dev/null || true)
if ((${#BASE_DEVEL_PACKAGES[@]} == 0)); then
    MISSING_PACKAGES+=(base-devel)
else
    for package in "${BASE_DEVEL_PACKAGES[@]}"; do
        if ! pacman -Q "$package" >/dev/null 2>&1; then
            MISSING_PACKAGES+=(base-devel)
            break
        fi
    done
fi

if ((${#MISSING_PACKAGES[@]})); then
    log "Installiere fehlende Pakete"
    sudo pacman -S --needed --noconfirm "${MISSING_PACKAGES[@]}"
else
    log "Pakete bereits installiert"
fi

if [[ -f "$SCRIPT_DIR/background" ]]; then
    BG_URI="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().as_uri())' "$SCRIPT_DIR/background")"
    set_gsetting_if_needed org.gnome.desktop.background picture-uri-dark "$BG_URI"
    set_gsetting_if_needed org.gnome.desktop.background picture-uri "$BG_URI"
else
    log "Hintergrundbild nicht gefunden"
fi
set_gsetting_if_needed org.gnome.desktop.interface color-scheme prefer-dark

EXT_BASE="$HOME/.local/share/gnome-shell/extensions"
mkdir -p "$EXT_BASE"
for uuid in \
    "dash-to-dock@micxgx.gmail.com" \
    "hidetopbar@mathieu.bidon.ca" \
    "app-hider@lynith.dev" \
    "dhruva@narkagni"; do
    if ! install_ext "$uuid"; then
        log "Extension-Installation fehlgeschlagen: $uuid"
        continue
    fi

    if gnome-extensions list --enabled 2>/dev/null | grep -Fxq -- "$uuid"; then
        log "Extension aktiv: $uuid"
    elif gnome-extensions enable "$uuid"; then
        log "Extension aktiviert: $uuid"
    else
        log "Extension konnte nicht aktiviert werden: $uuid"
    fi
done

CONFIG_FILE="$SCRIPT_DIR/gnome-extensions-config.ini"
if [[ -f "$CONFIG_FILE" ]]; then
    CURRENT_CONFIG="$(dconf dump /org/gnome/shell/extensions/)"
    DESIRED_CONFIG="$(<"$CONFIG_FILE")"
    if [[ "$CURRENT_CONFIG" == "$DESIRED_CONFIG" ]]; then
        log "Dconf-Einstellungen bereits aktuell"
    else
        dconf load /org/gnome/shell/extensions/ < "$CONFIG_FILE"
        log "Dconf-Einstellungen importiert"
    fi
else
    log "Dconf-Konfiguration nicht gefunden"
fi

log "Prüfe optionale Pakete"
OPTIONAL_PACKAGES=(gnome-contacts gnome-weather gnome-clocks gnome-maps htop gnome-music snapshot vim gnome-characters gnome-tour gnome-software gnome-text-editor gnome-calendar epiphany gnome-connections malcontent decibels gnome-font-viewer showtime loupe gnome-console)
INSTALLED_PACKAGES="$(pacman -Qq "${OPTIONAL_PACKAGES[@]}" 2>/dev/null || true)"
if [[ -n "$INSTALLED_PACKAGES" ]]; then
    mapfile -t INSTALLED_PACKAGE_LIST <<< "$INSTALLED_PACKAGES"
    sudo pacman -Rns --noconfirm "${INSTALLED_PACKAGE_LIST[@]}"
    log "Optionale Pakete entfernt"
else
    log "Keine optionalen Pakete installiert"
fi

log "Prüfe Systemupdates"
sudo pacman -Syu --noconfirm

if command -v paru >/dev/null 2>&1; then
    log "Paru bereits installiert"
else
    log "Installiere Paru"
    git clone https://aur.archlinux.org/paru.git "$TMP_DIR/paru"
    (cd "$TMP_DIR/paru" && makepkg -si --noconfirm)
fi

SHORTCUT_SCHEMA=org.gnome.settings-daemon.plugins.media-keys
CUSTOM_SHORTCUT_SCHEMA="${SHORTCUT_SCHEMA}.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
set_gsetting_if_needed "$SHORTCUT_SCHEMA" custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']"
set_gsetting_if_needed "$CUSTOM_SHORTCUT_SCHEMA" name 'Ptyxis'
set_gsetting_if_needed "$CUSTOM_SHORTCUT_SCHEMA" command 'ptyxis'
set_gsetting_if_needed "$CUSTOM_SHORTCUT_SCHEMA" binding '<Super>t'
set_gsetting_if_needed "$SHORTCUT_SCHEMA" home "['<Super>e']"
set_gsetting_if_needed "$SHORTCUT_SCHEMA" control-center "['<Super>i']"
set_gsetting_if_needed "$SHORTCUT_SCHEMA" www "['<Super>w']"
log "Shortcuts geprüft"

if [[ -f "$HOME/.bashrc" ]] && cmp -s "$SCRIPT_DIR/.bashrc" "$HOME/.bashrc"; then
    log "Bash-Konfiguration bereits aktuell"
else
    cp "$SCRIPT_DIR/.bashrc" "$HOME/.bashrc"
    log "Bash-Konfiguration aktualisiert"
fi

log "Setup abgeschlossen"