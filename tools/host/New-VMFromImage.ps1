<#
.SYNOPSIS
    Creates Hyper-V VMs from a built image.

.DESCRIPTION
    Hyper-V has no template object - that is a VMM idea. What it has is a
    generalized VHDX and whatever you write to deploy from it, which is this.

    The image this repo builds with generalize = true is already the template
    half: sysprep has run, so every VM made from a copy boots through OOBE once
    and takes its own SID, hostname and machine GUID.

    Differencing keeps one read-only parent and gives each VM a child disk that
    holds only its own writes. That is the closest thing here to how a VMM
    template behaves, and it costs megabytes per VM instead of gigabytes.

.EXAMPLE
    .\tools\host\New-VMFromImage.ps1 -ImagePath C:\HyperV\packer\WINMIN\Virtual' 'Hard' 'Disks\WINMIN.vhdx -Name WIN1

.EXAMPLE
    .\tools\host\New-VMFromImage.ps1 -ImagePath ...\WINMIN.vhdx -Name WIN1,WIN2,WIN3 -Differencing
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string] $ImagePath,
    [Parameter(Mandatory)][string[]] $Name,
    [string] $Path = 'C:\HyperV',
    [string] $SwitchName = 'Default Switch',
    [int64] $MemoryStartupBytes = 4GB,
    [int] $ProcessorCount = 2,
    [switch] $Differencing,
    [switch] $SecureBoot,
    [switch] $Tpm
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "No image at $ImagePath."
}
$image = (Get-Item -LiteralPath $ImagePath).FullName

foreach ($vmName in $Name) {
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        Write-Warning "$vmName already exists, skipped."
        continue
    }
    if ($vmName.Length -gt 15) {
        Write-Warning "$vmName is longer than the 15 characters Windows takes for a hostname. The VM name is fine; sysprep names the guest itself."
    }

    $vmDir = Join-Path $Path $vmName
    $disk = Join-Path $vmDir "$vmName.vhdx"
    if (Test-Path -LiteralPath $disk) {
        Write-Warning "$disk already exists, skipped."
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($vmName, "create from $image")) { continue }

    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null

    if ($Differencing) {
        # A differencing child is only valid while its parent never changes
        Set-ItemProperty -LiteralPath $image -Name IsReadOnly -Value $true
        New-VHD -Path $disk -ParentPath $image -Differencing | Out-Null
    } else {
        Copy-Item -LiteralPath $image -Destination $disk
        Set-ItemProperty -LiteralPath $disk -Name IsReadOnly -Value $false
    }

    New-VM -Name $vmName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes `
        -VHDPath $disk -SwitchName $SwitchName -Path $Path | Out-Null
    Set-VM -Name $vmName -ProcessorCount $ProcessorCount -CheckpointType Disabled

    # Off unless asked: the image installs without either, which is what lets
    # one build serve hypervisors that cannot offer them
    Set-VMFirmware -VMName $vmName -EnableSecureBoot $(if ($SecureBoot) { 'On' } else { 'Off' })

    if ($Tpm) {
        # Enable-VMTPM fails outright without one of these, and the message
        # does not say which of the two steps was missed
        Set-VMKeyProtector -VMName $vmName -NewLocalKeyProtector
        Enable-VMTPM -VMName $vmName
    }

    $kind = if ($Differencing) { 'differencing' } else { 'full copy' }
    Write-Output "$vmName created ($kind)"
}
