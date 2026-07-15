#!/bin/sh
# medewerker-welkom.sh - sluit een medewerker aan op zijn bedrijfs-Mainframe (Mac/Linux/git-bash).
# Leest bij de veilige Convex-resolver op welke lagen deze persoon toegang heeft, en cloont
# ALLEEN die lagen als submappen onder mijn-mainframe/. Persoonlijke lagen (ik/, mijn-projecten/)
# komen uit de eigen kluis en blijven prive. Geen jq/python nodig.
#
# Env:
#   MF_SLUG      (verplicht) bedrijf-slug, bv test-bv
#   MF_DIR       (default $HOME/mijn-mainframe) de werkmap
#   MF_GH        (optioneel) github-naam; anders via gh afgeleid
#   MF_VOORNAAM  (optioneel) voor ik/over-mij.md
#   MF_ENDPOINT  (default de Mainframe Convex-host)
#   MF_DRYRUN=1  toon wat er zou gebeuren
set -e

SLUG="${MF_SLUG:?zet MF_SLUG op je bedrijf (bv test-bv)}"
DIR="${MF_DIR:-$HOME/mijn-mainframe}"
ENDPOINT="${MF_ENDPOINT:-https://efficient-retriever-70.eu-west-1.convex.site}"
TAB="$(printf '\t')"

say() { printf '  %s\n' "$1"; }

# 1. Gereedschap.
if ! command -v git >/dev/null 2>&1; then
  say "Git ontbreekt. Installeer git (mac: 'xcode-select --install'; linux: 'apt install git') en probeer opnieuw."
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  say "De GitHub-tool (gh) ontbreekt. Installeer 'gh' (cli.github.com) en probeer opnieuw."
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  say "curl ontbreekt (ongebruikelijk). Installeer curl en probeer opnieuw."
  exit 1
fi

# 2. Inloggen met je eigen GitHub-account.
if ! gh auth status >/dev/null 2>&1; then
  say "Je moet even inloggen met je eigen GitHub-account."
  [ "$MF_DRYRUN" = "1" ] || gh auth login --web
fi
gh auth setup-git >/dev/null 2>&1 || true
GH="${MF_GH:-$(gh api user --jq .login 2>/dev/null || true)}"
if [ -z "$GH" ]; then say "Kon je GitHub-naam niet bepalen. Log in met 'gh auth login'."; exit 1; fi
say "Ingelogd als $GH."

# 3. Vraag de resolver welke lagen jij mag ophalen (veilig, geen geheimen).
RESP="$(curl -fsS "$ENDPOINT/enterprise/mijn-lagen?slug=$SLUG&github_username=$GH")" || {
  say "Kon de aansluit-server niet bereiken. Check je internet en probeer opnieuw."; exit 1; }
OK="$(printf '%s\n' "$RESP" | sed -n 's/^ok=//p' | head -1)"
if [ "$OK" != "true" ]; then
  REDEN="$(printf '%s\n' "$RESP" | sed -n 's/^reden=//p' | head -1)"
  case "$REDEN" in
    geen_lid) say "Je GitHub-naam '$GH' staat (nog) niet als lid bij bedrijf '$SLUG'. Vraag je beheerder om je toe te voegen.";;
    onbekend_bedrijf) say "Bedrijf '$SLUG' is onbekend. Klopt de bedrijfsnaam?";;
    geen_org) say "Dit bedrijf heeft nog geen GitHub-organisatie gekoppeld. Vraag je beheerder.";;
    *) say "Aansluiten kan nu niet ($REDEN). Vraag je beheerder.";;
  esac
  exit 1
fi
ORG="$(printf '%s\n' "$RESP" | sed -n 's/^github_org=//p' | head -1)"
NAAM="$(printf '%s\n' "$RESP" | sed -n 's/^naam=//p' | head -1)"
PERS="$(printf '%s\n' "$RESP" | sed -n 's/^persoonlijk_repo=//p' | head -1)"
BOARD="$(printf '%s\n' "$RESP" | sed -n 's/^is_board=//p' | head -1)"
[ -n "$MF_VOORNAAM" ] && NAAM="$MF_VOORNAAM"
say "Bedrijf gevonden: org $ORG. Ik haal alleen jouw lagen op."

