# aansluiten.ps1 - een Windows-laptop in een keer aansluiten op het bedrijfs-Mainframe.
# Bedoeld voor de installatiedag: per laptop EEN regel in een gewone PowerShell, geen
# losse stappen meer (Horti, 20 juli 2026: de installatie per persoon duurde te lang).
#
#   $env:MF_SLUG="qdp"; irm https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/aansluiten.ps1 | iex
#
# Doet: Git en de GitHub-tool (gh) erop als ze ontbreken, inloggen met je EIGEN
# GitHub-account, uitnodigingen accepteren, en dan medewerker-welkom.ps1 draaien.
$ErrorActionPreference = "Continue"
function Say($m) { Write-Host "  $m" }

if (-not $env:MF_SLUG) { Say "Zet eerst je bedrijf: `$env:MF_SLUG=`"<bedrijf>`""; return }

function VerversPad {
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}

# 1. Git en gh. Winget zit op Windows 10 en 11; de installatie vraagt soms om Ja.
$pakketten = @(@("git", "Git.Git", "Git"), @("gh", "GitHub.cli", "de GitHub-tool"))
foreach ($p in $pakketten) {
  if (-not (Get-Command $p[0] -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
      Say "Winget ontbreekt. Installeer $($p[2]) met de hand en draai dit opnieuw."; return
    }
    Say "$($p[2]) installeren. Vraagt Windows om toestemming? Klik op Ja."
    & winget install --id $p[1] -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    VerversPad
    if (-not (Get-Command $p[0] -ErrorAction SilentlyContinue)) {
      Say "$($p[2]) staat erop, maar Windows ziet hem nog niet. Sluit dit venster, open een nieuwe PowerShell en draai de regel opnieuw."; return
    }
  }
}
Say "Git en de GitHub-tool staan erop."

# 2. Inloggen met je eigen GitHub-account (hier in een echt venster, dus de code is te zien).
& gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Say "Log in met JE EIGEN GitHub-account. Kopieer de code hieronder en druk op Enter."
  & gh auth login --web -h github.com --git-protocol https
  & gh auth status 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { Say "Inloggen is niet gelukt. Draai de regel opnieuw."; return }
}

# 3. De echte aansluiting (haalt alleen jouw lagen op en accepteert uitnodigingen).
$bron = if ($env:MF_WELKOM_BRON) { $env:MF_WELKOM_BRON } else { "https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/medewerker-welkom.ps1" }
$tmp = Join-Path $env:TEMP "medewerker-welkom.ps1"
try { Invoke-WebRequest -UseBasicParsing -ErrorAction Stop -Uri $bron -OutFile $tmp }
catch { Say "Kon de aansluiting niet ophalen. Check de internetverbinding en probeer opnieuw."; return }
& powershell -NoProfile -ExecutionPolicy Bypass -File $tmp
if ($LASTEXITCODE -eq 0) {
  Say "Klaar. Open Claude Code in je map mijn-mainframe en typ /ophalen."
}
