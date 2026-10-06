# medewerker-welkom.ps1 - sluit een medewerker aan op zijn bedrijfs-Mainframe (Windows).
# Spiegel van lib/medewerker-welkom.sh. Leest bij de veilige Convex-resolver welke lagen
# deze persoon mag ophalen, en cloont ALLEEN die lagen als submappen onder mijn-mainframe/.
#
# Env: MF_ORG (GitHub-organisatie; dan komt alles uit GitHub zelf, geen andere server nodig)
#      of MF_SLUG (oud, via de aansluit-server), MF_DIR (default $HOME\mijn-mainframe), MF_GH, MF_VOORNAAM,
#      MF_ENDPOINT (default de Mainframe Convex-host), MF_DRYRUN=1
# "Continue" en niet "Stop": in Windows PowerShell 5.1 (de standaard op Windows) telt een
# foutregel van git of gh die je met 2>$null wegstuurt als een fout. Met "Stop" brak het
# script dan af, bijvoorbeeld bij iemand die nog niet was ingelogd, VOOR de inlogstap.
# Fouten controleren we hieronder zelf met $LASTEXITCODE.
$ErrorActionPreference = "Continue"

function Say($m) { Write-Host "  $m" }

$OrgLokaal = $env:MF_ORG
$Slug = if ($env:MF_SLUG) { $env:MF_SLUG } elseif ($OrgLokaal) { $OrgLokaal.ToLower() } else { $null }
if (-not $Slug) { Say "Zet MF_ORG op de GitHub-organisatie van je bedrijf (bv QDP-BV)."; exit 1 }
$Dir = if ($env:MF_DIR) { $env:MF_DIR } else { Join-Path $HOME "mijn-mainframe" }
$Endpoint = if ($env:MF_ENDPOINT) { $env:MF_ENDPOINT } else { "https://api.slimwerken.ai" }

# 1. Gereedschap.
foreach ($t in @("git","gh")) {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
    Say "$t ontbreekt. Installeer het (git: https://git-scm.com/download/win ; gh: 'winget install GitHub.cli') en probeer opnieuw."
    exit 1
  }
}

# 2. Inloggen met eigen GitHub-account.
& gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Say "Je moet even inloggen met je eigen GitHub-account."
  if ($env:MF_DRYRUN -ne "1") { & gh auth login --web -h github.com --git-protocol https }
}
& gh auth setup-git 2>$null | Out-Null
$Gh = $env:MF_GH
if (-not $Gh) { $ghUit = & gh api user --jq .login 2>$null; if ($ghUit) { $Gh = ([string]$ghUit).Trim() } }
if (-not $Gh) { Say "Kon je GitHub-naam niet bepalen. Log in met 'gh auth login'."; exit 1 }
Say "Ingelogd als $Gh."

