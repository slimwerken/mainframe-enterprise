# aansluiten.ps1 - een Windows-laptop in een keer aansluiten op het bedrijfs-Mainframe.
# Bedoeld voor de installatiedag: per laptop EEN regel in een gewone PowerShell, geen
# losse stappen meer (Horti, 20 juli 2026: de installatie per persoon duurde te lang).
#
#   $env:MF_ORG="QDP-BV"; irm https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/aansluiten.ps1 | iex
#
# Doet: Git en de GitHub-tool (gh) erop als ze ontbreken, inloggen met je EIGEN
# GitHub-account, uitnodigingen accepteren, en dan medewerker-welkom.ps1 draaien.
$ErrorActionPreference = "Continue"
function Say($m) { Write-Host "  $m" }

if (-not $env:MF_SLUG -and -not $env:MF_ORG) { Say "Zet eerst je bedrijf: `$env:MF_ORG=`"<GitHub-organisatie>`""; return }

function VerversPad {
  # Uit het register, zonder .NET-aanroepen: die zijn geblokkeerd als PowerShell in de beperkte
  # stand draait (ConstrainedLanguage, bij bedrijfslaptops met WDAC/Intune).
  $m = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name Path -ErrorAction SilentlyContinue).Path
  $u = (Get-ItemProperty "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
  $env:Path = "$m;$u"
}

# 1. Git en gh. Winget zit op Windows 10 en 11; de installatie vraagt soms om Ja.
# Python is voor /team (het teambeheer op je eigen computer).
$pakketten = @(@("git", "Git.Git", "Git"), @("gh", "GitHub.cli", "de GitHub-tool"), @("python", "Python.Python.3.12", "Python"))
# Windows heeft een nep-"python" die naar de Microsoft Store wijst; die telt niet.
function Heeft($naam) {
  $c = Get-Command $naam -ErrorAction SilentlyContinue
  return [bool]($c -and $c.Source -notlike "*WindowsApps*")
}
foreach ($p in $pakketten) {
  if (-not (Heeft $p[0])) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
      if ($p[0] -eq "python") { continue }
      Say "Winget ontbreekt. Installeer $($p[2]) met de hand en draai dit opnieuw."; return
    }
    Say "$($p[2]) installeren. Vraagt Windows om toestemming? Klik op Ja."
    & winget install --id $p[1] -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    VerversPad
    if (-not (Heeft $p[0])) {
      if ($p[0] -eq "python") { Say "Python lukte niet. Aansluiten gaat gewoon door; alleen /team (voor beheerders) heeft het nodig."; continue }
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
if ($LASTEXITCODE -ne 0) { return }
Say "Je Mainframe staat klaar."

# 4. 1Password erbij (7 okt 2026, QDP): CLI, de knop Mainframe starten en de test. Staat de
# 1Password-app er nog niet op, dan zegt het script dat en gaat het aansluiten gewoon goed.
if (-not $env:MF_ZONDER_1PASSWORD) {
  Say ""
  Say "Nu 1Password koppelen."
  $opBron = if ($env:MF_1PASSWORD_BRON) { $env:MF_1PASSWORD_BRON } else { "https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/1password.ps1" }
  try { $opScript = Invoke-WebRequest -UseBasicParsing -ErrorAction Stop -Uri $opBron } catch { $opScript = $null }
  if ($opScript) { & { Invoke-Expression $opScript.Content } }
  else { Say "1Password-stap kon niet worden opgehaald. Draai later de 1Password-regel van de uitlegpagina." }
}
Say ""
Say "Open je Mainframe met 'Mainframe starten' op je bureaublad (of VS Code, map mijn-mainframe) en typ in Claude Code /ophalen."
