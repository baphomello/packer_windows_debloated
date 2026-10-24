# Defender rescans every file the payload reads and writes, which is the single
# biggest IO cost on an image like this. On Windows 11 with tamper protection on
# - the default on a fresh install - turning the service or real-time protection
# off is not scriptable: Defender's own ELAM driver reverts those writes while it
# runs. A full-drive exclusion IS honoured, and it takes Defender off the IO path
# all the same, which is the performance the image is after.
#
# Kept deliberately small for a reason. A script that also carries the real-time,
# tamper and service-start writes matches an antimalware signature and is refused
# at parse time, which takes the exclusion down with it. Tamper protection
# reverts those writes anyway, so nothing of value is lost by leaving them out.
# The DisableAntiSpyware policy that still has any effect is set in the answer
# file's specialize pass instead, before Defender's first run.

if ($env:DisableDefender -ne 'true') {
    Write-Output 'disable_defender is false, leaving Defender alone.'
    exit 0
}

# The system drive. This is what keeps Defender out of the IO path for everything
# the payload touches. Copy-Payload.ps1 adds the payload directory as well.
try {
    Add-MpPreference -ExclusionPath 'C:\' -ErrorAction Stop
    Write-Output 'Added exclusion for C:\.'
} catch {
    Write-Output "Drive exclusion not applied: $($_.Exception.Message)"
}

# Routine scans and maintenance are pure IO on a disposable VM. These tasks are
# not tamper protected and stay disabled.
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

# Reported, never asserted: tamper protection owns these, so the build should say
# what the machine really ends in rather than what was intended.
try {
    $status = Get-MpComputerStatus -ErrorAction Stop
    Write-Output "Defender -> RealTimeProtection=$($status.RealTimeProtectionEnabled) TamperProtected=$($status.IsTamperProtected)"
    Write-Output "Exclusions: $((Get-MpPreference).ExclusionPath -join ', ')"
} catch {
    Write-Output "Get-MpComputerStatus unavailable: $($_.Exception.Message)"
}

exit 0
