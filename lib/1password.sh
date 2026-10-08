#!/bin/bash
# 1password.sh - 1Password koppelen aan je Mainframe (Mac). Spiegel van 1password.ps1.
# Een regel in Terminal (niet in Claude Code):
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/1password.sh)"
#
# Doet: de 1Password-app erop als hij ontbreekt, 1Password CLI (op) in ~/.mainframe/bin, de
# knop "Mainframe starten" op het bureaublad en het commando "mainframe" (openen VS Code met je
# sleutels uit 1Password), en test de koppeling. Daarna in Claude Code: /kluis of /inrichten.
#
# Env (optioneel): MF_DIR (je Mainframe-map), MF_OP_ZONDER_APP=1 (app niet nodig, voor tests).
set -u

say() { printf '  %s\n' "$1"; }
heeft() { command -v "$1" >/dev/null 2>&1; }

BIN="$HOME/.mainframe/bin"
mkdir -p "$BIN"
export PATH="$BIN:/usr/local/bin:/opt/homebrew/bin:$PATH"
MAC=0
[ "$(uname -s)" = "Darwin" ] && MAC=1
case "$(uname -m)" in arm64|aarch64) ARCH=arm64;; *) ARCH=amd64;; esac

# 1. De 1Password-app. Eerst zelf installeren (een keer je Mac-wachtwoord); lukt dat niet, dan
# zelf downloaden.
zoek_app() {
  APP=""
  for a in "/Applications/1Password.app" "$HOME/Applications/1Password.app"; do
    if [ -d "$a" ]; then APP="$a"; return 0; fi
  done
  return 1
}
if [ "$MAC" = "1" ] && [ -z "${MF_OP_ZONDER_APP:-}" ] && ! zoek_app; then
  say "De 1Password-app installeren (ongeveer 400 MB, even geduld)."
  say "Vraagt je Mac om een wachtwoord: typ het wachtwoord waarmee je op deze Mac inlogt. Je ziet geen tekens, dat klopt."
  T="$(mktemp -d)"
  if curl -fsSL -o "$T/1Password.pkg" https://downloads.1password.com/mac/1Password.pkg; then
    sudo installer -pkg "$T/1Password.pkg" -target / >/dev/null 2>&1 || true
  fi
  rm -rf "$T"
  if zoek_app; then say "1Password-app staat erop. Open hem en log in met je uitnodiging uit de mail."; fi
fi
if [ "$MAC" = "1" ] && [ -z "${MF_OP_ZONDER_APP:-}" ] && ! zoek_app; then
  say "De 1Password-app staat nog niet op deze Mac."
  say "Download hem op https://1password.com/downloads/mac, log in met je uitnodiging uit de mail"
  say "en draai daarna de 1Password-regel van de uitlegpagina opnieuw."
  exit 0
fi
[ -n "${APP:-}" ] && say "1Password-app gevonden."

# 2. 1Password CLI (op). De officiele versie van 1Password, in ~/.mainframe/bin: geen wachtwoord
# nodig. (Alleen 1Password voor Mac 8.10.12 en ouder eiste /usr/local/bin.)
installeer_op() {
  v="$(curl -fsSL https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N 2>/dev/null | sed -n 's/.*"version":"\([0-9.]*\)".*/\1/p')"
  [ -n "$v" ] || return 1
  if [ "$MAC" = "1" ]; then os=darwin; else os=linux; fi
  t="$(mktemp -d)"
  curl -fsSL -o "$t/op.zip" "https://cache.agilebits.com/dist/1P/op2/pkg/v$v/op_${os}_${ARCH}_v$v.zip" &&
    unzip -q -o "$t/op.zip" -d "$t" && cp "$t/op" "$BIN/op" && chmod 755 "$BIN/op"
  s=$?
  rm -rf "$t"
  return $s
}
if ! heeft op; then
  say "1Password CLI installeren."
  installeer_op || true
fi
if ! heeft op; then
  say "1Password CLI lukte niet. Check de internetverbinding en draai de regel opnieuw."
  exit 1
fi
say "1Password CLI staat erop (versie $(op --version 2>/dev/null))."

