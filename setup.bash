#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log() {
    printf '[\033[1;36mArchSetup\033[0m] %s\n' "$*"
}

cleanup_clone() {
    local repo_root
    local repo_name
    local repo_status

    repo_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -z "$repo_root" || "$repo_root" != "$SCRIPT_DIR" || ! -e "$repo_root/.git" ]]; then
        log "Clone-Bereinigung übersprungen"
        return
    fi

    repo_name="${repo_root##*/}"
    if [[ "${repo_name,,}" != "archsetup" ]]; then
        log "Clone-Bereinigung übersprungen: Ordnername abweichend"
        return
    fi

    repo_status="$(git -C "$repo_root" status --porcelain --untracked-files=all)"
    if [[ -n "$repo_status" ]]; then
        log "Clone-Bereinigung übersprungen: lokale Änderungen vorhanden"
        return
    fi

    cd "$HOME"
    rm -rf -- "$repo_root"
    log "Geklonten Ordner entfernt"
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

if ((EUID == 0)); then
    log "Bitte ohne sudo starten; erhöhte Rechte werden bei Bedarf angefordert"
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    log "Abbruch: pacman nicht gefunden; Arch Linux erforderlich"
    exit 1
fi

REQUIRED_PACKAGES=(git ptyxis python fastfetch ttf-jetbrains-mono)
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

set_gsetting_if_needed org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 11'

if [[ -f "$SCRIPT_DIR/background" ]]; then
    BG_URI="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().as_uri())' "$SCRIPT_DIR/background")"
    set_gsetting_if_needed org.gnome.desktop.background picture-uri-dark "$BG_URI"
    set_gsetting_if_needed org.gnome.desktop.background picture-uri "$BG_URI"
else
    log "Hintergrundbild nicht gefunden"
fi
set_gsetting_if_needed org.gnome.desktop.interface color-scheme prefer-dark

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
cleanup_clone