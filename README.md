# Mainframe Enterprise - aansluiten als medewerker

Dit is de publieke aansluit-hulp voor medewerkers van een bedrijf dat met het Mainframe werkt.
Hij haalt ALLEEN de lagen op waar jij toegang toe hebt en zet je persoonlijke werkomgeving klaar.

## Aansluiten (2 manieren)

### 1. Je hebt Claude Code al
Open Claude Code in een lege map en plak deze regel (vervang de bedrijf-code):

> Volg de medewerker-welkom skill van https://github.com/slimwerken/mainframe-enterprise voor bedrijf JOUW-BEDRIJF-CODE

Claude regelt de rest: inloggen met je eigen GitHub, en alleen jouw lagen ophalen.

### 2. Je hebt nog niks
Gebruik de Mainframe-installer (Windows of Mac). Kies bij het starten "aansluiten op mijn
bedrijf" en vul je bedrijf-code in. De installer zet VS Code + Claude Code klaar en start
daarna dezelfde aansluiting.

## Wat je krijgt
Een map `mijn-mainframe/` met je lagen als submappen:
- `bedrijf/`, `bedrijfsprojecten/` - gedeeld met het hele bedrijf
- `afdeling/` - alleen als je in een afgeschermde afdeling zit
- `directie/` - alleen voor de directie
- `ik/`, `mijn-projecten/` - je eigen, prive werk (wordt naar je eigen kluis gebackupt)

Je ziet alleen de lagen waar je bij mag. Meer hoef je niet te weten: begin gewoon, en typ
`/einde` als je klaar bent.

## Voor beheerders
De inrichting van een bedrijf (org, afdelingen, leden, gedeelde bedrijfslaag) gebeurt met de
`inrichten-bedrijf` skill + `seed-bedrijfslaag.sh`. Detail:
`projecten/mainframe-starter/docs/BOUWPLAN-medewerker-wizard.md` in Het Mainframe.
