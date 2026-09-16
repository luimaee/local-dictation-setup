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

# What matters is FREE VRAM right now, not the card's total. A desktop full of
# browsers and Electron apps can leave a 6 GB card with barely 1 GB usable, and
# an oversized model then spills to system RAM - fast on short test phrases,
# catastrophic on real sentences.
$freeVramMB = $null
$nvidiaSmi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
if (Test-Path $nvidiaSmi) {
    try {
        $freeVramMB = [int]((& $nvidiaSmi --query-gpu=memory.free --format=csv,noheader,nounits |
                             Select-Object -First 1).Trim())
        Write-Ok "Free VRAM right now: $freeVramMB MiB"
    } catch {
        Write-Warn 'Could not read free VRAM from nvidia-smi.'
    }
}

if ($null -ne $freeVramMB -and $freeVramMB -ge 3000) {
    Write-Host '    Recommended: Cohere Transcribe (1.6 GB, highest accuracy).'
    Write-Host '    You have enough free VRAM for it with headroom.'
}
elseif ($null -ne $freeVramMB) {
    Write-Host '    Recommended: Parakeet Unified EN 0.6B (697 MB).'
    Write-Warn "Only $freeVramMB MiB of VRAM is free - Cohere Transcribe (1.6 GB)"
    Write-Warn '    would spill to system RAM. It would feel fast on short test'
    Write-Warn '    phrases and then crawl on real sentences.'
    Write-Host '    Closing browsers frees VRAM if you want the bigger model.'
}
elseif ($hasDiscreteGpu) {
    Write-Host '    Discrete GPU found, but free VRAM is unknown.'
    Write-Host '    Start with Parakeet Unified EN 0.6B (697 MB) - it fits anywhere.'
    Write-Host '    Move up to Cohere Transcribe only if 3 GB+ of VRAM is free.'
}
else {
    Write-Host '    Recommended: Parakeet Unified EN 0.6B (697 MB).'
    Write-Host '    No discrete GPU detected, so avoid Cohere and Whisper Medium/Large.'
}

Write-Host ''
Write-Host '    Check your speed in the log after a few real sentences:' -ForegroundColor Cyan
Write-Host '      Transcription completed in X for Y of audio (Z real-time)'
Write-Host '    Below 1.0x means the model is too big for your free VRAM.'

Write-Host ''
Write-Host '    Then set a hotkey. The Ctrl+Space default collides with' -ForegroundColor Yellow
Write-Host '    autocomplete in VS Code, Cursor and JetBrains IDEs.' -ForegroundColor Yellow
Write-Host '    Run configure-handy.ps1 to set a modifier-only binding.'
Write-Host ''
