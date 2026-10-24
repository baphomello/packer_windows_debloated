# Copies the payload into the image.
#
# The payload is whatever folder you pointed the build at. It arrives as a
# read-only DVD attached to the build VM, so nothing is downloaded and nothing
# is served over the network during the build.

if ($env:InstallPayload -ne 'true') {
    Write-Output 'install_payload is false, nothing to copy.'
    exit 0
}

$dest = $env:PayloadInstallDir
$label = $env:PayloadLabel
$marker = $env:PayloadMarker

# Found by volume label, not by letter: the unattend CD is attached too and the
# letters depend on the order Windows enumerated them
$source = $null
foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
    if ($drive.DriveType -ne 'CDRom' -or -not $drive.IsReady) { continue }
    if ($drive.VolumeLabel -ne $label) { continue }
    $source = $drive.RootDirectory.FullName
    break
}
if (-not $source) {
    throw "No disc labelled $label found. Check that payload_iso is attached to the build VM."
}
Write-Output "Payload disc at $source"

if ($marker -and -not (Test-Path -LiteralPath (Join-Path $source $marker))) {
    throw "The disc at $source does not contain $marker, which payload_marker says it should."
}

& robocopy.exe $source $dest /E /COPY:DAT /R:2 /W:2 /MT:8 /NFL /NDL /NJH /NJS | Out-Null
# robocopy returns a bitmask: under 8 means files were copied, 8 and up is a failure
if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}

$files = Get-ChildItem -LiteralPath $dest -Recurse -File
$size = ($files | Measure-Object Length -Sum).Sum
Write-Output ("Payload at {0}: {1} files, {2:N2} GB" -f $dest, $files.Count, ($size / 1GB))

if ($marker -and -not (Test-Path -LiteralPath (Join-Path $dest $marker))) {
    throw "$marker is missing from $dest after the copy."
}

# Applications that keep state next to their executable - and anticheats that
# rewrite their own files on every launch - need the session account to write
# here, which it does not get by default under a new folder on C:\
& icacls.exe $dest /grant '*S-1-5-32-545:(OI)(CI)M' /T /C | Out-Null

try {
    Add-MpPreference -ExclusionPath $dest -ErrorAction Stop
} catch {
    Write-Output "Exclusion not applied for ${dest}: $($_.Exception.Message)"
}

if ($env:PayloadShortcut) {
    $target = Join-Path $dest $env:PayloadShortcut
    if (Test-Path -LiteralPath $target) {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut("C:\Users\Public\Desktop\$([System.IO.Path]::GetFileNameWithoutExtension($target)).lnk")
        $lnk.TargetPath = $target
        $lnk.WorkingDirectory = $dest
        $lnk.Save()
        Write-Output "Shortcut created for $target"
    } else {
        Write-Output "payload_shortcut points at $target, which does not exist."
    }
}

exit 0
