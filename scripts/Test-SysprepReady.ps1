# Sysprep runs from Packer's shutdown command, and the Hyper-V builder throws
# away everything that command prints. A refusal there costs a whole build and
# says nothing, so whatever can be looked at beforehand is looked at here, in a
# provisioner whose output the console does show.
#
# This reports and never removes. An appx package that looks like a blocker can
# also be one the payload needs, and guessing wrong on the last step before
# shutdown is worse than a build that stops with the name printed.

if ($env:Generalize -ne 'true') {
    Write-Output 'generalize is false, sysprep will not run.'
    exit 0
}

foreach ($needed in @('C:\Windows\System32\Sysprep\sysprep.exe', 'C:\Windows\Panther\sysprep-unattend.xml')) {
    if (Test-Path -LiteralPath $needed) {
        Write-Output "present: ${needed}"
    } else {
        Write-Output "MISSING: ${needed} - sysprep cannot run without it"
    }
}

# The refusal that actually cost a build: 24H2 encrypts the OS volume by
# itself, and sysprep will not generalize one. Disable-DriveEncryption.ps1 runs
# before this and should already have dealt with it.
$blv = $null
if (Get-Command 'Get-BitLockerVolume' -ErrorAction SilentlyContinue) {
    $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
}
if ($blv -and $blv.VolumeStatus -ne 'FullyDecrypted') {
    Write-Output "BLOCKER: $($env:SystemDrive) is $($blv.VolumeStatus) - sysprep refuses an encrypted OS volume (0x80310039)"
} else {
    Write-Output "OS volume encryption: none"
}

# The generalize pass refuses a package that is installed for a user but not
# provisioned for all users, and fails with 0x80073cf2. Removing appx packages
# is exactly how an image ends up in that state, so the mismatch is listed.
$provisioned = @()
try {
    $provisioned = @(Get-AppxProvisionedPackage -Online | Select-Object -ExpandProperty DisplayName)
} catch {
    Write-Output "Provisioned packages unreadable: $(($_.Exception.Message -replace '\s+', ' ').Trim())"
}

$orphans = @()
try {
    $orphans = @(
        Get-AppxPackage -AllUsers |
            Where-Object { -not $_.IsFramework -and $provisioned -notcontains $_.Name } |
            Select-Object -ExpandProperty Name -Unique
    )
} catch {
    Write-Output "Installed packages unreadable: $(($_.Exception.Message -replace '\s+', ' ').Trim())"
}

Write-Output "Provisioned for all users: $($provisioned.Count)"
if ($orphans.Count -eq 0) {
    Write-Output 'Installed but not provisioned: none'
} else {
    Write-Output "Installed but not provisioned: $($orphans.Count) - sysprep stops on one of these if it stops at all"
    foreach ($name in $orphans) { Write-Output "  ${name}" }
}

# Reported, never asserted: most of these are inbox packages sysprep handles on
# its own, and failing the build on a list this noisy would cry wolf.
exit 0
