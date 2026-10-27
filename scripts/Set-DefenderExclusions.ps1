# Defender rescans every file an application reads and writes, which on a VM
# built around one or two of them is almost pure overhead. A path exclusion is
# the supported way to take the scanner off that IO path, and it is the only
# Defender setting worth writing from a build: tamper protection reverts the
# real-time and service values, but it honours exclusions.
#
# Scope these to the directories the payload actually uses. A whole-volume
# exclusion is far broader than anything here needs, and Defender's own script
# scanner refuses a script that asks for one, which takes the rest of the file
# down with it. Install-Apps.ps1 adds each app's directory on its own.

$paths = @($env:DefenderExclusions -split ';' | Where-Object { $_ })

if ($paths.Count -eq 0) {
    Write-Output 'No Defender exclusions requested.'
    exit 0
}

foreach ($path in $paths) {
    try {
        Add-MpPreference -ExclusionPath $path -ErrorAction Stop
        Write-Output "Excluded ${path}"
    } catch {
        Write-Output "Exclusion not applied for ${path}: $($_.Exception.Message)"
    }
}

# Reading them back is a report, not the job, and a module that is not there
# throws past -ErrorAction because the command never resolves at all
try {
    Write-Output "Exclusions now: $((Get-MpPreference).ExclusionPath -join ', ')"
} catch {
    Write-Output 'Exclusions could not be read back.'
}

exit 0
