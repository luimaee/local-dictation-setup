<#
.SYNOPSIS
    Sets Handy's transcribe hotkey and autostart by patching settings_store.json.

.DESCRIPTION
    Handy stores all settings in one JSON file, so config is scriptable. Two
    things will silently destroy that file if you get them wrong, and this
    script handles both:

      1. A UTF-8 BOM makes Handy's parser reject the file and fall back to
         defaults - wiping your selected model and everything else. PowerShell
         5's `Set-Content -Encoding UTF8` writes a BOM. This script writes
         UTF-8 without one and verifies the first byte afterwards.

      2. Handy holds settings in memory and writes on exit, so edits made while
         it is running get overwritten. This script stops Handy first.

    A timestamped backup is taken before any write.

.PARAMETER Hotkey
    Binding string, lowercase tokens joined by '+'. Modifier-only bindings are
    supported and are the nicest option for push-to-talk.
    Examples: 'ctrl+win', 'ctrl+alt+space', 'ctrl+shift+space'

.PARAMETER Autostart
    Launch Handy at login. Registers under HKCU:\...\CurrentVersion\Run.

.PARAMETER NoRelaunch
    Leave Handy closed when done.

.EXAMPLE
    .\configure-handy.ps1 -Hotkey 'ctrl+win' -Autostart

.EXAMPLE
    .\configure-handy.ps1 -Hotkey 'ctrl+alt+space'
#>

[CmdletBinding()]
param(
    [string]$Hotkey = 'ctrl+win',
    [switch]$Autostart,
    [switch]$NoRelaunch
)

$ErrorActionPreference = 'Stop'

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "    $m" -ForegroundColor Yellow }

$settings = Join-Path $env:APPDATA 'com.pais.handy\settings_store.json'
$exe      = Join-Path $env:LOCALAPPDATA 'Handy\handy.exe'
$log      = Join-Path $env:LOCALAPPDATA 'com.pais.handy\logs\handy.log'

if (-not (Test-Path $settings)) {
    throw "No settings file at $settings. Launch Handy once and finish onboarding first."
}

Write-Step 'Stopping Handy'
Stop-Process -Name handy -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
if (Get-Process handy -ErrorAction SilentlyContinue) {
    throw 'Handy is still running. Close it manually and re-run.'
}
Write-Ok 'Stopped.'

Write-Step 'Backing up'
$backup = "$settings.$(Get-Date -Format yyyyMMdd-HHmmss).bak"
Copy-Item $settings $backup -Force
Write-Ok $backup

Write-Step 'Patching settings'

$text = [IO.File]::ReadAllText($settings)

# Read the current binding out of the transcribe block so we can replace it
# without a JSON round-trip (which risks re-encoding the whole file).
$m = [regex]::Match(
    $text,
    '"transcribe"\s*:\s*\{(?:[^{}]|\{[^{}]*\})*?"current_binding"\s*:\s*"(?<val>[^"]*)"'
)
if (-not $m.Success) { throw 'Could not locate the transcribe binding in settings_store.json.' }

$current = $m.Groups['val'].Value
if ($current -eq $Hotkey) {
    Write-Ok "Hotkey already '$Hotkey'."
} else {
    $idx  = $m.Groups['val'].Index
    $len  = $m.Groups['val'].Length
    $text = $text.Substring(0, $idx) + $Hotkey + $text.Substring($idx + $len)
    Write-Ok "Hotkey: '$current' -> '$Hotkey'"
}

if ($Autostart) {
    if ($text -match '"autostart_enabled"\s*:\s*false') {
        $text = $text -replace '"autostart_enabled"\s*:\s*false', '"autostart_enabled": true'
        Write-Ok 'Autostart: enabled'
    } else {
        Write-Ok 'Autostart: already enabled'
    }
}

# UTF-8, no BOM. This is the part that matters.
[IO.File]::WriteAllText($settings, $text, (New-Object System.Text.UTF8Encoding($false)))

$bytes = [IO.File]::ReadAllBytes($settings)
if ($bytes[0] -ne 123) {
    Copy-Item $backup $settings -Force
    throw "Wrote a BOM or bad first byte ($($bytes[0])). Restored backup. Aborting."
}
Write-Ok 'Written as UTF-8 without BOM.'

# Confirm it still parses and the model survived.
$parsed = Get-Content $settings -Raw | ConvertFrom-Json
if (-not $parsed.settings.selected_model) {
    Write-Warn 'selected_model is empty - you will need to pick a model again.'
}

if ($NoRelaunch) {
    Write-Step 'Done (not relaunching)'
    return
}

Write-Step 'Relaunching and verifying'

if (Test-Path $log) { Clear-Content $log -ErrorAction SilentlyContinue }
Start-Process $exe
Start-Sleep -Seconds 15

$after = (Get-Content $settings -Raw | ConvertFrom-Json).settings
$bound = $after.bindings.transcribe.current_binding

if ($bound -ne $Hotkey) {
    Write-Warn "Handy reverted the hotkey to '$bound'."
    Write-Warn "'$Hotkey' is probably not a valid binding string. Try 'ctrl+alt+space'."
} else {
    Write-Ok "Hotkey holding: $bound"
}

if (Test-Path $log) {
    $reg = Select-String -Path $log -Pattern 'Registered handy-keys shortcut: transcribe' |
           Select-Object -Last 1 -ExpandProperty Line
    if ($reg) { Write-Ok ($reg -replace '^\[.*?\]\[.*?\]\[.*?\]\s*', '') }
}

if ($Autostart) {
    $run = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).Handy
    if ($run) { Write-Ok "Autostart registered: $run" }
    else      { Write-Warn 'Autostart flag set but no Run key found.' }
}

Write-Host ''
Write-Host "    Test it: click into any text box, hold $Hotkey, talk, release." -ForegroundColor Cyan
Write-Host ''
