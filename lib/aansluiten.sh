#!/bin/bash
# aansluiten.sh - een Mac in een keer aansluiten op het bedrijfs-Mainframe.
# Spiegel van aansluiten.ps1 (Windows). Per Mac EEN regel in Terminal, niet in Claude Code:
#
#   MF_ORG="QDP-BV" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/aansluiten.sh)"
#
# Doet: Apple's gereedschap (git en python3) als het ontbreekt, de GitHub-tool (gh) in
# ~/.mainframe/bin (geen Homebrew en geen wachtwoord nodig), inloggen met je EIGEN
# GitHub-account, medewerker-welkom.sh (uitnodigingen accepteren, alleen jouw lagen ophalen)
# en daarna 1password.sh (1Password CLI en de knop Mainframe starten).
#
# Env (optioneel): MF_DIR (werkmap, standaard ~/mijn-mainframe), MF_ZONDER_1PASSWORD=1 (bedrijf
# gebruikt geen 1Password), MF_GEEN_CODE=1 (VS Code aan het eind niet openen).
set -u

say() { printf '  %s\n' "$1"; }
heeft() { command -v "$1" >/dev/null 2>&1; }

if [ -z "${MF_ORG:-}" ] && [ -z "${MF_SLUG:-}" ]; then
  say 'Zet eerst je bedrijf voor de regel: MF_ORG="<GitHub-organisatie>"'
  exit 1
fi

BIN="$HOME/.mainframe/bin"
mkdir -p "$BIN"
export PATH="$BIN:/usr/local/bin:/opt/homebrew/bin:$PATH"
MAC=0
[ "$(uname -s)" = "Darwin" ] && MAC=1

# 0. Het profiel: ~/.mainframe/bin in het pad van elke nieuwe Terminal en van VS Code en Claude Code,
# plus (later) het 1Password-serviceaccount uit de sleutelhanger. Een bestand, een regel per profiel.
zet_profiel() {
  cat > "$HOME/.mainframe/profiel.sh" <<'EOF'
# Mainframe: gereedschap en 1Password. Gemaakt door aansluiten.sh; niet met de hand aanpassen.
case ":$PATH:" in *":$HOME/.mainframe/bin:"*) ;; *) PATH="$HOME/.mainframe/bin:$PATH"; export PATH;; esac
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  if [ -x /usr/bin/security ]; then
    _mf_t="$(/usr/bin/security find-generic-password -a "$USER" -s "Mainframe 1Password" -w 2>/dev/null)"
  elif [ -f "$HOME/.config/mainframe/op-serviceaccount" ]; then
    _mf_t="$(cat "$HOME/.config/mainframe/op-serviceaccount" 2>/dev/null)"
  fi
  if [ -n "${_mf_t:-}" ]; then OP_SERVICE_ACCOUNT_TOKEN="$_mf_t"; export OP_SERVICE_ACCOUNT_TOKEN; fi
  unset _mf_t
fi
EOF
  regel='[ -f "$HOME/.mainframe/profiel.sh" ] && . "$HOME/.mainframe/profiel.sh"  # Mainframe'
  bash_bestand="$HOME/.bash_profile"
  [ ! -f "$bash_bestand" ] && [ -f "$HOME/.profile" ] && bash_bestand="$HOME/.profile"
  for f in "$HOME/.zshrc" "$HOME/.zprofile" "$bash_bestand"; do
    if ! grep -qs '.mainframe/profiel.sh' "$f"; then
      printf '\n%s\n' "$regel" >> "$f"
    fi
  done
}
zet_profiel

# 1. Apple's gereedschap: git en python3. Op een nieuwe Mac staat dat er nog niet op; Apple
# laat dan een eigen venster zien en wij wachten tot het klaar is.
if [ "$MAC" = "1" ]; then
  if ! xcode-select -p >/dev/null 2>&1 || ! /usr/bin/git --version >/dev/null 2>&1; then
    say "Apple's gereedschap (git en python3) ontbreekt nog."
    say "Er verschijnt een venster van Apple: klik op Installeren en daarna op Akkoord. Dit duurt een paar minuten."
    xcode-select --install >/dev/null 2>&1 || true
    i=0
    until xcode-select -p >/dev/null 2>&1 && /usr/bin/git --version >/dev/null 2>&1; do
      i=$((i + 1))
      if [ "$i" -gt 360 ]; then
        say "Apple is na een half uur nog niet klaar. Draai de regel opnieuw zodra het venster van Apple klaar is."
        exit 1
      fi
      [ $((i % 12)) -eq 0 ] && say "Nog even wachten tot Apple klaar is met installeren..."
      sleep 5
    done
    say "Apple's gereedschap staat erop."
  fi
elif ! heeft git; then
  say "Git ontbreekt. Installeer git (bijvoorbeeld: sudo apt install git) en draai de regel opnieuw."
  exit 1
fi

