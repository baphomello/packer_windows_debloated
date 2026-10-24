# Host side, after the VM is shut down and exported: the guest TRIMmed its free
# space, this is what hands it back to the host as a smaller file.

$ErrorActionPreference = 'Stop'

$outputDirectory = $env:OutputDirectory
$disks = Get-ChildItem -LiteralPath $outputDirectory -Filter '*.vhdx' -Recurse -File

if (-not $disks) {
    Write-Warning "No VHDX found under $outputDirectory"
    exit 0
}

foreach ($disk in $disks) {
    $before = $disk.Length
    try {
        # Full mode needs the disk attached read-only
        Mount-VHD -Path $disk.FullName -ReadOnly -NoDriveLetter
        try {
            Optimize-VHD -Path $disk.FullName -Mode Full
        } finally {
            Dismount-VHD -Path $disk.FullName
        }
    } catch {
        Write-Warning "Full compaction failed for $($disk.Name): $($_.Exception.Message)"
        Optimize-VHD -Path $disk.FullName -Mode Quick -ErrorAction SilentlyContinue
    }

    $after = (Get-Item -LiteralPath $disk.FullName).Length
    Write-Output ("{0}: {1:N1} GB -> {2:N1} GB" -f $disk.Name, ($before / 1GB), ($after / 1GB))
}
