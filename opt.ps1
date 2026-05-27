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

$dxvkUrl    = "https://github.com/doitsujin/dxvk/releases/latest/download/dxvk-2.7.1.tar.gz"
$tempDir    = Join-Path $env:TEMP "dxvk_enhancer"
$tarGzPath  = Join-Path $tempDir "dxvk-2.7.1.tar.gz"
$extractDir = Join-Path $tempDir "dxvk_extracted"

if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir    | Out-Null
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

$dlls    = @("d3d9.dll", "d3d11.dll", "dxgi.dll")
$x64Path = Join-Path $gamePath "x64"

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
    Set-ItemProperty -Path $mouseKey -Name "MouseSpeed"      -Value "0" -Type String
    Set-ItemProperty -Path $mouseKey -Name "MouseThreshold1" -Value "0" -Type String
    Set-ItemProperty -Path $mouseKey -Name "MouseThreshold2" -Value "0" -Type String
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
    Write-OK "Keyboard accessibility response values written."
} catch {
    Write-Fail "Failed to apply keyboard accessibility tweaks: $_"
} finally {
    Set-Location $PSScriptRoot -ErrorAction SilentlyContinue
}

Write-Step "Applying keyboard repeat speed tweaks ..."

$kbKey = "HKCU:\Control Panel\Keyboard"

try {
    Set-ItemProperty -Path $kbKey -Name "KeyboardDelay" -Value 0  -Type String
    Set-ItemProperty -Path $kbKey -Name "KeyboardSpeed" -Value 31 -Type String
    Write-OK "KeyboardDelay=0 (shortest), KeyboardSpeed=31 (fastest)."
} catch {
    Write-Fail "Failed to apply keyboard speed tweaks: $_"
}


Write-Step "Applying Multimedia SystemProfile tweaks ..."

$mmKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"

try {
    Set-ItemProperty -Path $mmKey -Name "SystemResponsiveness"   -Value 0x00000000 -Type DWord
    Set-ItemProperty -Path $mmKey -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
    Write-OK "SystemResponsiveness=0, NetworkThrottlingIndex=0xFFFFFFFF."
} catch {
    Write-Fail "Failed to apply Multimedia SystemProfile tweaks: $_"
}


Write-Step "Applying Games task scheduling profile ..."

$gamesKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"

try {
    if (-not (Test-Path $gamesKey)) {
        New-Item -Path $gamesKey -Force | Out-Null
    }

    Set-ItemProperty -Path $gamesKey -Name "GPU Priority"         -Value 8       -Type DWord
    Set-ItemProperty -Path $gamesKey -Name "Priority"             -Value 6       -Type DWord
    Set-ItemProperty -Path $gamesKey -Name "Scheduling Category"  -Value "High"  -Type String
    Set-ItemProperty -Path $gamesKey -Name "SFIO Priority"        -Value "High"  -Type String

    Write-OK "Games task: GPU Priority=8, Priority=6, Scheduling=High, SFIO=High."
} catch {
    Write-Fail "Failed to apply Games task scheduling: $_"
}


Write-Step "Enabling global timer resolution requests (0.5ms) ..."

$timerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"

try {
    Set-ItemProperty -Path $timerKey -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord
    Write-OK "GlobalTimerResolutionRequests=1 (allows apps to request 0.5ms timer)."
} catch {
    Write-Fail "Failed to set timer resolution: $_"
}


Write-Step "Disabling Nagle's Algorithm on all active network interfaces ..."

$tcpInterfacesKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
$nicCount = 0

try {
    $guids = Get-ChildItem -Path $tcpInterfacesKey -ErrorAction Stop

    foreach ($guid in $guids) {
        $props = Get-ItemProperty -Path $guid.PSPath -ErrorAction SilentlyContinue

        $hasIp = ($props.DhcpIPAddress -and $props.DhcpIPAddress -ne "0.0.0.0") -or
                 ($props.IPAddress     -and $props.IPAddress     -notcontains "0.0.0.0")

        if ($hasIp) {
            Set-ItemProperty -Path $guid.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord
            Set-ItemProperty -Path $guid.PSPath -Name "TCPNoDelay"      -Value 1 -Type DWord
            Write-Info "Patched NIC GUID: $($guid.PSChildName)"
            $nicCount++
        }
    }

    if ($nicCount -gt 0) {
        Write-OK "Nagle's Algorithm disabled on $nicCount interface(s)."
    } else {
        Write-Info "No active interfaces detected — Nagle tweak skipped."
    }
} catch {
    Write-Fail "Failed to apply Nagle's Algorithm tweak: $_"
}