# 2. De GitHub-tool (gh). Staat hij er al (Homebrew of eerder), dan die; anders de officiele
# versie van GitHub in ~/.mainframe/bin. Geen wachtwoord nodig.
installeer_gh() {
  v="$(curl -fsSI -o /dev/null -w '%{redirect_url}' https://github.com/cli/cli/releases/latest 2>/dev/null | sed -n 's|.*/tag/v||p')"
  [ -n "$v" ] || return 1
  case "$(uname -m)" in arm64|aarch64) a=arm64;; *) a=amd64;; esac
  t="$(mktemp -d)"
  if [ "$MAC" = "1" ]; then
    curl -fsSL -o "$t/gh.zip" "https://github.com/cli/cli/releases/download/v$v/gh_${v}_macOS_$a.zip" &&
      unzip -q "$t/gh.zip" -d "$t" && cp "$t"/gh_*/bin/gh "$BIN/gh" && chmod 755 "$BIN/gh"
  else
    curl -fsSL -o "$t/gh.tgz" "https://github.com/cli/cli/releases/download/v$v/gh_${v}_linux_$a.tar.gz" &&
      tar -xzf "$t/gh.tgz" -C "$t" && cp "$t"/gh_*/bin/gh "$BIN/gh" && chmod 755 "$BIN/gh"
  fi
  s=$?
  rm -rf "$t"
  return $s
}
if ! heeft gh; then
  say "De GitHub-tool installeren."
  if ! installeer_gh || ! heeft gh; then
    say "De GitHub-tool lukte niet. Check de internetverbinding en draai de regel opnieuw."
    exit 1
  fi
fi
say "Git en de GitHub-tool staan erop."

# Python is voor /team (het teambeheer op je eigen computer) en voor de 1Password-sleutels.
if ! python3 -c "import sys" >/dev/null 2>&1; then
  say "Python ontbreekt. Aansluiten gaat gewoon door; Claude regelt het later met /inrichten."
fi

# 3. Inloggen met je eigen GitHub-account.
if ! gh auth status >/dev/null 2>&1; then
  say "Log in met JE EIGEN GitHub-account. Kopieer de code hieronder, druk op Enter,"
  say "plak de code in de browser en klik op Authorize."
  gh auth login --web -h github.com --git-protocol https
  if ! gh auth status >/dev/null 2>&1; then
    say "Inloggen is niet gelukt. Draai de regel opnieuw."
    exit 1
  fi
fi

# 4. De echte aansluiting (accepteert de uitnodigingen en haalt alleen jouw lagen op).
BRON="${MF_WELKOM_BRON:-https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/medewerker-welkom.sh}"
TMP="$(mktemp -d)"
if ! curl -fsSL -o "$TMP/medewerker-welkom.sh" "$BRON"; then
  say "Kon de aansluiting niet ophalen. Check de internetverbinding en probeer opnieuw."
  rm -rf "$TMP"
  exit 1
fi
MF_GEEN_CODE=1 sh "$TMP/medewerker-welkom.sh"
s=$?
rm -rf "$TMP"
[ "$s" -eq 0 ] || exit "$s"
DIR="${MF_DIR:-$HOME/mijn-mainframe}"
say "Je Mainframe staat klaar."

# 5. 1Password erbij: CLI, de knop Mainframe starten en de test. Staat de 1Password-app er
# nog niet op en lukt installeren niet, dan zegt het script dat; het aansluiten is dan al gelukt.
if [ -z "${MF_ZONDER_1PASSWORD:-}" ]; then
  say ""
  say "Nu 1Password koppelen."
  OPB="${MF_1PASSWORD_BRON:-https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/1password.sh}"
  if OPS="$(curl -fsSL "$OPB")"; then
    MF_DIR="$DIR" /bin/bash -c "$OPS"
  else
    say "De 1Password-stap kon niet worden opgehaald. Draai later de 1Password-regel van de uitlegpagina."
  fi
fi

# 6. Openen. Met de knop gaan de sleutels uit 1Password mee; anders gewoon VS Code.
say ""
if [ -n "${MF_GEEN_CODE:-}" ]; then
  say "Klaar. Open je Mainframe met 'Mainframe starten' op je bureaublad en typ in Claude Code: hoi"
  exit 0
fi
s=1
if [ -x "$BIN/mainframe" ] && [ -z "${MF_ZONDER_1PASSWORD:-}" ]; then
  "$BIN/mainframe" --stil >/dev/null 2>&1
  s=$?
fi
if [ "$s" -eq 0 ]; then
  say "VS Code gaat nu open. Klik rechtsboven op het oranje icoontje (Claude Code) en typ: hoi"
elif [ "$s" -eq 3 ]; then
  say "VS Code stond al open. Sluit VS Code helemaal (Cmd+Q), dubbelklik op 'Mainframe starten' op je"
  say "bureaublad en typ in Claude Code: hoi"
elif [ "$MAC" = "1" ] && [ -d "/Applications/Visual Studio Code.app" ] && open -a "Visual Studio Code" "$DIR" >/dev/null 2>&1; then
  say "VS Code gaat nu open. Klik rechtsboven op het oranje icoontje (Claude Code) en typ: hoi"
else
  say "Zet VS Code erop (code.visualstudio.com), open hem met 'Mainframe starten' op je bureaublad"
  say "(of Open Folder, map $DIR) en typ in Claude Code: hoi"
fi
