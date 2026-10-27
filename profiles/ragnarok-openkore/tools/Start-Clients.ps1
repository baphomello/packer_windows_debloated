<#
.SYNOPSIS
    Starts the game clients on this VM.

.DESCRIPTION
    XKore 1 listens per instance, it does not multiplex: one OpenKore process
    per client, each on its own port. So client N is launched against
    BasePort + N - 1, and the matching OpenKore has that value as XKore_port.

    The -ip and -port flags are what the bridge DLL reads out of the command
    line, and -al picks a profile from autologin.ini. Defaults come from
    C:\Tools\config.json; every parameter overrides the file.

.EXAMPLE
    Start-Clients.ps1

.EXAMPLE
    Start-Clients.ps1 -Count 2 -BasePort 2360 -Profiles alpha,beta

.EXAMPLE
    Start-Clients.ps1 -AppDir C:\Client -ClientExe Ragexe.exe -LaunchToken 1rag1
#>
[CmdletBinding()]
param(
    [int] $Count,
    [string] $KoreHost,
    [int] $BasePort,
    [string] $AppDir,
    [string] $ClientExe,
    [string] $LaunchToken,
    [string[]] $Profiles,
    [int] $StartDelaySeconds = 8,
    [string] $ConfigPath = "$PSScriptRoot\config.json"
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

$Count = Get-Setting -Name 'Instances' -Value $Count -Fallback 1
$KoreHost = Get-Setting -Name 'KoreHost' -Value $KoreHost -Fallback ''
$BasePort = Get-Setting -Name 'BasePort' -Value $BasePort -Fallback 2350
$AppDir = Get-Setting -Name 'AppDir' -Value $AppDir -Fallback 'C:\Ragnarok'
$ClientExe = Get-Setting -Name 'ClientExe' -Value $ClientExe -Fallback 'Ragexe.exe'
$LaunchToken = Get-Setting -Name 'LaunchToken' -Value $LaunchToken -Fallback '1rag1'
$Profiles = Get-Setting -Name 'Profiles' -Value $Profiles -Fallback @()

if (-not $KoreHost) {
    throw 'KoreHost is required. Pass -KoreHost or set it in config.json.'
}

$exe = Join-Path $AppDir $ClientExe
if (-not (Test-Path -LiteralPath $exe)) {
    throw "$ClientExe not found in $AppDir"
}

for ($i = 0; $i -lt $Count; $i++) {
    $port = $BasePort + $i
    $arguments = @($LaunchToken, '-ip', $KoreHost, '-port', $port)
    $profileName = ''
    if ($Profiles -and $i -lt $Profiles.Count) {
        $profileName = $Profiles[$i]
        $arguments += @('-al', $profileName)
    }

    Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $AppDir
    Write-Output ("Client {0}/{1} -> {2}:{3} {4}" -f ($i + 1), $Count, $KoreHost, $port, $profileName)

    # GameGuard initialises one client at a time; launching them together is how
    # two of them end up fighting over the same init and dying
    if ($i -lt $Count - 1) {
        Start-Sleep -Seconds $StartDelaySeconds
    }
}
