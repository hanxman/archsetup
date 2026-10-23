#!/bin/bash

set -e

log() {
    local CYAN='\033[1;36m' # Farbdefinitionen
    local NC='\033[0m' # No Color / Reset

    echo -e "[${CYAN}ArchSetup${NC}]> $*" # Textausgabe: [ und ]> normal, ArchSetup in Cyan
}
install_ext() { # Funktion zum Herunterladen und Entpacken von extensions.gnome.org
    local uuid="$1"
    local download_url="$2"
    local target_dir="$EXT_BASE/$uuid"

    echo "[ArchSetup]> Installiere $uuid"
    mkdir -p "$target_dir"
    curl -sL "$download_url" -o /tmp/gnome_ext_download/ext.zip
    unzip -q -o /tmp/gnome_ext_download/ext.zip -d "$target_dir"
    rm /tmp/gnome_ext_download/ext.zip
}

IS_PTYXIS=false

if [ -n "${KITTY_PID:-}" ] || [ "${TERM:-}" = "xterm-kitty" ]; then # 1. Kitty und andere Terminals explizit ausschließen
    IS_PTYXIS=false


elif [ -n "${PTYXIS_PROFILE:-}" ] || [[ "${COLORTERM:-}" =~ "ptyxis" ]]; then # 2. Eindeutige Ptyxis-Umgebungsvariablen prüfen
    IS_PTYXIS=true

else # 3. Direkten Parent-Prozess der Shell prüfen (exakter Namensabgleich)
    PARENT_PROC=$(ps -p $PPID -o comm= 2>/dev/null || echo "")
    if [ "$PARENT_PROC" = "ptyxis" ] || [ "$PARENT_PROC" = "org.gnome.Ptyxis" ]; then
        IS_PTYXIS=true
    fi
fi


if [ "$IS_PTYXIS" = true ]; then # 4. Auswertung der Abfrage
    log "Ptyxis erkannt! "

else # Terminal-Namen für die Fehlerausgabe bestimmen
    CURRENT_TERM="${KITTY_PID:+kitty}"
    CURRENT_TERM="${CURRENT_TERM:-${TERM_PROGRAM:-$(ps -p $PPID -o comm= 2>/dev/null)}}"

    log "Fehler: Dieses Script darf NUR in Ptyxis ausgeführt werden (Aktuell: '$CURRENT_TERM')."
    
    # Prüfen, ob Ptyxis installiert ist, andernfalls nachinstallieren
    if ! command -v ptyxis &> /dev/null; then
        log "Ptyxis ist nicht installiert. Installiere Ptyxis via pacman..."
        sudo pacman -S --noconfirm ptyxis
        log "Ptyxis wurde erfolgreich installiert."
    else
        log "Ptyxis ist bereits auf dem System installiert."
    fi

    log "Bitte schließe dieses Terminal und starte das Script erneut in Ptyxis!"
    log "Drücke [Enter], um das Script abzubrechen"
    read -r
    exit 1
fi

sudo pacman -S --noconfirm git ptyxis extension-manager base-devel

log "Entferne optionale Pakete..."

# pacman -Qq liefert nur die Pakete zurück, die auch wirklich installiert sind
INSTALLED=$(pacman -Qq gnome-contacts gnome-weather gnome-clocks gnome-maps htop gnome-music snapshot vim gnome-characters gnome-tour gnome-software gnome-text-editor gnome-calendar epiphany gnome-connections malcontent decibels gnome-font-viewer showtime loupe gnome-console 2>/dev/null || true)

if [ -n "$INSTALLED" ]; then
    echo "$INSTALLED" | xargs sudo pacman -Rns --noconfirm
fi

#sudo pacman -Rns --noconfirm gnome-contacts gnome-weather gnome-clocks gnome-maps htop gnome-music snapshot vim gnome-characters gnome-tour gnome-software gnome-text-editor gnome-calendar epiphany gnome-connections malcontent decibels gnome-font-viewer showtime loupe gnome-console
log "unerwünschte Apps deinstalliert"

