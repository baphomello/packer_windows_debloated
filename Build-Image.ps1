#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Builds the image with Packer.

.DESCRIPTION
    Checks the host prerequisites, packs the payload folder into an ISO the
    build VM mounts as a second DVD, then runs packer init, validate and build.

    The build writes to output_directory and scratches in build_temp_dir, both
    set in the variable file. Free space is checked on the first before anything
    is created, because a build that runs out of disk does so an hour in.

    The payload ISO is a cache: it is rebuilt only when something in the payload
    folder is newer.

.PARAMETER ProfileName
    Name of a directory under profiles/. Its profile.pkrvars.hcl is placed
    before your own variable files, so your values win.

.PARAMETER VarFile
    Variable files to build with, in order; later files win. Defaults to
    local.pkrvars.hcl.

.PARAMETER Var
    Extra packer variables, repeatable, each as name=value. Use this for the
    per-VM differences instead of keeping one file per VM.

.EXAMPLE
    .\Build-Image.ps1

.EXAMPLE
    .\Build-Image.ps1 -Var vm_name=WIN2 -Var computer_name=WIN2

.EXAMPLE
    .\Build-Image.ps1 -ProfileName ragnarok-openkore
#>
[CmdletBinding()]
param(
    [string] $ProfileName,
    [string[]] $VarFile = @('local.pkrvars.hcl'),
    [string[]] $Var = @(),
    [string] $PackerPath,
    [switch] $SkipPayloadIso,
    [switch] $SkipSpaceCheck,
    [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

# The variable file can name the profile, so the normal invocation is just
# .\Build-Image.ps1 with no arguments
if (-not $ProfileName) {
    foreach ($file in $VarFile) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $named = [regex]::Match((Get-Content -LiteralPath $file -Raw), '(?m)^\s*profile_name\s*=\s*"([^"]+)"')
        if ($named.Success) {
            $ProfileName = $named.Groups[1].Value
            break
        }
    }
}

# A profile goes first so the local file can override anything in it
$varFiles = @()
if ($ProfileName) {
    $profileFile = Join-Path $PSScriptRoot "profiles\$ProfileName\profile.pkrvars.hcl"
    if (-not (Test-Path -LiteralPath $profileFile)) {
        $available = (Get-ChildItem (Join-Path $PSScriptRoot 'profiles') -Directory -ErrorAction SilentlyContinue).Name -join ', '
        throw "No profile named '$ProfileName'. Available: $available"
    }
    $varFiles += $profileFile
}
$varFiles += $VarFile

foreach ($file in $varFiles) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Missing $file. Copy example.pkrvars.hcl to local.pkrvars.hcl and edit it."
    }
}

if (-not $PackerPath) {
    $local = Join-Path $PSScriptRoot 'packer.exe'
    $PackerPath = if (Test-Path -LiteralPath $local) { $local } else { 'packer' }
}
if (-not (Get-Command $PackerPath -ErrorAction SilentlyContinue)) {
    throw "Packer not found. Install it, drop packer.exe next to this script, or pass -PackerPath."
}

# Checked before anything expensive: packing the apps ISO takes minutes, and
# packer's own required_version only speaks up at validate, well after that.
$minPacker = [version] '1.16.0'
$versionLine = (& $PackerPath version) -join ' '
if ($versionLine -match 'v?(\d+\.\d+\.\d+)') {
    $found = [version] $Matches[1]
    if ($found -lt $minPacker) {
        throw "Packer $found is too old: this template needs $minPacker or newer, because optional() in an object type constraint is rejected by earlier releases. Download from https://developer.hashicorp.com/packer/install"
    }
} else {
    Write-Host "Could not read the Packer version from '$versionLine'; continuing." -ForegroundColor Yellow
}

