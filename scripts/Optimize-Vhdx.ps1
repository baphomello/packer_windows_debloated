# Host side, after the VM is shut down and exported: the guest TRIMmed its free
# space, this is what hands it back to the host as a smaller file.

$ErrorActionPreference = 'Stop'

$outputDirectory = $env:OutputDirectory

# A post-processor failing fails the build, and by now the image exists and is
# finished. Nothing in here is worth that, so every way out is a warning.
if (-not (Get-Command 'Optimize-VHD' -ErrorAction SilentlyContinue)) {
    Write-Warning 'No Hyper-V PowerShell module on this host; leaving the VHDX uncompacted.'
    exit 0
}

$disks = @(Get-ChildItem -LiteralPath $outputDirectory -Filter '*.vhdx' -Recurse -File -ErrorAction SilentlyContinue)

if ($disks.Count -eq 0) {
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
        try {
            Optimize-VHD -Path $disk.FullName -Mode Quick
        } catch {
            Write-Warning "Quick compaction also failed: $($_.Exception.Message)"
        }
    }

    $after = (Get-Item -LiteralPath $disk.FullName).Length
    Write-Output ("{0}: {1:N1} GB -> {2:N1} GB" -f $disk.Name, ($before / 1GB), ($after / 1GB))
}