if [ "$MF_DRYRUN" = "1" ]; then
  say "[dry-run] zou naar $DIR clonen:"
  printf '%s\n' "$RESP" | grep '^laag=' | while IFS="$TAB" read -r lp rp; do
    printf '    - %s <- %s\n' "${lp#laag=}" "${rp#repo=}"
  done
  say "[dry-run] plus persoonlijke kluis $PERS -> ik/ + mijn-projecten/"
  exit 0
fi

# 4. Clone de bedrijf-laag naar de ROOT, de rest als submappen (mapnaam = laagnaam).
clone_of_pull() { # $1=url $2=doel
  if [ -d "$2/.git" ]; then git -C "$2" pull -q --no-rebase || true
  else git clone -q "$1" "$2"; fi
}
mkdir -p "$(dirname "$DIR")"
BEDRIJF_REPO=""
printf '%s\n' "$RESP" | grep '^laag=' | while IFS="$TAB" read -r lp rp; do
  laag="${lp#laag=}"; repo="${rp#repo=}"
  url="https://github.com/$ORG/$repo.git"
  if [ "$laag" = "bedrijf" ]; then
    clone_of_pull "$url" "$DIR"; say "laag bedrijf -> $DIR (root)"
  else
    clone_of_pull "$url" "$DIR/$laag"; say "laag $laag -> $DIR/$laag"
  fi
done
# (de subshell-loop hierboven kan geen variabelen exporteren; bedrijf-clone is al gedaan)
if [ ! -d "$DIR" ]; then say "Er ging iets mis bij het ophalen van de bedrijf-laag."; exit 1; fi

# 5. Persoonlijke kluis -> ik/ + mijn-projecten/ (prive, kopie-backup, geen symlinks).
KLUIS_DIR="$HOME/.mainframe-persoonlijk-$SLUG"
clone_of_pull "https://github.com/$ORG/$PERS.git" "$KLUIS_DIR"
mkdir -p "$KLUIS_DIR/ik" "$KLUIS_DIR/mijn-projecten" "$DIR/ik" "$DIR/mijn-projecten"
for laag in ik mijn-projecten; do
  if [ -n "$(ls -A "$KLUIS_DIR/$laag" 2>/dev/null)" ] && [ -z "$(ls -A "$DIR/$laag" 2>/dev/null)" ]; then
    cp -R "$KLUIS_DIR/$laag/." "$DIR/$laag/"; say "kluis teruggezet: $laag/"
  fi
done
if [ ! -f "$DIR/ik/over-mij.md" ]; then
  cat > "$DIR/ik/over-mij.md" <<EOF
# Over mij

- Naam: ${NAAM:-（vul in)}
- Schrijfstijl: (vul in hoe jij wilt dat Claude schrijft)
- Deze map is PRIVE. Hij verlaat je computer nooit en wordt alleen naar je eigen kluis gebackupt.
EOF
  say "ik/over-mij.md aangemaakt."
fi
[ -f "$DIR/mijn-projecten/LEES-MIJ.md" ] || printf '# Mijn projecten\n\nJouw eigen werk. Blijft prive tot je zegt "deel dit met het bedrijf".\n' > "$DIR/mijn-projecten/LEES-MIJ.md"

# 6. Schrijf de aansluit-config (leest /einde straks).
mkdir -p "$DIR/.mainframe"
{
  printf '{\n'
  printf '  "github_org": "%s",\n' "$ORG"
  printf '  "slug": "%s",\n' "$SLUG"
  printf '  "github_username": "%s",\n' "$GH"
  printf '  "persoonlijk_repo": "%s",\n' "$PERS"
  printf '  "is_board": %s,\n' "${BOARD:-false}"
  printf '  "lagen": [\n'
  printf '%s\n' "$RESP" | grep '^laag=' | while IFS="$TAB" read -r lp rp; do
    laag="${lp#laag=}"; repo="${rp#repo=}"
    if [ "$laag" = "bedrijf" ]; then map="."; else map="$laag"; fi
    printf '    { "laag": "%s", "repo": "%s", "map": "%s" },\n' "$laag" "$repo" "$map"
  done
  printf '    { "laag": "ik", "map": "ik" },\n'
  printf '    { "laag": "mijn-projecten", "map": "mijn-projecten" }\n'
  printf '  ]\n}\n'
} > "$DIR/.mainframe/aansluiting.json"

say "Aangesloten. Je Mainframe staat klaar in: $DIR"

# 7. Open VS Code als het er is.
if command -v code >/dev/null 2>&1; then
  code "$DIR" >/dev/null 2>&1 || true
fi
