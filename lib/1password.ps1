# 1password.ps1 - fase 2: 1Password koppelen aan je Mainframe (Windows).
# Een regel in een gewone PowerShell (niet in Claude Code):
#
#   irm https://raw.githubusercontent.com/slimwerken/mainframe-enterprise/main/lib/1password.ps1 | iex
#
# Doet: 1Password CLI (op) erop als hij ontbreekt, zorgt dat Windows hem vindt, maakt het
# knop "Mainframe starten" (opent VS Code met je sleutels uit 1Password) en test de koppeling.
# Werkt ook als PowerShell in de beperkte stand draait (WDAC/Intune): geen .NET-aanroepen.
# Daarna in Claude Code: /kluis (zet je sleutels uit ik/.env in 1Password).
$ErrorActionPreference = "Continue"
function Say($m) { Write-Host "  $m" }

function VerversPad {
  $m = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name Path -ErrorAction SilentlyContinue).Path
  $u = (Get-ItemProperty "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
  $env:Path = "$m;$u"
}
function ZetInPad($map) {
  $u = (Get-ItemProperty "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
  if (-not $u) { $u = "" }
  $delen = $u -split ";" | Where-Object { $_ -ne "" }
  if ($delen -notcontains $map) {
    Set-ItemProperty "HKCU:\Environment" -Name Path -Value ((@($delen) + $map) -join ";")
  }
  VerversPad
}
function Heeft($naam) { return [bool](Get-Command $naam -ErrorAction SilentlyContinue) }

# 1. De 1Password-app. Die moet er eerst op (via het Bedrijfsportal of de IT-partner).
$app = @(
  (Join-Path $env:LOCALAPPDATA "1Password\app\8\1Password.exe"),
  (Join-Path $env:ProgramFiles "1Password\app\8\1Password.exe")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $app -and -not $env:MF_OP_ZONDER_APP -and (Heeft "winget")) {
  # Eerst zelf proberen; lukt het niet (IT houdt het tegen), dan via het Bedrijfsportal.
  Say "De 1Password-app installeren. Vraagt Windows om toestemming? Klik op Ja."
  & winget install -e --id AgileBits.1Password --silent --accept-package-agreements --accept-source-agreements | Out-Null
  $app = @(
    (Join-Path $env:LOCALAPPDATA "1Password\app\8\1Password.exe"),
    (Join-Path $env:ProgramFiles "1Password\app\8\1Password.exe")
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($app) { Say "1Password-app staat erop. Open hem en log in met je uitnodiging uit de mail." }
}
if (-not $app -and -not $env:MF_OP_ZONDER_APP) {
  Say "De 1Password-app staat nog niet op deze laptop."
  Say "Installeer hem via het Bedrijfsportal (Company Portal), of vraag de IT-partner."
  Say "Log in met je uitnodiging van 1Password en draai daarna de 1Password-regel van de uitlegpagina."
  return
}
if ($app) { Say "1Password-app gevonden." }

# 2. 1Password CLI (op).
if (-not (Heeft "op")) {
  if (-not (Heeft "winget")) { Say "Winget ontbreekt. Vraag de IT-partner om 1Password CLI te installeren."; return }
  Say "1Password CLI installeren. Vraagt Windows om toestemming? Klik op Ja."
  & winget install -e --id AgileBits.1Password.CLI --silent --accept-package-agreements --accept-source-agreements | Out-Null
  VerversPad
}
if (-not (Heeft "op")) {
  # Winget zet hem soms in een map die nog niet in het pad staat.
  $gevonden = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet") -Recurse -Filter op.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $gevonden) {
    $gevonden = Get-ChildItem $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA "Programs") -Recurse -Filter op.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  }
  if ($gevonden) { ZetInPad $gevonden.DirectoryName }
}
if (-not (Heeft "op")) {
  Say "1Password CLI lukte niet. Houdt de laptop hem tegen? Vraag de IT-partner om 1Password CLI (AgileBits.1Password.CLI) toe te staan."
  return
}
$versie = & op --version 2>$null
Say "1Password CLI staat erop (versie $versie)."