if ($OrgLokaal) {
# 3 (zonder server). Eerst de uitnodigingen accepteren, dan zie je je teams.
$Org = $OrgLokaal
if ($env:MF_DRYRUN -ne "1") {
  & gh api -X PATCH "user/memberships/orgs/$Org" -f state=active 2>$null | Out-Null
  $inv = (& gh api user/repository_invitations 2>$null) | Out-String
  if ($inv.Trim()) {
    $lijst = $inv | ConvertFrom-Json
    foreach ($i in $lijst) { if ($i.repository.owner.login -eq $Org) { & gh api -X PATCH "user/repository_invitations/$($i.id)" 2>$null | Out-Null; Say "Uitnodiging voor $($i.repository.name) geaccepteerd." } }
  }
}
$staat = ([string](& gh api "user/memberships/orgs/$Org" --jq .state 2>$null)).Trim()
if ($staat -ne "active") {
  Say "Je bent (nog) geen lid van $Org. Vraag een beheerder je toe te voegen en Doorvoeren te kiezen,"
  Say "of accepteer de uitnodiging via https://github.com/orgs/$Org/invitation en draai dit opnieuw."; exit 1
}
$teamsJson = (& gh api user/teams --paginate 2>$null) | Out-String
$lagenTekst = "ok=true`nlaag=bedrijf`trepo=mainframe-bedrijf`nlaag=bedrijfsprojecten`trepo=mainframe-bedrijfsprojecten"
$Board = "false"; $afd = $null
if ($teamsJson.Trim()) {
  # --paginate kan meerdere lijsten achter elkaar geven: ][ samenvoegen.
  $alle = ($teamsJson -replace '\]\s*\[', ',') | ConvertFrom-Json
  foreach ($tm in $alle) {
    if ($tm.organization.login -ne $Org) { continue }
    if ($tm.slug -eq "directie") { $Board = "true"; $lagenTekst += "`nlaag=directie`trepo=mainframe-directie" }
    elseif ($tm.slug -ne "iedereen" -and -not $afd) { $afd = $tm.slug; $lagenTekst += "`nlaag=afdeling`trepo=mainframe-$($tm.slug)" }
  }
}
$lines = $lagenTekst -split "`n"
$Pers = "mainframe-persoonlijk-$($Gh.ToLower())"; $Naam = $env:MF_VOORNAAM
Say "Bedrijf gevonden: org $Org. Ik haal alleen jouw lagen op."
} else {
# 3. Vraag de resolver welke lagen jij mag ophalen.
if ($Endpoint -ne "https://api.slimwerken.ai") {
  Say "Deze aansluit-server is niet vertrouwd. Verwijder MF_ENDPOINT en probeer opnieuw."; exit 1
}
$MfGhToken = ([string](& gh auth token --hostname github.com 2>$null)).Trim()
if ($LASTEXITCODE -ne 0 -or -not $MfGhToken) {
  Say "Je GitHub-login is verlopen. Log opnieuw in met 'gh auth login'."; exit 1
}
try {
  # Slug en GitHub-naam bestaan alleen uit letters, cijfers en streepjes: geen codering nodig
  # (en [uri] is niet beschikbaar in de beperkte stand van PowerShell).
  $slugQuery = $Slug -replace '[^A-Za-z0-9._-]', ''
  $ghQuery = $Gh -replace '[^A-Za-z0-9._-]', ''
  $resp = (Invoke-WebRequest -UseBasicParsing -ErrorAction Stop -Headers @{ Authorization = "Bearer $MfGhToken" } -Uri "$Endpoint/enterprise/mijn-lagen?slug=$slugQuery&github_username=$ghQuery").Content
} catch { Say "Aansluiten lukt niet. Controleer je GitHub-login en probeer opnieuw."; exit 1 }
finally { $MfGhToken = $null }
$lines = $resp -split "`n"
function Field($k) { ($lines | Where-Object { $_ -match "^$k=" } | Select-Object -First 1) -replace "^$k=","" }
if ((Field "ok") -ne "true") {
  switch (Field "reden") {
    "geen_lid" { Say "Je GitHub-naam '$Gh' staat (nog) niet als lid bij bedrijf '$Slug'. Vraag je beheerder je toe te voegen." }
    "onbekend_bedrijf" { Say "Bedrijf '$Slug' is onbekend. Klopt de bedrijfsnaam?" }
    "geen_org" { Say "Dit bedrijf heeft nog geen GitHub-organisatie gekoppeld. Vraag je beheerder." }
    default { Say "Aansluiten kan nu niet. Vraag je beheerder." }
  }
  exit 1
}
$Org = Field "github_org"; $Naam = Field "naam"; $Pers = Field "persoonlijk_repo"; $Board = Field "is_board"
if ($Board -ne "true") { $Board = "false" }
if ($env:MF_VOORNAAM) { $Naam = $env:MF_VOORNAAM }
Say "Bedrijf gevonden: org $Org. Ik haal alleen jouw lagen op."
}

$lagen = @()
foreach ($l in $lines) {
  if ($l -match "^laag=") {
    $parts = $l -split "`t"
    $laag = ($parts[0]) -replace "^laag=",""
    $repo = ($parts[1]) -replace "^repo=",""
    $lagen += ,@($laag,$repo)
  }
}

# 3b. Openstaande GitHub-uitnodigingen van dit bedrijf zelf accepteren. Zonder dat geeft
# ophalen een 404: de meest voorkomende vastloper bij Horti (juli 2026).
if ($env:MF_DRYRUN -ne "1") {
  & gh api -X PATCH "user/memberships/orgs/$Org" -f state=active 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { Say "Lid van de organisatie $Org." }
  else { Say "Let op: accepteer de uitnodiging van $Org via https://github.com/orgs/$Org/invitation en draai dit opnieuw." }
  # Filteren in PowerShell zelf: aanhalingstekens in een --jq-argument raken in
  # Windows PowerShell 5.1 kwijt onderweg naar gh.
  $inv = (& gh api user/repository_invitations 2>$null) | Out-String
  if ($LASTEXITCODE -eq 0 -and $inv.Trim()) {
    # Eerst in een variabele: in 5.1 komt een JSON-lijst anders als een enkel ding terug.
    $lijst = $inv | ConvertFrom-Json
    foreach ($i in $lijst) {
      if ($i.repository.owner.login -eq $Org) {
        & gh api -X PATCH "user/repository_invitations/$($i.id)" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Say "Uitnodiging voor $($i.repository.name) geaccepteerd." }
      }
    }
  }
}

if ($env:MF_DRYRUN -eq "1") {
  Say "[dry-run] zou naar $Dir clonen:"
  foreach ($p in $lagen) { Write-Host "    - $($p[0]) <- $($p[1])" }
  Say "[dry-run] plus kluis $Pers -> ik/ + mijn-projecten/"
  exit 0
}