# 3. Je Mainframe-map vinden.
DIR="${MF_DIR:-}"
if [ -z "$DIR" ]; then
  for k in "$PWD" "$HOME/mijn-mainframe" "$HOME"/*-mainframe; do
    if [ -d "$k/ik" ] && [ -f "$k/.mainframe/aansluiting.json" ]; then DIR="$k"; break; fi
  done
fi
if [ -z "$DIR" ] || [ ! -d "$DIR/ik" ]; then
  say "Je Mainframe-map niet gevonden. Ga in Terminal eerst naar je map (cd <map>) en draai de regel opnieuw."
  exit 1
fi
DIR="$(cd "$DIR" && pwd)"
# ik/.env netjes: bestaat, alleen voor jou leesbaar, en zonder onzichtbaar teken vooraan
# (1Password CLI leest geen .env met een BOM; QDP, 7 okt 2026).
ENVF="$DIR/ik/.env"
[ -f "$ENVF" ] || : > "$ENVF"
if [ "$(head -c 3 "$ENVF" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
  tail -c +4 "$ENVF" > "$ENVF.nieuw" && mv "$ENVF.nieuw" "$ENVF"
  say "ik/.env opgeschoond (onzichtbaar teken vooraan weggehaald)."
fi
chmod 600 "$ENVF" 2>/dev/null || true

# 4. Het commando "mainframe": opent VS Code met je sleutels uit 1Password. Alles wat daarin
# start (Claude Code, scripts) krijgt dan de echte sleutels in plaats van de op://-verwijzing.
# VS Code moet daarvoor eerst helemaal dicht: een al geopende VS Code houdt zijn oude instellingen.
cat > "$BIN/mainframe" <<EOF
#!/bin/bash
# mainframe - opent je Mainframe in VS Code met je sleutels uit 1Password. Gemaakt door 1password.sh.
DIR="$DIR"
EOF
cat >> "$BIN/mainframe" <<'EOF'
export PATH="$HOME/.mainframe/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
[ -f "$HOME/.mainframe/profiel.sh" ] && . "$HOME/.mainframe/profiel.sh"
if pgrep -f "Visual Studio Code.app/Contents/MacOS/" >/dev/null 2>&1; then
  echo "VS Code staat nog open. Sluit VS Code helemaal (Cmd+Q) en start dit opnieuw." >&2
  exit 3
fi
CODE=""
for c in "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
         "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
  if [ -x "$c" ]; then CODE="$c"; break; fi
done
[ -n "$CODE" ] || CODE="$(command -v code 2>/dev/null)"
if [ -z "$CODE" ]; then
  echo "VS Code staat niet op deze Mac. Installeer hem via code.visualstudio.com en probeer opnieuw." >&2
  exit 4
fi
cd "$DIR" || { echo "Je Mainframe-map $DIR bestaat niet meer." >&2; exit 5; }
[ -f ik/.env ] || : > ik/.env
LOG="$HOME/.mainframe/mainframe-starten.log"
if [ "${1:-}" = "--stil" ]; then
  # Vanuit de knop: geen Terminal, dus de uitvoer naar een logboek en alleen bij een fout iets zeggen.
  if ! op run --env-file=ik/.env -- "$CODE" "$DIR" >"$LOG" 2>&1 </dev/null; then
    { echo "Openen met 1Password lukte niet:"; tail -n 3 "$LOG"
      echo "Is 1Password open en ontgrendeld? Typ anders in Claude Code: /inrichten"; } >&2
    exit 6
  fi
  exit 0
fi
echo "  Mainframe openen met je sleutels uit 1Password..."
exec op run --env-file=ik/.env -- "$CODE" "$DIR" </dev/null
EOF
chmod 755 "$BIN/mainframe"
say "Commando 'mainframe' gemaakt voor $DIR"

# De knop op het bureaublad: een klein programma (geen Terminal-venster) dat "mainframe --stil"
# draait en een foutmelding laat zien als het niet lukt.
if [ "$MAC" = "1" ] && [ -d "$HOME/Desktop" ] && heeft osacompile; then
  KNOP="$HOME/Desktop/Mainframe starten.app"
  rm -rf "$KNOP"
  if osacompile -o "$KNOP" \
    -e 'try' \
    -e '  do shell script "/bin/bash \"$HOME/.mainframe/bin/mainframe\" --stil"' \
    -e 'on error foutTekst' \
    -e '  display dialog foutTekst buttons {"OK"} default button 1 with title "Mainframe starten" with icon caution' \
    -e 'end try' >/dev/null 2>&1; then
    say "Op je bureaublad staat nu: Mainframe starten"
  else
    say "De knop op het bureaublad lukte niet; typ in Terminal: mainframe"
  fi
fi

# 5. Werkt de koppeling met de app?
if ! op vault list </dev/null >/dev/null 2>&1; then
  say ""
  say "Nog een ding in de 1Password-app: log in met je uitnodiging uit de mail, en zet dan aan:"
  say "Instellingen > Ontwikkelaar (Developer) > 'Integrate with 1Password CLI'. Laat de app open en ontgrendeld."
  say "Typ daarna in Claude Code: /inrichten. Claude maakt de rest zelf af."
  exit 0
fi
say "1Password is gekoppeld. Je kluizen:"
op vault list </dev/null
say ""
say "1Password is klaar. Sluit VS Code helemaal (Cmd+Q) en open je Mainframe voortaan met 'Mainframe starten'."
say "Heb je al eigen sleutels in je Mainframe? Typ dan in Claude Code: /kluis"
