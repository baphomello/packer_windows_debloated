# Windows 11 24H2 turns device encryption on by itself during OOBE of a clean
# install, and sysprep then refuses the image outright:
#
#   SYSPRP BitLocker-Sysprep: BitLocker is on for the OS volume. (0x80310039)
#
# That refusal is invisible from the build console, so it costs a whole run.
# The answer file asks Windows not to encrypt in the first place, but that is a
# community-documented registry value rather than a supported setting, so the
# volume is checked here as well. Encryption is also pure overhead on an image
# whose point is speed, and no clone of it would keep the protectors anyway.

$mount = $env:SystemDrive

# The answer file sets this before OOBE for this build; written again here so it
# is in the image, where every clone inherits it and skips encryption in turn.
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'
if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -LiteralPath $key -Name 'PreventDeviceEncryption' -Value 1 -PropertyType DWord -Force | Out-Null

# Windows Home ships no BitLocker module, and -ErrorAction does not suppress a
# command that does not resolve at all, so the guard has to come first. Not
# being able to look is not a reason to fail a build: the answer file is what
# stops the encryption, and this is the net under it.
if (-not (Get-Command 'Get-BitLockerVolume' -ErrorAction SilentlyContinue)) {
    Write-Output 'No BitLocker cmdlets on this edition; relying on the answer file to have prevented encryption.'
    exit 0
}

$volume = Get-BitLockerVolume -MountPoint $mount -ErrorAction SilentlyContinue
if (-not $volume) {
    Write-Output "No BitLocker status for ${mount}; nothing to decrypt."
    exit 0
}

if ($volume.VolumeStatus -eq 'FullyDecrypted') {
    Write-Output "${mount} is not encrypted."
    exit 0
}

Write-Output "${mount} is $($volume.VolumeStatus) at $($volume.EncryptionPercentage)%, decrypting."
try {
    Disable-BitLocker -MountPoint $mount -ErrorAction Stop | Out-Null
} catch {
    Write-Output "Disable-BitLocker refused: $(($_.Exception.Message -replace '\s+', ' ').Trim())"
}

# Decryption runs in the background and sysprep is close behind, so the build
# waits for it here rather than discovering the state too late to report it.
$deadline = (Get-Date).AddMinutes(60)
$lastReported = -1
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    $volume = Get-BitLockerVolume -MountPoint $mount -ErrorAction SilentlyContinue
    if (-not $volume -or $volume.VolumeStatus -eq 'FullyDecrypted') {
        Write-Output "${mount} is decrypted."
        exit 0
    }
    if ([math]::Abs($volume.EncryptionPercentage - $lastReported) -ge 10) {
        $lastReported = $volume.EncryptionPercentage
        Write-Output "  $($volume.VolumeStatus) $($volume.EncryptionPercentage)%"
    }
}

Write-Output "${mount} is still $($volume.VolumeStatus) after 60 minutes; sysprep will refuse it."
exit 1