# 4. Clone bedrijf-laag naar ROOT, de rest als submappen.
function CloneOrPull($url, $dest) {
  if (Test-Path (Join-Path $dest ".git")) { & git -C $dest pull -q --no-rebase 2>$null }
  else {
    & git clone -q $url $dest
    if ($LASTEXITCODE -ne 0) {
      Say "Ophalen van $url lukt niet. Heb je de uitnodiging in je mail (van GitHub) al geaccepteerd?"
      exit 1
    }
  }
}
New-Item -ItemType Directory -Force -Path (Split-Path $Dir) | Out-Null
foreach ($p in $lagen) {
  $laag = $p[0]; $repo = $p[1]; $url = "https://github.com/$Org/$repo.git"
  if ($laag -eq "bedrijf") { CloneOrPull $url $Dir; Say "laag bedrijf -> $Dir (root)" }
  else { CloneOrPull $url (Join-Path $Dir $laag); Say "laag $laag -> $Dir\$laag" }
}

# 5. Persoonlijke kluis -> ik/ + mijn-projecten/.
$KluisDir = Join-Path $HOME ".mainframe-persoonlijk-$Slug"
CloneOrPull "https://github.com/$Org/$Pers.git" $KluisDir
foreach ($m in @("ik","mijn-projecten")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $KluisDir $m) | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $Dir $m) | Out-Null
  $kluisM = Join-Path $KluisDir $m; $werkM = Join-Path $Dir $m
  if ((Get-ChildItem $kluisM -Force -ErrorAction SilentlyContinue) -and -not (Get-ChildItem $werkM -Force -ErrorAction SilentlyContinue)) {
    Copy-Item -Recurse -Force (Join-Path $kluisM "*") $werkM; Say "kluis teruggezet: $m/"
  }
}
$overMij = Join-Path $Dir "ik\over-mij.md"
if (-not (Test-Path $overMij)) {
  $naamTxt = if ($Naam) { $Naam } else { "(vul in)" }
  @"
# Over mij

- Naam: $naamTxt
- Schrijfstijl: (vul in hoe jij wilt dat Claude schrijft)
- Deze map is PRIVE. Hij verlaat je computer nooit en wordt alleen naar je eigen kluis gebackupt.
"@ | Set-Content -Encoding UTF8 $overMij
  Say "ik/over-mij.md aangemaakt."
}
$leesmij = Join-Path $Dir "mijn-projecten\LEES-MIJ.md"
if (-not (Test-Path $leesmij)) { "# Mijn projecten`n`nJouw eigen werk. Blijft prive tot je zegt `"deel dit met het bedrijf`"." | Set-Content -Encoding UTF8 $leesmij }
# Persoonlijk geheugen + veilige sleutel-plek voorbereiden (prive, in de kluis).
$mem = Join-Path $Dir "ik\memory"
New-Item -ItemType Directory -Force -Path $mem | Out-Null
$memFile = Join-Path $mem "MEMORY.md"
if (-not (Test-Path $memFile)) { "# Mijn geheugen`n`nPersoonlijke notities die Claude tussen sessies onthoudt. Prive: alleen op jouw computer en in je kluis.`n`n- (nog leeg)" | Set-Content -Encoding UTF8 $memFile }
$envFile = Join-Path $Dir "ik\.env"
if (-not (Test-Path $envFile)) { "# Jouw persoonlijke sleutels (API-keys, tokens). PRIVE: staat nergens gedeeld, gaat alleen mee in je kluis.`n# Koppel een dienst met /koppel; Claude zet de sleutel hier veilig neer." | Set-Content -Encoding UTF8 $envFile }

# 6. Aansluit-config voor /einde.
$mf = Join-Path $Dir ".mainframe"
New-Item -ItemType Directory -Force -Path $mf | Out-Null
# Alleen gewone tekst en Set-Content: werkt ook in de beperkte stand (ConstrainedLanguage).
$json = "{`n"
$json += "  ""github_org"": ""$Org"",`n"
$json += "  ""slug"": ""$Slug"",`n"
$json += "  ""github_username"": ""$Gh"",`n"
$json += "  ""persoonlijk_repo"": ""$Pers"",`n"
$json += "  ""is_board"": $Board,`n"
$json += "  ""lagen"": [`n"
foreach ($p in $lagen) {
  $map = if ($p[0] -eq "bedrijf") { "." } else { $p[0] }
  $json += "    { ""laag"": ""$($p[0])"", ""repo"": ""$($p[1])"", ""map"": ""$map"" },`n"
}
$json += "    { ""laag"": ""ik"", ""map"": ""ik"" },`n"
$json += "    { ""laag"": ""mijn-projecten"", ""map"": ""mijn-projecten"" }`n"
$json += "  ]`n}`n"
# ASCII: geen onzichtbare BOM-tekens voor de JSON (namen zijn altijd ASCII).
Set-Content -Encoding Ascii -NoNewline -Path (Join-Path $mf "aansluiting.json") -Value $json

Say "Aangesloten. Je Mainframe staat klaar in: $Dir"
if (Get-Command code -ErrorAction SilentlyContinue) { & code $Dir 2>$null }
