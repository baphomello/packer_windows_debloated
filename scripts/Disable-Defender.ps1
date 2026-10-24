# Defender is the single biggest source of CPU and IO on an image like this: it
# rescans every payload update and every file the payload writes. What is
# reachable from a script is done here; what is not is reported, not pretended.
#
# Tamper protection is on by default on a fresh Windows 11 install and has no
# supported script path: Defender's own ELAM driver reverts writes to the value
# while it is running, whatever privileges the writer holds. Both the write and
# the service start types are attempted anyway and the result is printed, so the
# build log says what the state really is instead of what was intended.
#
# What does stick on an unmanaged machine is exclusions, including one for the
# whole system drive, which takes Defender off the IO path even with tamper
# protection on. That is the layer this image actually relies on.

if ($env:DisableDefender -ne 'true') {
    Write-Output 'disable_defender is false, leaving Defender alone.'
    exit 0
}

function Set-RegValue {
    param([string] $Path, [string] $Name, $Value, [string] $Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

$def = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'

Set-RegValue -Path $def -Name 'DisableAntiSpyware' -Value 1
Set-RegValue -Path $def -Name 'DisableAntiVirus' -Value 1
Set-RegValue -Path $def -Name 'PUAProtection' -Value 0
Set-RegValue -Path $def -Name 'DisableRoutinelyTakingAction' -Value 1

foreach ($name in @(
    'DisableRealtimeMonitoring', 'DisableBehaviorMonitoring', 'DisableOnAccessProtection',
    'DisableScanOnRealtimeEnable', 'DisableIOAVProtection', 'DisableScriptScanning'
)) {
    Set-RegValue -Path "$def\Real-Time Protection" -Name $name -Value 1
}

Set-RegValue -Path "$def\Spynet" -Name 'SpynetReporting' -Value 0
Set-RegValue -Path "$def\Spynet" -Name 'SubmitSamplesConsent' -Value 2
Set-RegValue -Path "$def\Spynet" -Name 'DisableBlockAtFirstSeen' -Value 1
Set-RegValue -Path "$def\Scan" -Name 'DisableScanningNetworkFiles' -Value 1
Set-RegValue -Path "$def\Reporting" -Name 'DisableEnhancedNotifications' -Value 1

try {
    Set-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' `
        -Name 'TamperProtection' -Value 0 -ErrorAction Stop
} catch {
    Write-Output "TamperProtection value not written: $($_.Exception.Message)"
}

# An exclusion for the system drive is what actually takes Defender off the IO
# path when real-time protection cannot be switched off. Copy-Payload.ps1 adds
# one for the payload directory as well.
try {
    Add-MpPreference -ExclusionPath 'C:\' -ErrorAction Stop
} catch {
    Write-Output "Drive exclusion not applied: $($_.Exception.Message)"
}

foreach ($pref in @(
    @{ DisableRealtimeMonitoring = $true },
    @{ DisableBehaviorMonitoring = $true },
    @{ DisableBlockAtFirstSeen = $true },
    @{ MAPSReporting = 0 },
    @{ SubmitSamplesConsent = 2 },
    @{ ScanScheduleDay = 8 },
    @{ DisableArchiveScanning = $true }
)) {
    try {
        Set-MpPreference @pref -ErrorAction Stop
    } catch {
        Write-Output "Set-MpPreference $($pref.Keys) refused: $($_.Exception.Message)"
    }
}

# The tray agent and its autorun are not protected
Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
    -Name 'SecurityHealth' -ErrorAction SilentlyContinue
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray' `
    -Name 'HideSystray' -Value 1

foreach ($name in @(
    'Windows Defender Cache Maintenance', 'Windows Defender Cleanup',
    'Windows Defender Scheduled Scan', 'Windows Defender Verification'
)) {
    try {
        Disable-ScheduledTask -TaskPath '\Microsoft\Windows\Windows Defender\' -TaskName $name -ErrorAction Stop | Out-Null
    } catch {
        Write-Output "Task not disabled: ${name}"
    }
}

foreach ($name in @('WinDefend', 'WdNisSvc', 'Sense', 'SecurityHealthService', 'wscsvc', 'WdFilter', 'WdBoot', 'WdNisDrv')) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (-not (Test-Path -LiteralPath $key)) { continue }
    try {
        Set-ItemProperty -LiteralPath $key -Name 'Start' -Value 4 -ErrorAction Stop
        Write-Output "Start type disabled for ${name}."
    } catch {
        Write-Output "Start type refused for ${name} (expected for the protected ones)."
    }
}

try {
    $status = Get-MpComputerStatus -ErrorAction Stop
    Write-Output "Defender after changes -> AntivirusEnabled=$($status.AntivirusEnabled) RealTimeProtectionEnabled=$($status.RealTimeProtectionEnabled) IsTamperProtected=$($status.IsTamperProtected)"
    Write-Output "Exclusion paths: $((Get-MpPreference).ExclusionPath -join ', ')"
} catch {
    Write-Output "Get-MpComputerStatus unavailable: $($_.Exception.Message)"
}

exit 0
