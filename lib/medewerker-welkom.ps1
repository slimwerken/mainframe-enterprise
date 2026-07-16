# medewerker-welkom.ps1 - sluit een medewerker aan op zijn bedrijfs-Mainframe (Windows).
# Spiegel van lib/medewerker-welkom.sh. Leest bij de veilige Convex-resolver welke lagen
# deze persoon mag ophalen, en cloont ALLEEN die lagen als submappen onder mijn-mainframe/.
#
# Env: MF_SLUG (verplicht), MF_DIR (default $HOME\mijn-mainframe), MF_GH, MF_VOORNAAM,
#      MF_ENDPOINT (default de Mainframe Convex-host), MF_DRYRUN=1
$ErrorActionPreference = "Stop"

function Say($m) { Write-Host "  $m" }

$Slug = $env:MF_SLUG
if (-not $Slug) { Say "Zet MF_SLUG op je bedrijf (bv test-bv)."; exit 1 }
$Dir = if ($env:MF_DIR) { $env:MF_DIR } else { Join-Path $HOME "mijn-mainframe" }
$Endpoint = if ($env:MF_ENDPOINT) { $env:MF_ENDPOINT } else { "https://efficient-retriever-70.eu-west-1.convex.site" }

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
  if ($env:MF_DRYRUN -ne "1") { & gh auth login --web }
}
& gh auth setup-git 2>$null | Out-Null
$Gh = if ($env:MF_GH) { $env:MF_GH } else { (& gh api user --jq .login).Trim() }
if (-not $Gh) { Say "Kon je GitHub-naam niet bepalen. Log in met 'gh auth login'."; exit 1 }
Say "Ingelogd als $Gh."

# 3. Vraag de resolver welke lagen jij mag ophalen.
try {
  $resp = (Invoke-WebRequest -UseBasicParsing -Uri "$Endpoint/enterprise/mijn-lagen?slug=$Slug&github_username=$Gh").Content
} catch { Say "Kon de aansluit-server niet bereiken. Check je internet."; exit 1 }
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
if ($env:MF_VOORNAAM) { $Naam = $env:MF_VOORNAAM }
Say "Bedrijf gevonden: org $Org. Ik haal alleen jouw lagen op."

$lagen = @()
foreach ($l in $lines) {
  if ($l -match "^laag=") {
    $parts = $l -split "`t"
    $laag = ($parts[0]) -replace "^laag=",""
    $repo = ($parts[1]) -replace "^repo=",""
    $lagen += ,@($laag,$repo)
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
  else { & git clone -q $url $dest }
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
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("{")
[void]$sb.AppendLine("  ""github_org"": ""$Org"",")
[void]$sb.AppendLine("  ""slug"": ""$Slug"",")
[void]$sb.AppendLine("  ""github_username"": ""$Gh"",")
[void]$sb.AppendLine("  ""persoonlijk_repo"": ""$Pers"",")
[void]$sb.AppendLine("  ""is_board"": $($Board.ToLower()),")
[void]$sb.AppendLine("  ""lagen"": [")
foreach ($p in $lagen) {
  $map = if ($p[0] -eq "bedrijf") { "." } else { $p[0] }
  [void]$sb.AppendLine("    { ""laag"": ""$($p[0])"", ""repo"": ""$($p[1])"", ""map"": ""$map"" },")
}
[void]$sb.AppendLine("    { ""laag"": ""ik"", ""map"": ""ik"" },")
[void]$sb.AppendLine("    { ""laag"": ""mijn-projecten"", ""map"": ""mijn-projecten"" }")
[void]$sb.AppendLine("  ]")
[void]$sb.AppendLine("}")
$sb.ToString() | Set-Content -Encoding UTF8 (Join-Path $mf "aansluiting.json")

Say "Aangesloten. Je Mainframe staat klaar in: $Dir"
if (Get-Command code -ErrorAction SilentlyContinue) { & code $Dir 2>$null }
