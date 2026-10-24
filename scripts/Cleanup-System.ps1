# Last pass before sysprep: everything deleted here is space the VHDX would
# carry into every clone.
#
# C:\Windows\Panther is left alone on purpose: sysprep-unattend.xml lives there
# and is read on the shutdown that ends this build.

$before = (Get-PSDrive C).Free

# WinRE is a 700 MB recovery image for a VM that gets rebuilt instead of repaired
reagentc /disable 2>&1 | Out-Null
Remove-Item -LiteralPath 'C:\Recovery\WindowsRE' -Recurse -Force -ErrorAction SilentlyContinue

Write-Output 'Running component store cleanup, this takes a while.'
& dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet
Write-Output "dism exit code: $LASTEXITCODE"

$paths = @(
    'C:\Windows\Prefetch\*'
    'C:\Windows\SoftwareDistribution\Download\*'
    'C:\Windows\Logs\CBS\*'
    'C:\Windows\Logs\DISM\*'
    'C:\Windows\Logs\MoSetup\*'
    'C:\Windows\Logs\WindowsUpdate\*'
    'C:\$Windows.~BT'
    'C:\$Windows.~WS'
    'C:\Windows.old'
    'C:\ProgramData\Microsoft\Windows\WER\*'
    "$env:LOCALAPPDATA\Temp\*"
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db"
)
foreach ($path in $paths) {
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

# C:\Windows\Temp holds the script Packer is running right now, its environment
# variables and its output file. A blanket delete pulls the floor out from under
# this very provisioner.
Get-ChildItem -LiteralPath 'C:\Windows\Temp' -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike 'packer-*' -and $_.Name -notlike 'script-*' } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

try {
    Clear-RecycleBin -Force -ErrorAction Stop
} catch {
    Write-Output 'Recycle bin already empty.'
}

& wevtutil.exe el | ForEach-Object { & wevtutil.exe cl "$_" 2>&1 | Out-Null }

# Defragmenting a dynamic VHDX rewrites it and makes it grow; only the TRIM
# matters, because that is what lets the host compact the file afterwards
Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue

$after = (Get-PSDrive C).Free
Write-Output ("Free space on C: {0:N1} GB -> {1:N1} GB" -f ($before / 1GB), ($after / 1GB))

exit 0