# Later files win, same as packer
$vars = ($varFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"

function Get-PackerVar {
    param([string] $Name, [string] $Default = '')
    # Command line wins, same as packer itself
    $fromArgs = $Var | Where-Object { $_ -like "$Name=*" } | Select-Object -Last 1
    if ($fromArgs) { return $fromArgs.Substring($Name.Length + 1).Trim('"') }

    $found = [regex]::Matches($vars, "(?m)^\s*$Name\s*=\s*`"?([^`"\r\n]+)`"?\s*$")
    if ($found.Count -gt 0) { return $found[$found.Count - 1].Groups[1].Value.Trim() }
    return $Default
}

function ConvertTo-WindowsPath {
    param([string] $Path)
    return ($Path -replace '/', '\')
}

# --- host prerequisites -------------------------------------------------

# Checked through the service rather than the DISM feature: it is what actually
# has to be running, it needs no elevation gymnastics, and it avoids the DISM
# module, which PowerShell 7 can only reach through its Windows PowerShell
# compatibility proxies.
$vmms = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue
if (-not $vmms) {
    throw 'Hyper-V is not installed on this host: there is no vmms service.'
}
if ($vmms.Status -ne 'Running') {
    throw "The Hyper-V service (vmms) is $($vmms.Status). Start it, or enable Hyper-V and reboot."
}

# Hyper-V takes guest memory from physical RAM and never from the pagefile, so
# a machine with plenty of commit but little free memory still cannot start the
# VM. Packer only warns about this, and it warns after two minutes of work.
$vmMemoryMb = [int](Get-PackerVar 'vm_memory' '4096')
$freeMb = [int]((Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory / 1KB)
if ($freeMb -lt ($vmMemoryMb + 512)) {
    throw ("Only {0} MB of physical memory is free; the VM needs {1} MB plus overhead. Close something, or cap WSL in %USERPROFILE%\.wslconfig and run wsl --shutdown." -f $freeMb, $vmMemoryMb)
}
Write-Host ("Free memory: {0:N1} GB, VM wants {1:N1} GB" -f ($freeMb / 1024), ($vmMemoryMb / 1024)) -ForegroundColor Cyan

# Packer builds the unattend CD with oscdimg, and so does this script
if (-not (Get-Command 'oscdimg.exe' -ErrorAction SilentlyContinue)) {
    throw 'oscdimg.exe is not in PATH. Install the Windows ADK (Deployment Tools) and add it, or copy oscdimg.exe into C:\Windows\System32.'
}

$isoUrl = Get-PackerVar 'iso_url'
if ($isoUrl -and $isoUrl -notmatch '^https?://' -and -not (Test-Path -LiteralPath (ConvertTo-WindowsPath $isoUrl))) {
    throw "The Windows ISO does not exist: $isoUrl"
}

# Asked over CIM rather than through the Hyper-V module, so this script needs
# nothing that PowerShell 7 can only reach through compatibility proxies
$switchName = Get-PackerVar 'switch_name' 'Default Switch'
$switch = Get-CimInstance -Namespace 'root\virtualization\v2' -ClassName 'Msvm_VirtualEthernetSwitch' `
    -Filter "ElementName='$switchName'" -ErrorAction SilentlyContinue
if (-not $switch) {
    throw "Hyper-V switch '$switchName' does not exist. Create it or set switch_name."
}

# A ComputerName Windows rejects takes the whole specialize pass with it: the
# answer file is abandoned, no account is created, bootstrap-winrm.ps1 never
# runs, and the build dies hours later on a WinRM timeout with nothing to read.
# computer_name falls back to vm_name, so a descriptive VM name lands here too.
$computerName = Get-PackerVar 'computer_name'
if (-not $computerName) { $computerName = Get-PackerVar 'vm_name' 'WINMIN' }
if ($computerName.Length -gt 15 -or $computerName -notmatch '^[A-Za-z0-9-]+$' -or $computerName -match '^\d+$') {
    throw ("'$computerName' is not a valid Windows hostname: 1-15 characters, " +
        'letters, digits and hyphens only, and not all digits. It comes from ' +
        'computer_name, which falls back to vm_name. Shorten vm_name, or set ' +
        'computer_name separately to keep the longer VM name.')
}

$outputDirectory = Get-PackerVar 'output_directory' 'C:/HyperV/packer'
if ($outputDirectory -match '^\\\\') {
    throw "output_directory must be a local path, Hyper-V cannot use UNC: $outputDirectory"
}

# Packer takes its scratch location from the environment and not from the
# template, so the unattend ISO and the ISO cache are moved here rather than in
# windows.pkr.hcl. Both default to the user TEMP on C:.
$buildTempDir = ConvertTo-WindowsPath (Get-PackerVar 'build_temp_dir')
if ($buildTempDir) {
    foreach ($dir in @($buildTempDir, (Join-Path $buildTempDir 'packer_cache'))) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    $env:TMP = $buildTempDir
    $env:TEMP = $buildTempDir
    $env:PACKER_CACHE_DIR = Join-Path $buildTempDir 'packer_cache'
    Write-Host "Build scratch: $buildTempDir" -ForegroundColor Cyan
}

# --- payload ISO --------------------------------------------------------

$installPayload = (Get-PackerVar 'install_payload' 'true') -eq 'true'

if ($installPayload -and -not $SkipPayloadIso) {
    $sourceDir = ConvertTo-WindowsPath (Get-PackerVar 'payload_source_dir')
    if (-not $sourceDir) {
        throw 'payload_source_dir is not set and install_payload is true.'
    }

    # Mirrors the defaults in windows.pkr.hcl
    $payloadIso = Get-PackerVar 'payload_iso'
    if (-not $payloadIso) { $payloadIso = "$(Get-PackerVar 'payload_source_dir').iso" }
    $payloadIso = ConvertTo-WindowsPath $payloadIso
    $label = Get-PackerVar 'payload_label' 'PAYLOAD'
    $marker = Get-PackerVar 'payload_marker'

    $payloadFiles = @(Get-ChildItem -LiteralPath $sourceDir -File -Recurse -ErrorAction SilentlyContinue)
    if ($payloadFiles.Count -eq 0) {
        throw "No files in $sourceDir. Point payload_source_dir at the folder you want in the image."
    }
    if ($marker -and -not (Test-Path -LiteralPath (Join-Path $sourceDir $marker))) {
        throw "payload_marker is '$marker' but $sourceDir does not contain it."
    }

    $newest = ($payloadFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    $isoFile = Get-Item -LiteralPath $payloadIso -ErrorAction SilentlyContinue

    if (-not $isoFile -or $isoFile.LastWriteTime -lt $newest) {
        # oscdimg will not create the target directory for you
        $isoParent = Split-Path -LiteralPath $payloadIso -Parent
        if ($isoParent -and -not (Test-Path -LiteralPath $isoParent)) {
            New-Item -ItemType Directory -Path $isoParent -Force | Out-Null
        }

        $size = ($payloadFiles | Measure-Object Length -Sum).Sum / 1GB
        Write-Host ("Packing {0} ({1:N2} GB) into {2}" -f $sourceDir, $size, $payloadIso) -ForegroundColor Cyan
        & oscdimg.exe -u2 -udfver102 "-l$label" $sourceDir $payloadIso
        if ($LASTEXITCODE -ne 0) {
            throw "oscdimg failed with exit code $LASTEXITCODE"
        }
        $isoFile = Get-Item -LiteralPath $payloadIso
    }

    Write-Host ("Payload ISO: {0} ({1:N2} GB, label {2})" -f $isoFile.FullName, ($isoFile.Length / 1GB), $label) -ForegroundColor Cyan
}

# --- free space ---------------------------------------------------------

# The VHDX grows to the installed image plus the payload, and an export is a
# second full copy of it. Checked here, after the payload ISO exists, so its
# real size is known instead of guessed.
if (-not $SkipSpaceCheck) {
    $outputRoot = [System.IO.Path]::GetPathRoot((ConvertTo-WindowsPath $outputDirectory))
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($outputRoot.TrimEnd('\'))'" -ErrorAction SilentlyContinue
    if (-not $disk) {
        Write-Warning "Could not read free space on $outputRoot, skipping the check."
    } else {
        $payloadGb = 0
        if ($installPayload) {
            $iso = Get-Item -LiteralPath (ConvertTo-WindowsPath (Get-PackerVar 'payload_iso')) -ErrorAction SilentlyContinue
            if ($iso) { $payloadGb = $iso.Length / 1GB }
        }
        $neededGb = [math]::Round(20 + $payloadGb, 1)
        if ((Get-PackerVar 'skip_export' 'false') -ne 'true') { $neededGb = $neededGb * 2 }
        $freeGb = [math]::Round($disk.FreeSpace / 1GB, 1)

        if ($freeGb -lt $neededGb) {
            throw ("Only {0} GB free on {1}; this build needs about {2} GB. Point output_directory at another drive, set skip_export = true, or pass -SkipSpaceCheck." -f $freeGb, $outputRoot, $neededGb)
        }
        Write-Host ("Build location: {0} ({1:N1} GB free, about {2:N1} GB needed)" -f $outputDirectory, $freeGb, $neededGb) -ForegroundColor Cyan
    }
}

# --- build --------------------------------------------------------------

$packerArgs = @($varFiles | ForEach-Object { "-var-file=$_" })
foreach ($v in $Var) { $packerArgs += @('-var', $v) }

& $PackerPath init windows.pkr.hcl
if ($LASTEXITCODE -ne 0) { throw "packer init failed with exit code $LASTEXITCODE" }

& $PackerPath validate @packerArgs windows.pkr.hcl
if ($LASTEXITCODE -ne 0) { throw "packer validate failed with exit code $LASTEXITCODE" }

if ($ValidateOnly) {
    Write-Host 'Validation only, stopping here.' -ForegroundColor Cyan
    return
}

& $PackerPath build -on-error=ask -force @packerArgs windows.pkr.hcl
if ($LASTEXITCODE -ne 0) { throw "packer build failed with exit code $LASTEXITCODE" }