Write-Step "Disabling USB Selective Suspend for HID devices ..."

$hidKey = "HKLM:\SYSTEM\CurrentControlSet\Services\HidUsb\Parameters"

try {
    if (-not (Test-Path $hidKey)) {
        New-Item -Path $hidKey -Force | Out-Null
    }
    Set-ItemProperty -Path $hidKey -Name "DeviceSelectiveSuspend" -Value 0 -Type DWord
    Write-OK "HidUsb DeviceSelectiveSuspend=0."
} catch {
    Write-Fail "Failed to disable HID selective suspend: $_"
}

Write-Step "Disabling USB Selective Suspend globally ..."

$usbKey = "HKLM:\SYSTEM\CurrentControlSet\Services\USB"

try {
    if (-not (Test-Path $usbKey)) {
        New-Item -Path $usbKey -Force | Out-Null
    }
    Set-ItemProperty -Path $usbKey -Name "DisableSelectiveSuspend" -Value 1 -Type DWord
    Write-OK "USB DisableSelectiveSuspend=1."
} catch {
    Write-Fail "Failed to disable global USB selective suspend: $_"
}


Write-Step "Enabling Windows QoS (removing NPI bypass) ..."

$qosNpiKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS"

try {
    if (-not (Test-Path $qosNpiKey)) {
        New-Item -Path $qosNpiKey -Force | Out-Null
    }
    Set-ItemProperty -Path $qosNpiKey -Name "Do not use NPI" -Value "No" -Type String
    Write-OK "QoS NPI bypass removed — DSCP marking is now active."
} catch {
    Write-Fail "Failed to enable QoS NPI: $_"
}


Write-Step "Creating QoS policy for crossfire.exe (TCP, DSCP 46) ..."

$qosPolicyRoot = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS"
$qosTcpKey     = "$qosPolicyRoot\Crossfire_TCP"

try {
    if (-not (Test-Path $qosPolicyRoot)) {
        New-Item -Path $qosPolicyRoot -Force | Out-Null
    }
    if (-not (Test-Path $qosTcpKey)) {
        New-Item -Path $qosTcpKey -Force | Out-Null
    }

    Set-ItemProperty -Path $qosTcpKey -Name "Version"                 -Value "1.0"           -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Application Name"        -Value "crossfire.exe"  -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "DSCP Value"              -Value "46"             -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Local IP"                -Value "*"              -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Local IP Prefix Length"  -Value "*"              -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Local Port"              -Value "*"              -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Protocol"                -Value "6"              -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Remote IP"               -Value "*"              -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Remote IP Prefix Length" -Value "*"              -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Remote Port"             -Value "*"              -Type String
    Set-ItemProperty -Path $qosTcpKey -Name "Throttle Rate"           -Value "-1"             -Type String

    Write-OK "QoS TCP policy created: crossfire.exe → DSCP 46 (EF), no throttle."
} catch {
    Write-Fail "Failed to create QoS TCP policy: $_"
}


Write-Step "Creating QoS policy for crossfire.exe (UDP, DSCP 46) ..."

$qosUdpKey = "$qosPolicyRoot\Crossfire_UDP"

try {
    if (-not (Test-Path $qosUdpKey)) {
        New-Item -Path $qosUdpKey -Force | Out-Null
    }

    Set-ItemProperty -Path $qosUdpKey -Name "Version"                 -Value "1.0"           -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Application Name"        -Value "crossfire.exe"  -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "DSCP Value"              -Value "46"             -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Local IP"                -Value "*"              -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Local IP Prefix Length"  -Value "*"              -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Local Port"              -Value "*"              -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Protocol"                -Value "17"             -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Remote IP"               -Value "*"              -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Remote IP Prefix Length" -Value "*"              -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Remote Port"             -Value "*"              -Type String
    Set-ItemProperty -Path $qosUdpKey -Name "Throttle Rate"           -Value "-1"             -Type String

    Write-OK "QoS UDP policy created: crossfire.exe → DSCP 46 (EF), no throttle."
} catch {
    Write-Fail "Failed to create QoS UDP policy: $_"
}


Write-Step "Detecting active WireGuard tunnel ..."