sudo pacman -Syu


BG_PATH="background.png" # 1. Bildpfad definieren (absoluter Pfad zur Datei)
gsettings set org.gnome.desktop.background picture-uri-dark "$BG_PATH"
gsettings set org.gnome.desktop.background picture-uri "$BG_PATH"

#paru installieren
log "Installiere Paru"
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm
cd ~
rm -rf /tmp/paru
log "Paru installiert!"

log "Setzte Shortcuts"
# 1. Vorhandene benutzerdefinierte Pfade auslesen und neue definieren
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
"['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', \
  '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']"

# 2. Win + T für Pytixis (Terminal / App) einrichten
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Ptyxis'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'ptyxis'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Super>t'

# 3. Standard-Shortcuts für System-Apps anpassen (Win = <Super>)g
gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']" # Super + E -> Files / Nautilus
gsettings set org.gnome.settings-daemon.plugins.media-keys control-center "['<Super>i']" # Super + I -> Settings
gsettings set org.gnome.settings-daemon.plugins.media-keys www "['<Super>w']" # Super + W -> Standard
log "Shortcuts gesetzt!"

log "kopiere .bashrc"
cp .bahrc /home/*/ # .bashrc in Home einfügen


log "inizialisiere Extensions"
EXT_BASE="$HOME/.local/share/gnome-shell/extensions" # Erweiterungs ordner
mkdir -p "$EXT_BASE" #Verzeichnis erstelen falls nicht vorhanden
mkdir -p /tmp/gnome_ext_download #Temp Verzeichniss zum download erstellen

log "Lade und installiere Extensions"

# 1. Dash to Dock (v90)
install_ext "dash-to-dock@micxgx.gmail.com" \
  "https://github.com/micheleg/dash-to-dock/releases/download/extensions.gnome.org-v90/dash-to-dockmicxgx.gmail.com.v90.shell-extension.zip"

# 2. Hide Top Bar
install_ext "hidetopbar@mathiew.bidon.ca" \
  "https://extensions.gnome.org/extension-data/hidetopbarmathiew.bidon.ca.v72.shell-extension.zip"

# 3. App Hider
install_ext "app-hider@lynith.dev" \
  "https://extensions.gnome.org/extension-data/app-hiderlynith.dev.v8.shell-extension.zip"

# 4. Dhruva (falls direkte Zip-Quelle vorhanden, sonst GitHub Release eintragen)
# Falls du die ZIP von ego bereits lokal hast, einfach entpacken
install_ext "dhruva@narkagni" \
  "https://extensions.gnome.org/extension-data/dhruvanarkagni.v1.shell-extension.zip"

# Aufräumen
rm -rf /tmp/gnome_ext_download

log "Aktiviere Extensions"
gnome-extensions enable "dash-to-dock@micxgx.gmail.com" || true
gnome-extensions enable "hidetopbar@mathiew.bidon.ca" || true
gnome-extensions enable "app-hider@lynith.dev" || true
gnome-extensions enable "dhruva@narkagni" || true

log "Lade gespeicherte Dconf-Einstellungen"
if [ -f "./gnome-extensions-config.ini" ]; then
    dconf load /org/gnome/shell/extensions/ < ./gnome-extensions-config.ini
    log "Einstellungen erfolgreich importiert!"
else
    log "Warnung: gnome-extensions-config.ini nicht im selben Ordner gefunden!"
fi

log "Extensioninstalation abgeschlossen!"

# 1. Temporäre Download-Verzeichnisse entfernen
rm -rf /tmp/gnome_ext_download
rm -f /tmp/*.zip

# 2. Lokale Setup-Dateien/Configs im aktuellen Ordner löschen (falls vorhanden)
if [ -f "./gnome-extensions-config.ini" ]; then
    rm -f ./gnome-extensions-config.ini
fi