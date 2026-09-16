<#
.SYNOPSIS
    Installs Handy (local speech-to-text) on Windows and reports the hardware
    and compute backends it will actually use.

.DESCRIPTION
    Wraps `winget install cjpais.Handy`, which pulls the Vulkan runtime and
    VC++ redistributable as dependencies. Then launches Handy and reads its log
    to tell you whether GPU acceleration is available, so you can pick a model
    that suits the machine.

    Does not require admin. Installs per-user to %LOCALAPPDATA%\Handy.

.EXAMPLE
    .\install-handy.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipLaunch
)

$ErrorActionPreference = 'Stop'

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "    $m" -ForegroundColor Yellow }

Write-Step 'Checking prerequisites'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
}
Write-Ok "winget: $((Get-Command winget).Source)"

$os = (Get-CimInstance Win32_OperatingSystem).Caption
Write-Ok "OS: $os ($env:PROCESSOR_ARCHITECTURE)"

Write-Step 'Reporting hardware'

$gpus = Get-CimInstance Win32_VideoController
foreach ($g in $gpus) { Write-Ok "GPU: $($g.Name)" }
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Write-Ok "RAM: $ramGB GB"

$hasDiscreteGpu = $gpus | Where-Object { $_.Name -match 'NVIDIA|Radeon|Arc' }

Write-Step 'Installing Handy via winget'
Write-Warn 'This also installs the Vulkan runtime and VC++ redistributable.'

winget install --id cjpais.Handy -e --source winget `
    --accept-source-agreements --disable-interactivity

if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
    throw "winget exited with code $LASTEXITCODE"
}

$exe = Join-Path $env:LOCALAPPDATA 'Handy\handy.exe'
if (-not (Test-Path $exe)) {
    throw "Install finished but $exe is missing."
}
Write-Ok "Installed: $exe"

if ($SkipLaunch) {
    Write-Step 'Done (launch skipped)'
    return
}

Write-Step 'Launching Handy and checking compute backends'

Start-Process $exe
Start-Sleep -Seconds 12

$log = Join-Path $env:LOCALAPPDATA 'com.pais.handy\logs\handy.log'
if (Test-Path $log) {
    $backends = Select-String -Path $log -Pattern 'compute device\(s\) registered' |
                Select-Object -Last 1 -ExpandProperty Line
    if ($backends) {
        if ($backends -match 'Vulkan') {
            Write-Ok 'Vulkan backend registered - GPU acceleration is available.'
        } else {
            Write-Warn 'CPU only - no Vulkan backend. Expect slower transcription.'
        }
    }

    $vk = Select-String -Path $log -Pattern 'ggml_vulkan: \d+ = ' |
          Select-Object -Last 1 -ExpandProperty Line
    if ($vk) { Write-Ok ($vk -replace '^.*ggml_vulkan: ', 'Vulkan device: ') }
} else {
    Write-Warn "No log yet at $log"
}

Write-Step 'Next: pick a model in the Handy window'

if ($hasDiscreteGpu) {
    Write-Host '    Recommended: Cohere Transcribe (1.6 GB, highest accuracy).'
    Write-Host '    Its "slower" label assumes CPU - your GPU handles it fine.'
} else {
    Write-Host '    Recommended: Parakeet Unified EN 0.6B (697 MB).'
    Write-Host '    No discrete GPU detected, so avoid Cohere and Whisper Medium/Large.'
}

Write-Host ''
Write-Host '    Then set a hotkey. The Ctrl+Space default collides with' -ForegroundColor Yellow
Write-Host '    autocomplete in VS Code, Cursor and JetBrains IDEs.' -ForegroundColor Yellow
Write-Host '    Run configure-handy.ps1 to set a modifier-only binding.'
Write-Host ''
