<#
.SYNOPSIS
    Reads why sysprep refused to generalize a build VM that is still running.

.DESCRIPTION
    Packer's Hyper-V builder discards everything the shutdown command prints, so
    a sysprep failure surfaces only as "Timeout while waiting for machine to
    shut down". Answer [a] at the Packer prompt to keep the VM, then run this.

    It reads the guest over PowerShell Direct, which needs neither a network nor
    WinRM and keeps working on a half-generalized machine.

.EXAMPLE
    .\tools\host\Get-SysprepFailure.ps1 -VMName bpho-rola-01
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $VMName,
    [pscredential] $Credential,
    [int] $Tail = 60
)

$ErrorActionPreference = 'Stop'

if (-not (Get-VM -Name $VMName -ErrorAction SilentlyContinue)) {
    throw "No VM named '$VMName'. Packer deletes it on [c], so this only works after [a]."
}

if (-not $Credential) {
    $Credential = Get-Credential -Message "Administrator account of $VMName (admin_username / admin_password)"
}

Invoke-Command -VMName $VMName -Credential $Credential -ArgumentList $Tail -ScriptBlock {
    param([int] $Tail)

    $report = 'C:\sysprep-failed.log'
    if (Test-Path -LiteralPath $report) {
        Get-Content -LiteralPath $report
        return
    }

    # The shutdown script never got far enough to write its report, so go
    # straight to the logs sysprep keeps on its own
    Write-Output "$report is not there, reading sysprep's own logs."
    foreach ($name in @('setuperr.log', 'setupact.log')) {
        $log = "C:\Windows\System32\Sysprep\Panther\$name"
        if (-not (Test-Path -LiteralPath $log)) {
            Write-Output "--- $log is not there ---"
            continue
        }
        Write-Output "--- $log (last $Tail lines) ---"
        Get-Content -LiteralPath $log -Tail $Tail
    }
}
