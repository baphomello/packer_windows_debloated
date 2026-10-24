<#
.SYNOPSIS
    Points this VM at the OpenKore listener.

.DESCRIPTION
    GameGuard refuses a client that connects outside the official server range,
    so OpenKore has to be reachable at an address inside 172.65.0.0/16. How this
    VM gets there depends on where OpenKore runs:

      route    OpenKore is on another machine. A single /32 route sends exactly
               that address to it and leaves every other 172.65.x.x (the real
               game server, the patcher) on the normal path.
      gateway  That machine is already this VM's default gateway, usually
               because it also serves DHCP and DNS on an isolated switch. There
               is nothing to add, so this only verifies reachability.
      alias    OpenKore runs on this VM. The address is added as a secondary
               address on the adapter, which is the single-machine layout.
      none     Nothing is configured.

    ServerPrefix is the address range the server accepts, 172.65. for the
    official one. Set it to '' to skip the warning on a private server.

    Defaults come from C:\Tools\config.json, so a second or third VM is a file
    edit instead of a rebuild. Every parameter overrides the file.

.EXAMPLE
    Set-KoreLink.ps1 -Mode route -KoreHost 172.65.10.1 -NextHop 192.168.1.50

.EXAMPLE
    Set-KoreLink.ps1 -Mode gateway -KoreHost kore.lab.lan
#>
[CmdletBinding()]
param(
    [ValidateSet('none', 'route', 'gateway', 'alias')]
    [string] $Mode,
    [string] $KoreHost,
    [string] $NextHop,
    [string] $ServerPrefix,
    [int] $BasePort,
    [int] $PrefixLength,
    [string] $InterfaceAlias,
    [string] $ConfigPath = "$PSScriptRoot\config.json",
    [switch] $SkipTest
)

$ErrorActionPreference = 'Stop'

$config = @{}
if (Test-Path -LiteralPath $ConfigPath) {
    (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { $config[$_.Name] = $_.Value }
}

function Get-Setting {
    param([string] $Name, $Value, $Fallback)
    if ($Value) { return $Value }
    if ($config.ContainsKey($Name) -and $config[$Name]) { return $config[$Name] }
    return $Fallback
}

$Mode = Get-Setting -Name 'Mode' -Value $Mode -Fallback 'none'
$KoreHost = Get-Setting -Name 'KoreHost' -Value $KoreHost -Fallback ''
$NextHop = Get-Setting -Name 'NextHop' -Value $NextHop -Fallback ''
$BasePort = Get-Setting -Name 'BasePort' -Value $BasePort -Fallback 2350
$ServerPrefix = Get-Setting -Name 'ServerPrefix' -Value $ServerPrefix -Fallback '172.65.'
$PrefixLength = Get-Setting -Name 'PrefixLength' -Value $PrefixLength -Fallback 24

if ($Mode -eq 'none') {
    Write-Output 'Mode is none, nothing configured.'
    return
}
if (-not $KoreHost) {
    throw 'KoreHost is required. Pass -KoreHost or set it in config.json.'
}

# A name is allowed so the OpenKore host can be published over DNS, but what
# the client is given on its command line is the address it resolves to
$koreIp = $KoreHost
if ($KoreHost -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    $resolved = (Resolve-DnsName -Name $KoreHost -Type A -ErrorAction Stop |
        Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
    if (-not $resolved) {
        throw "Could not resolve $KoreHost to an IPv4 address."
    }
    $koreIp = $resolved
    Write-Output "$KoreHost resolves to $koreIp"
}

# Which range is acceptable is a property of the server, not of this script,
# so it is configurable and an empty value turns the check off
if ($ServerPrefix -and $koreIp -notlike "$ServerPrefix*") {
    Write-Warning "$koreIp is outside ${ServerPrefix}x. GameGuard is expected to reject the client with Illegal Program."
}

if (-not $InterfaceAlias) {
    $default = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1
    if (-not $default) {
        throw 'No default route on this machine, cannot pick an interface. Pass -InterfaceAlias.'
    }
    $InterfaceAlias = (Get-NetAdapter -InterfaceIndex $default.InterfaceIndex).Name
}

switch ($Mode) {
    'route' {
        if (-not $NextHop) {
            throw 'NextHop is required in route mode. Pass -NextHop or set it in config.json.'
        }
        $prefix = "$koreIp/32"
        foreach ($store in @('ActiveStore', 'PersistentStore')) {
            Get-NetRoute -DestinationPrefix $prefix -PolicyStore $store -ErrorAction SilentlyContinue |
                Remove-NetRoute -Confirm:$false -PolicyStore $store -ErrorAction SilentlyContinue
            New-NetRoute -DestinationPrefix $prefix -NextHop $NextHop -InterfaceAlias $InterfaceAlias `
                -PolicyStore $store -ErrorAction Stop | Out-Null
        }
        Write-Output "Route: $prefix via $NextHop on $InterfaceAlias"
    }

    'gateway' {
        $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -InterfaceAlias $InterfaceAlias |
            Sort-Object RouteMetric | Select-Object -First 1).NextHop
        Write-Output "Default gateway on ${InterfaceAlias}: $gateway (nothing to add)"
    }

    'alias' {
        $existing = Get-NetIPAddress -IPAddress $koreIp -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Output "$koreIp is already on $($existing.InterfaceAlias)"
        } else {
            New-NetIPAddress -IPAddress $koreIp -PrefixLength $PrefixLength -InterfaceAlias $InterfaceAlias -ErrorAction Stop | Out-Null
            Write-Output "Alias: $koreIp/$PrefixLength on $InterfaceAlias"
        }
    }
}

if (-not $SkipTest) {
    $reachable = Test-NetConnection -ComputerName $koreIp -Port $BasePort -InformationLevel Quiet -WarningAction SilentlyContinue
    Write-Output "OpenKore reachable at ${koreIp}:${BasePort}: $reachable"
    if (-not $reachable) {
        Write-Warning 'Nothing is listening yet. Start OpenKore first, then re-run with -SkipTest to silence this.'
    }
}
