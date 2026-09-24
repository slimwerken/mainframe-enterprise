---
name: medewerker-welkom
description: Sluit een nieuwe medewerker aan op zijn bedrijfs-Mainframe. Regelt de omgeving, laat de persoon inloggen met zijn eigen GitHub-account, en haalt ALLEEN de lagen op waar hij toegang toe heeft (bedrijf, eventueel afdeling/directie, plus zijn eigen prive-lagen). Gebruik wanneer iemand zegt "sluit me aan", "medewerker-welkom", "ik wil aansluiten op het bedrijf", of de aansluit-regel van zijn bedrijf plakt.
metadata:
  version: 1.0.0
---

# Medewerker aansluiten op het bedrijfs-Mainframe

Je helpt een nieuwe medewerker om zijn persoonlijke werkomgeving op te zetten. Hij hoeft
NIETS technisch te snappen; jij regelt alles en legt in gewone taal uit wat er gebeurt.
Neem geen technische beslissingen voor de persoon.

## Stap 0: welk bedrijf?
Bepaal de bedrijf-code (slug). Meestal staat die in de aansluit-regel die de persoon plakte
("... voor bedrijf X"). Zo niet, vraag er vriendelijk naar. Voorbeeld: `test-bv`.

## Stap 1: gereedschap
Zorg dat `git`, `gh` (GitHub CLI) en `curl` aanwezig zijn. Ontbreekt er iets:
- **git**: Windows -> https://git-scm.com/download/win ; Mac -> `xcode-select --install`.
- **gh**: https://cli.github.com (Windows: `winget install GitHub.cli`; Mac: `brew install gh`).
- **curl** zit standaard op Windows 10+ en Mac.
Installeer wat mist (of geef de persoon de link) en ga pas verder als alles er is.

## Stap 2: draai de aansluit-helper
Run het meegeleverde script. Het regelt de GitHub-login, vraagt de veilige resolver welke
lagen deze persoon mag ophalen, en cloont ALLEEN die lagen als submappen onder `mijn-mainframe/`.

- **Mac, Linux en Windows** (Claude Code op Windows werkt met Git Bash, dus dit werkt daar ook):
  ```sh
  MF_SLUG="<bedrijf-slug>" sh <pad-naar-deze-repo>/lib/medewerker-welkom.sh
  ```
- **Reserve voor Windows**, alleen als Git Bash er echt niet is. Windows staat scripts standaard
  niet toe, dus altijd met `-ExecutionPolicy Bypass` (anders: "running scripts is disabled"):
  ```powershell
  $env:MF_SLUG="<bedrijf-slug>"; powershell -NoProfile -ExecutionPolicy Bypass -File "<pad-naar-deze-repo>\lib\medewerker-welkom.ps1"
  ```
Geef de voornaam mee als je die weet: `MF_VOORNAAM="Bart"` (Mac) / `$env:MF_VOORNAAM="Bart"` (Win).

Tijdens het draaien opent een browser voor de GitHub-login (`gh auth login --web`). Laat de
persoon inloggen met zijn EIGEN account. Kan het script niet draaien op deze computer, doe dan
de stappen uit "Handmatig vangnet" hieronder zelf, precies zo.

## Stap 3: leg uit wat er nu staat
Als het klaar is, staat er een map `mijn-mainframe/` met alleen de lagen waar de persoon bij
mag. Leg kort uit (verwijs naar `CLAUDE.md` in die map):
- `bedrijf/`, `bedrijfsprojecten/` = gedeeld met het hele bedrijf.
- `afdeling/` = alleen zichtbaar als hij in een afgeschermde afdeling zit.
- `directie/` = alleen voor de directie (staat er dus meestal niet).
- `ik/`, `mijn-projecten/` = zijn eigen, prive; worden veilig naar zijn eigen kluis gebackupt.
Sluit af met: "typ `/einde` als je klaar bent, dan sla ik je werk op de juiste plek op."

## Handmatig vangnet (als het script niet kan draaien)
Doe dan zelf, in een lege werkmap `mijn-mainframe/`:
1. `gh auth login --web` (eigen account) en pak de naam: `gh api user --jq .login`.
2. Haal de lagen op:
   `curl -fsS -H "Authorization: Bearer $(gh auth token)" "https://efficient-retriever-70.eu-west-1.convex.site/enterprise/mijn-lagen?slug=<SLUG>&github_username=<NAAM>"`
   (Zonder die GitHub-login weigert de server met 401; zo weet hij zeker dat jij het bent.)
   Dit geeft regels `ok=true`, `github_org=...`, `persoonlijk_repo=...` en `laag=..<tab>repo=..`.
   Bij `ok=false` (bv `geen_lid`): leg vriendelijk uit dat de beheerder de persoon eerst moet toevoegen.
3. Clone de laag `bedrijf` naar de ROOT van `mijn-mainframe/`; de andere lagen (`bedrijfsprojecten`,
   `afdeling`, `directie`) elk als submap met de laagnaam:
   `git clone https://github.com/<ORG>/<repo>.git <map>`.
4. Clone de kluis `<persoonlijk_repo>` naar `~/.mainframe-persoonlijk-<SLUG>` en zet `ik/` +
   `mijn-projecten/` als (kopie) in de werkmap terug (of maak ze leeg aan). NOOIT symlinks.
5. Schrijf `mijn-mainframe/.mainframe/aansluiting.json` met `{github_org, slug, github_username,
   persoonlijk_repo, is_board, lagen:[{laag,repo,map}]}` zodat `/einde` weet waar alles heen moet.

Verzin nooit toegang: haal alleen op wat de resolver teruggeeft. Kan de persoon een laag niet
clonen (GitHub weigert), dan hoort hij daar niet bij; dat is de bedoeling, geen fout.
