# The build's last word on itself. Every other script reports what it tried;
# this one reads the machine back and fails the build when a change asked for in
# a variable is not there.
#
# Only deterministic artifacts are asserted: the registry value a script writes,
# never the behaviour Windows may still refuse. A policy being present proves
# the script ran. Whether Defender then honours it is reported instead, because
# tamper protection can veto it and that is not a build error.

$failures = @()

function Test-State {
    param(
        [Parameter(Mandatory)][string] $What,
        [Parameter(Mandatory)][bool] $Requested,
        [Parameter(Mandatory)][scriptblock] $Actual,
        [Parameter(Mandatory)] $Expected
    )
    if (-not $Requested) {
        Write-Output ("{0,-24} -" -f $What)
        return
    }
    $value = try { & $Actual } catch { 'unreadable: ' + ($_.Exception.Message -replace '\s+', ' ').Trim() }
    if ("$value" -eq "$Expected") {
        Write-Output ("{0,-24} {1}" -f $What, $value)
    } else {
        Write-Output ("{0,-24} {1}  EXPECTED {2}" -f $What, $value, $Expected)
        $script:failures += "${What}: found '$value', expected '$Expected'"
    }
}

# 'absent' rather than the exception text: a missing value is the whole signal,
# and the message is long and localised
function Get-RegValue {
    param([string] $Path, [string] $Name)
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'absent' }
    return $item.$Name
}

$pagefileMb = [int]($env:PagefileSizeMb)
$mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'

Write-Output '== Asserted: a variable asked for it, so it has to be here'

Test-State -What 'Defender policy' -Requested ($env:DisableDefender -eq 'true') -Expected 1 -Actual {
    Get-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'DisableAntiSpyware'
}

Test-State -What 'Windows Update policy' -Requested ($env:DisableWindowsUpdate -eq 'true') -Expected 1 -Actual {
    Get-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoUpdate'
}

Test-State -What 'wuauserv start type' -Requested ($env:DisableWindowsUpdate -eq 'true') -Expected 'Disabled' -Actual {
    (Get-Service -Name 'wuauserv').StartType
}

Test-State -What 'Firewall profiles' -Requested ($env:DisableFirewall -eq 'true') -Expected 'False' -Actual {
    ((Get-NetFirewallProfile).Enabled | Sort-Object -Unique) -join ','
}

Test-State -What 'VBS policy' -Requested ($env:DisableVbs -eq 'true') -Expected 0 -Actual {
    Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity'
}

Test-State -What 'Auto-logon' -Requested $true -Expected '1' -Actual {
    Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon'
}

Test-State -What 'Pagefile entry' -Requested ($pagefileMb -gt 0) -Expected "C:\pagefile.sys $pagefileMb $pagefileMb" -Actual {
    (Get-RegValue -Path $mm -Name 'PagingFiles') -join ';'
}

Test-State -What 'Payload directory' -Requested ($env:InstallPayload -eq 'true') -Expected 'present' -Actual {
    if (Test-Path -LiteralPath $env:PayloadInstallDir) { 'present' } else { 'missing' }
}

Test-State -What 'Payload marker' -Requested (($env:InstallPayload -eq 'true') -and [bool]$env:PayloadMarker) -Expected 'present' -Actual {
    if (Test-Path -LiteralPath (Join-Path $env:PayloadInstallDir $env:PayloadMarker)) { 'present' } else { 'missing' }
}

Write-Output ''
Write-Output '== Reported: Windows can refuse these, which is not a build error'

try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Write-Output ("{0,-24} realtime={1} tamperprotected={2}" -f 'Defender effective', $mp.RealTimeProtectionEnabled, $mp.IsTamperProtected)
    Write-Output ("{0,-24} {1}" -f 'Defender exclusions', ((Get-MpPreference).ExclusionPath -join ', '))
} catch {
    Write-Output ("{0,-24} cmdlets unavailable: {1}" -f 'Defender effective', $_.Exception.Message)
}

# The appx cmdlets throw rather than honour -ErrorAction, so they are caught
if ($env:RemoveEdge -eq 'true') {
    try {
        $edge = @(Get-AppxPackage -Name 'Microsoft.MicrosoftEdge.Stable' -AllUsers -ErrorAction SilentlyContinue)
        Write-Output ("{0,-24} {1}" -f 'Edge still installed', ($edge.Count -gt 0))
    } catch {
        Write-Output ("{0,-24} unreadable: {1}" -f 'Edge still installed', ($_.Exception.Message -replace '\s+', ' ').Trim())
    }
}
if ($env:RemoveAppx -eq 'true') {
    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
        Write-Output ("{0,-24} {1}" -f 'Provisioned appx left', $provisioned.Count)
    } catch {
        Write-Output ("{0,-24} unreadable: {1}" -f 'Provisioned appx left', ($_.Exception.Message -replace '\s+', ' ').Trim())
    }
}
Write-Output ("{0,-24} {1}" -f 'Disabled services', @(Get-Service | Where-Object { $_.StartType -eq 'Disabled' }).Count)
Write-Output ("{0,-24} {1:N1} GB" -f 'C: free', ((Get-PSDrive C).Free / 1GB))

Write-Output ''
if ($failures.Count -gt 0) {
    Write-Output "$($failures.Count) requested change(s) did not land:"
    foreach ($failure in $failures) { Write-Output "  - $failure" }
    Write-Output 'A provisioner did not run, or Windows reverted it. Answer [a] to keep the VM and look.'
    exit 1
}

Write-Output 'Every requested change is present.'
exit 0