# 3. Het commando "mainframe": opent VS Code met je sleutels uit 1Password. Alles wat daarin
# start (Claude Code, scripts) krijgt dan de echte sleutels in plaats van de op://-verwijzing.
# VS Code moet daarvoor eerst helemaal dicht: een al geopend VS Code houdt zijn oude instellingen.
$dir = $env:MF_DIR
if (-not $dir) {
  $kandidaten = @((Get-Location).Path, (Join-Path $HOME "mijn-mainframe"), (Join-Path $HOME "qdp-mainframe"))
  $dir = $kandidaten | Where-Object { Test-Path (Join-Path $_ "ik") } | Select-Object -First 1
}
if (-not $dir) {
  Say "Je Mainframe-map niet gevonden. Ga in PowerShell eerst naar je map (cd <map>) en draai de regel opnieuw."
  return
}
# 1Password CLI leest geen .env met een BOM vooraan (QDP, 7 okt 2026: "expected '=' at line 1").
$envPad = Join-Path $dir "ik\.env"
if (Test-Path $envPad) {
  $kop = Get-Content -Encoding Byte -TotalCount 3 -Path $envPad -ErrorAction SilentlyContinue
  if ($kop -and $kop.Count -eq 3 -and $kop[0] -eq 239 -and $kop[1] -eq 187 -and $kop[2] -eq 191) {
    $inhoud = Get-Content -Raw -Encoding UTF8 -Path $envPad
    Set-Content -Path $envPad -Value $inhoud -Encoding Ascii -NoNewline
    Say "ik\.env opgeschoond (onzichtbaar teken vooraan weggehaald)."
  }
}
$bin = Join-Path $HOME ".mainframe\bin"
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$cmd = @(
  "@echo off",
  "tasklist /fi `"imagename eq Code.exe`" 2>nul | find /i `"Code.exe`" >nul",
  "if not errorlevel 1 (",
  "  echo.",
  "  echo   VS Code staat nog open. Sluit VS Code helemaal en start dit opnieuw.",
  "  echo.",
  "  pause",
  "  exit /b 1",
  ")",
  "cd /d `"$dir`"",
  "if not exist ik\.env type nul > ik\.env",
  "echo   Mainframe openen met je sleutels uit 1Password...",
  "op run --env-file=ik\.env -- code `"$dir`""
)
Set-Content -Path (Join-Path $bin "mainframe.cmd") -Value $cmd -Encoding Ascii
ZetInPad $bin
# Ook op het bureaublad, om op te dubbelklikken. Het bureaublad kan in OneDrive staan.
$bureau = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop -ErrorAction SilentlyContinue).Desktop
if ($bureau) { $bureau = $bureau -replace "%USERPROFILE%", $env:USERPROFILE } else { $bureau = Join-Path $HOME "Desktop" }
if (Test-Path $bureau) {
  Set-Content -Path (Join-Path $bureau "Mainframe starten.cmd") -Value $cmd -Encoding Ascii
  Say "Op je bureaublad staat nu: Mainframe starten"
}
Say "Commando 'mainframe' gemaakt voor $dir"

# 4. Werkt de koppeling met de app?
& op vault list 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Say ""
  Say "Nog een ding in de 1Password-app: Instellingen > Ontwikkelaar (Developer) >"
  Say "zet 'Integrate with 1Password CLI' aan. Laat de app open en ontgrendeld."
  Say "Draai daarna de 1Password-regel van de uitlegpagina."
  return
}
Say "1Password is gekoppeld. Je kluizen:"
& op vault list
Say ""
Say "1Password is klaar. Sluit VS Code helemaal en open je Mainframe voortaan met 'Mainframe starten'."
Say "Heb je al eigen sleutels in je Mainframe? Typ dan in Claude Code: /kluis"
