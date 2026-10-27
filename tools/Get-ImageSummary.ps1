<#
.SYNOPSIS
    Prints what this image actually ended up as.

.DESCRIPTION
    Reports the state the build left behind rather than the state it intended:
    Defender, Windows Update, the firewall, virtualization based security, the
    disabled services and the installed apps. Run it on a fresh clone when something
    behaves differently from what the README claims.
#>
[CmdletBinding()]
param()

function Write-Section {
    param([string] $Name)
    Write-Output ''
    Write-Output "== $Name"
}

Write-Output "$($env:COMPUTERNAME) - $((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).Version)"

Write-Section 'Defender'
try {
    $status = Get-MpComputerStatus -ErrorAction Stop
    Write-Output "AntivirusEnabled        : $($status.AntivirusEnabled)"
    Write-Output "RealTimeProtection      : $($status.RealTimeProtectionEnabled)"
    Write-Output "IsTamperProtected       : $($status.IsTamperProtected)"
    Write-Output "Exclusions              : $((Get-MpPreference).ExclusionPath -join ', ')"
} catch {
    Write-Output "Defender cmdlets unavailable: $($_.Exception.Message)"
}

Write-Section 'Windows Update'
foreach ($name in @('wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'DoSvc')) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) { Write-Output ("{0,-14} {1}" -f $svc.Name, $svc.StartType) }
}
$wu = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
Write-Output "WUServer                : $($wu.WUServer)"

Write-Section 'Security posture'
Write-Output "Firewall profiles       : $((Get-NetFirewallProfile).Enabled -join ', ')"
$dg = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -ErrorAction SilentlyContinue
Write-Output "VBS policy              : $($dg.EnableVirtualizationBasedSecurity)"
Write-Output "Hypervisor launch       : $((bcdedit /enum '{current}' | Select-String 'hypervisorlaunchtype') -replace '\s+', ' ')"

Write-Section 'Resources'
$cs = Get-CimInstance Win32_ComputerSystem
Write-Output "CPUs / RAM              : $($cs.NumberOfLogicalProcessors) / $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB"
Write-Output "Pagefile                : $((Get-CimInstance Win32_PageFileSetting | ForEach-Object { "$($_.Name) $($_.InitialSize)-$($_.MaximumSize) MB" }) -join ', ')"
$disk = Get-PSDrive C
Write-Output "C: free / used          : $([math]::Round($disk.Free / 1GB, 1)) / $([math]::Round($disk.Used / 1GB, 1)) GB"
Write-Output "Disabled services       : $((Get-Service | Where-Object StartType -eq 'Disabled').Count)"

Write-Section 'Apps'
$config = Join-Path $PSScriptRoot 'config.json'
if (Test-Path -LiteralPath $config) {
    Write-Output "C:\Tools\config.json    :"
    Get-Content -LiteralPath $config -Raw | Write-Output
} else {
    Write-Output 'No config.json in C:\Tools'
}