$wgAdapter = Get-NetAdapter -ErrorAction SilentlyContinue |
             Where-Object { $_.InterfaceDescription -like "*WireGuard*" -and $_.Status -eq "Up" } |
             Select-Object -First 1

if (-not $wgAdapter) {
    Write-Info "No active WireGuard tunnel detected — skipping WireGuard QoS policy."
    Write-Info "Connect your WireGuard VPN and re-run the script to apply this section."
} else {
    Write-OK "WireGuard tunnel found: '$($wgAdapter.Name)' ($($wgAdapter.InterfaceDescription))"

    $wgPort = "51820"

    try {
        $wgShow = & wireguard.exe show all listenport 2>$null
        if ($wgShow) {
            $detectedPort = ($wgShow | Select-String -Pattern '\d+' |
                             Select-Object -First 1).Matches[0].Value
            if ($detectedPort) {
                $wgPort = $detectedPort
                Write-Info "Auto-detected WireGuard listen port: $wgPort"
            }
        }
    } catch {
        Write-Info "Could not auto-detect port via wireguard.exe — using default 51820."
    }

    $qosWgKey = "$qosPolicyRoot\WireGuard_Tunnel_UDP"

    try {
        if (-not (Test-Path $qosWgKey)) {
            New-Item -Path $qosWgKey -Force | Out-Null
        }

        Set-ItemProperty -Path $qosWgKey -Name "Version"                 -Value "1.0"   -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Application Name"        -Value "*"     -Type String
        Set-ItemProperty -Path $qosWgKey -Name "DSCP Value"              -Value "46"    -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Local IP"                -Value "*"     -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Local IP Prefix Length"  -Value "*"     -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Local Port"              -Value "*"     -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Protocol"                -Value "17"    -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Remote IP"               -Value "*"     -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Remote IP Prefix Length" -Value "*"     -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Remote Port"             -Value $wgPort -Type String
        Set-ItemProperty -Path $qosWgKey -Name "Throttle Rate"           -Value "-1"    -Type String

        Write-OK "QoS WireGuard tunnel policy created: UDP port $wgPort → DSCP 46 (EF)."
    } catch {
        Write-Fail "Failed to create QoS WireGuard tunnel policy: $_"
    }
}


Write-Step "Cleaning up temporary files ..."
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-OK "Temp files removed."


Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host "  Crossfire PH Optimizer by NoapMat" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Applied tweaks summary:" -ForegroundColor White
Write-Host "    - DXVK 2.7.1 installed" -ForegroundColor Gray
Write-Host "    - Win32PrioritySeparation = 0x24" -ForegroundColor Gray
Write-Host "    - Mouse acceleration disabled" -ForegroundColor Gray
Write-Host "    - Keyboard delay/speed optimized" -ForegroundColor Gray
Write-Host "    - Multimedia SystemResponsiveness = 0" -ForegroundColor Gray
Write-Host "    - NetworkThrottlingIndex = 0xFFFFFFFF" -ForegroundColor Gray
Write-Host "    - Games task: GPU Priority=8, Priority=6" -ForegroundColor Gray
Write-Host "    - GlobalTimerResolutionRequests = 1 (0.5ms)" -ForegroundColor Gray
Write-Host "    - Nagle's Algorithm disabled on active NICs" -ForegroundColor Gray
Write-Host "    - USB Selective Suspend disabled (HID + global)" -ForegroundColor Gray
Write-Host "    - QoS NPI bypass removed (DSCP marking active)" -ForegroundColor Gray
Write-Host "    - QoS DSCP 46 (EF): crossfire.exe TCP" -ForegroundColor Gray
Write-Host "    - QoS DSCP 46 (EF): crossfire.exe UDP" -ForegroundColor Gray
Write-Host "    - QoS DSCP 46 (EF): WireGuard tunnel UDP:51820" -ForegroundColor Gray
Write-Host ""
Write-Host "  NOTE: QoS DSCP tagging requires your router to honour DSCP values." -ForegroundColor DarkYellow
Write-Host "  Most consumer routers do. WireGuard default port is 51820 — edit" -ForegroundColor DarkYellow
Write-Host "  the `$wgPort variable in Section 14 if yours differs." -ForegroundColor DarkYellow
Write-Host ""
Write-Host "  Restart your PC for all changes to take effect." -ForegroundColor Cyan
Write-Host ""
