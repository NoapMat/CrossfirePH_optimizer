#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Crossfire PH Performance Enhancer by NoapMat
.DESCRIPTION
    Applies perf boost, registry tweaks, and input optimizations for Crossfire PH.
#>

function Write-Step  { param($msg) Write-Host "    [*] $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Fail  { param($msg) Write-Host "    [!!] $msg" -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "    [-] $msg"  -ForegroundColor Gray }

$gamePath = $null

while ($true) {
    Write-Host ""
    $gamePath = Read-Host "Enter the absolute path of your Crossfire PH installation (e.g. C:\Program Files (x86)\Crossfire PH)"
    $gamePath = $gamePath.Trim('"').Trim("'").TrimEnd('\')

    if (-not (Test-Path $gamePath -PathType Container)) {
        Write-Fail "Path does not exist or is not a directory. Please try again."
        continue
    }

    $patcherPath = Join-Path $gamePath "patcher_cf2.exe"
    if (-not (Test-Path $patcherPath -PathType Leaf)) {
        Write-Fail "The directory isn't Crossfire PH. Please try again."
        continue
    }

    Write-OK "Valid Crossfire PH directory detected: $gamePath"
    break
}

Write-Step "Downloading DXVK 2.7.1 ..."

$dxvkUrl      = "https://github.com/doitsujin/dxvk/releases/latest/download/dxvk-2.7.1.tar.gz"
$tempDir      = Join-Path $env:TEMP "dxvk_enhancer"
$tarGzPath    = Join-Path $tempDir "dxvk-2.7.1.tar.gz"
$extractDir   = Join-Path $tempDir "dxvk_extracted"

if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir  | Out-Null
New-Item -ItemType Directory -Path $extractDir | Out-Null

try {
    Write-Info "Saving to $tarGzPath ..."
    Invoke-WebRequest -Uri $dxvkUrl -OutFile $tarGzPath -UseBasicParsing
    Write-OK "Download complete."
} catch {
    Write-Fail "Download failed: $_"
    exit 1
}

Write-Step "Extracting archive ..."

try {
    & tar.exe -xzf $tarGzPath -C $extractDir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "tar exited with code $LASTEXITCODE" }
    Write-OK "Extraction successful."
} catch {
    Write-Fail "Extraction failed: $_"
    exit 1
}

$x32Dir = Get-ChildItem -Path $extractDir -Recurse -Directory -Filter "x32" |
          Select-Object -First 1

if (-not $x32Dir) {
    Write-Fail "Could not locate x32 folder inside the archive."
    exit 1
}

Write-Info "Found x32 folder: $($x32Dir.FullName)"

Write-Step "Copying DXVK DLLs ..."

$dlls     = @("d3d9.dll", "d3d11.dll", "dxgi.dll")
$x64Path  = Join-Path $gamePath "x64"

if (-not (Test-Path $x64Path -PathType Container)) {
    Write-Info "Creating missing x64 subfolder: $x64Path"
    New-Item -ItemType Directory -Path $x64Path | Out-Null
}

foreach ($dll in $dlls) {
    $src = Join-Path $x32Dir.FullName $dll

    if (-not (Test-Path $src -PathType Leaf)) {
        Write-Fail "Source DLL not found in archive: $dll (skipping)"
        continue
    }

    Write-Info "Copying $dll → $gamePath"
    Copy-Item -Path $src -Destination (Join-Path $gamePath $dll) -Force

    Write-Info "Copying $dll → $x64Path"
    Copy-Item -Path $src -Destination (Join-Path $x64Path $dll) -Force
}

Write-OK "DLLs copied successfully."

Write-Step "Creating System Restore Point: 'before regedits' ..."

try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue

    Checkpoint-Computer `
        -Description "before regedits" `
        -RestorePointType "MODIFY_SETTINGS" `
        -ErrorAction Stop

    Write-OK "Restore point created."
} catch {
    Write-Fail "Could not create restore point: $_"
    Write-Info "Continuing anyway ..."
}

Write-Step "Setting Win32PrioritySeparation to 36 (0x24) ..."

$prioKey  = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
$prioName = "Win32PrioritySeparation"

try {
    Set-ItemProperty -Path $prioKey -Name $prioName -Value 0x00000024 -Type DWord -ErrorAction Stop
    $verify = (Get-ItemProperty -Path $prioKey -Name $prioName).$prioName
    Write-OK "Win32PrioritySeparation set to $verify (decimal) / 0x$('{0:X8}' -f $verify) (hex)"
} catch {
    Write-Fail "Failed to set Win32PrioritySeparation: $_"
}


Write-Step "Disabling mouse hardware acceleration ..."

$mouseKey = "HKCU:\Control Panel\Mouse"

try {
    Set-ItemProperty -Path $mouseKey -Name "MouseSpeed"      -Value "0"  -Type String
    Set-ItemProperty -Path $mouseKey -Name "MouseThreshold1" -Value "0"  -Type String
    Set-ItemProperty -Path $mouseKey -Name "MouseThreshold2" -Value "0"  -Type String

    Write-OK "Mouse hardware acceleration disabled."
} catch {
    Write-Fail "Failed to disable mouse acceleration: $_"
}

Write-Step "Applying keyboard response / accessibility tweaks ..."

try {
    Set-Location "HKCU:\Control Panel\Accessibility\Keyboard Response"
    Set-ItemProperty -Path . -Name AutoRepeatDelay       -Value 150
    Set-ItemProperty -Path . -Name AutoRepeatRate        -Value 25
    Set-ItemProperty -Path . -Name DelayBeforeAcceptance -Value 0
    Set-ItemProperty -Path . -Name BounceTime            -Value 0
    Set-ItemProperty -Path . -Name Flags                 -Value 47

    Write-OK "Keyboard response values written."
} catch {
    Write-Fail "Failed to apply keyboard tweaks: $_"
} finally {
    Set-Location $PSScriptRoot -ErrorAction SilentlyContinue
}

Write-Step "Cleaning up temporary files ..."
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-OK "Temp files removed."

Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host "  Crossfire PH optimizer by NoapMat" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Restart your PC for all changes to take effect." -ForegroundColor Cyan
Write-Host ""
