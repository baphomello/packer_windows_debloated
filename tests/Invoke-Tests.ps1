<#
.SYNOPSIS
    Exercises the provisioning scripts without building an image.

.DESCRIPTION
    A build takes hours and needs Hyper-V, elevation and a Windows ISO. Most of
    what goes wrong in it is ordinary script logic, and that can be checked in
    seconds on any Windows box, by anyone, with no rights at all.

    Each case runs the real script in a child Windows PowerShell, against a
    manifest shaped exactly the way jsonencode() writes it, and then looks at
    what landed on disk rather than at what the script said.

.EXAMPLE
    .\tests\Invoke-Tests.ps1
#>
[CmdletBinding()]
param([string] $Filter = '*')

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$installApps = Join-Path $root 'scripts\Install-Apps.ps1'
$testImageState = Join-Path $root 'scripts\Test-ImageState.ps1'
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$work = Join-Path $env:TEMP ('packer-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

$results = [ordered]@{}
$script:current = $null

function Start-Case {
    param([string] $Name)
    $script:current = $Name
    $results[$Name] = @()
}

function Confirm-That {
    param([string] $Claim, [bool] $Holds)
    $results[$script:current] += [pscustomobject]@{ Claim = $Claim; Holds = $Holds }
}

# The typed variable in windows.pkr.hcl sends every attribute, so a manifest
# with only the interesting ones set would not be the shape the guest sees
function New-AppEntry {
    param([hashtable] $Set)
    $app = [ordered]@{
        name = ''; type = ''; source = ''; url = ''; dest = ''
        args = @(); marker = ''; shortcut = ''
        extractor = ''; extractor_args = @(); success_exit_codes = @()
        grant_users = $false; exclude_from_defender = $false
    }
    foreach ($k in $Set.Keys) { $app[$k] = $Set[$k] }
    return $app
}

# Run the real script the way a provisioner does: a fresh process, a manifest on
# disk, and nothing shared with this one but the file system
function Invoke-Install {
    param([array] $Apps, [string] $DiscPath, [string] $Path)

    $manifest = Join-Path $work 'apps.json'
    ConvertTo-Json @($Apps) -Depth 6 | Set-Content -LiteralPath $manifest -Encoding UTF8

    $env:AppsManifest = $manifest
    $env:AppsDiscPath = $DiscPath
    $env:AppsLabel = 'TESTS'
    $old = $env:PATH
    if ($Path) { $env:PATH = $Path }
    # A failing case writes to stderr, and 2>&1 would turn that into a
    # terminating error here rather than the result the case wants to look at
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installApps 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
    } finally {
        $ErrorActionPreference = $prev
        $env:PATH = $old
        Remove-Item Env:\AppsDiscPath -ErrorAction SilentlyContinue
        Remove-Item Env:\AppsManifest -ErrorAction SilentlyContinue
    }
}

function New-Disc {
    param([string] $Name)
    $disc = Join-Path $work "disc-$Name"
    New-Item -Path $disc -ItemType Directory -Force | Out-Null
    return $disc
}

function Get-FileCount {
    param([string] $Path)
    return @(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count
}

New-Item -Path $work -ItemType Directory -Force | Out-Null
Write-Host "Workspace: $work" -ForegroundColor DarkGray

# ---------------------------------------------------------------- copy

if ('copy' -like $Filter) {
    Start-Case 'copy: a folder from the disc lands with its tree intact'
    $disc = New-Disc 'copy'
    New-Item -Path (Join-Path $disc 'App\sub') -ItemType Directory -Force | Out-Null
    'binary' | Set-Content (Join-Path $disc 'App\App.exe')
    'nested' | Set-Content (Join-Path $disc 'App\sub\data.bin')
    $dest = Join-Path $work 'out-copy'

    $r = Invoke-Install @(New-AppEntry @{ name = 'App'; type = 'copy'; source = 'App'; dest = $dest; marker = 'App.exe' }) $disc
    Confirm-That 'exits zero' ($r.ExitCode -eq 0)
    Confirm-That 'both files arrive' ((Get-FileCount $dest) -eq 2)
    Confirm-That 'the subdirectory survives' (Test-Path (Join-Path $dest 'sub\data.bin'))
}

if ('copy-root' -like $Filter) {
    Start-Case 'copy: source "." takes the whole disc'
    $disc = New-Disc 'root'
    'one' | Set-Content (Join-Path $disc 'a.txt')
    New-Item -Path (Join-Path $disc 'sub') -ItemType Directory -Force | Out-Null
    'two' | Set-Content (Join-Path $disc 'sub\b.txt')
    $dest = Join-Path $work 'out-root'

    $r = Invoke-Install @(New-AppEntry @{ name = 'Whole'; type = 'copy'; source = '.'; dest = $dest }) $disc
    Confirm-That 'exits zero' ($r.ExitCode -eq 0)
    Confirm-That 'both files arrive' ((Get-FileCount $dest) -eq 2)
}

if ('marker' -like $Filter) {
    Start-Case 'marker: a missing one fails the build'
    $disc = New-Disc 'marker'
    New-Item -Path (Join-Path $disc 'App') -ItemType Directory -Force | Out-Null
    'binary' | Set-Content (Join-Path $disc 'App\other.exe')
    $dest = Join-Path $work 'out-marker'

    $r = Invoke-Install @(New-AppEntry @{ name = 'App'; type = 'copy'; source = 'App'; dest = $dest; marker = 'App.exe' }) $disc
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'names the missing file' ($r.Output -match 'App\.exe')
}

# ------------------------------------------------------------- archive

if ('zip' -like $Filter) {
    Start-Case 'archive: a zip unpacks with the tar.exe Windows ships'
    $disc = New-Disc 'zip'
    $staging = Join-Path $work 'zipsrc'
    New-Item -Path $staging -ItemType Directory -Force | Out-Null
    'payload' | Set-Content (Join-Path $staging 'app.txt')
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath (Join-Path $disc 'app.zip') -Force
    $dest = Join-Path $work 'out-zip'

    $r = Invoke-Install @(New-AppEntry @{ name = 'Zipped'; type = 'archive'; source = 'app.zip'; dest = $dest }) $disc
    Confirm-That 'exits zero' ($r.ExitCode -eq 0)
    Confirm-That 'the file arrives' ((Get-FileCount $dest) -ge 1)
}

if ('7z' -like $Filter) {
    Start-Case 'archive: a plain 7z needs no extractor at all'
    $disc = New-Disc '7z'
    Copy-Item (Join-Path $fixtures 'plain.7z') (Join-Path $disc 'plain.7z')
    $dest = Join-Path $work 'out-7z'

    $r = Invoke-Install @(New-AppEntry @{ name = 'Plain7z'; type = 'archive'; source = 'plain.7z'; dest = $dest }) $disc
    Confirm-That 'exits zero' ($r.ExitCode -eq 0)
    Confirm-That 'both files arrive' ((Get-FileCount $dest) -eq 2)
}

if ('encrypted' -like $Filter) {
    Start-Case 'archive: an encrypted 7z fails and leaves the destination untouched'
    $disc = New-Disc 'enc'
    Copy-Item (Join-Path $fixtures 'encrypted.7z') (Join-Path $disc 'enc.7z')
    $dest = Join-Path $work 'out-enc'

    $r = Invoke-Install @(New-AppEntry @{ name = 'Secrets'; type = 'archive'; source = 'enc.7z'; dest = $dest }) $disc
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'says the archive is encrypted' ($r.Output -match 'encrypted')
    Confirm-That 'names extractor as the way out' ($r.Output -match 'extractor')
    # The point of the staging directory: tar.exe creates every file empty
    # before it fails, and none of that may reach the destination
    Confirm-That 'nothing at all reaches the destination' (-not (Test-Path $dest))
}

if ('encrypted-header' -like $Filter) {
    Start-Case 'archive: a header-encrypted 7z fails the same way'
    $disc = New-Disc 'ench'
    Copy-Item (Join-Path $fixtures 'encrypted-header.7z') (Join-Path $disc 'ench.7z')
    $dest = Join-Path $work 'out-ench'

    $r = Invoke-Install @(New-AppEntry @{ name = 'Headers'; type = 'archive'; source = 'ench.7z'; dest = $dest }) $disc
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'nothing reaches the destination' (-not (Test-Path $dest))
}

if ('extractor-missing' -like $Filter) {
    Start-Case 'archive: a declared extractor that is not installed says so'
    $disc = New-Disc 'extm'
    Copy-Item (Join-Path $fixtures 'encrypted.7z') (Join-Path $disc 'enc.7z')
    $dest = Join-Path $work 'out-extm'

    $r = Invoke-Install @(New-AppEntry @{
            name = 'Secrets'; type = 'archive'; source = 'enc.7z'; dest = $dest
            extractor = 'C:\Program Files\Nope\nope.exe'
        }) $disc
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'names the tool that is missing' ($r.Output -match 'nope\.exe')
    Confirm-That 'suggests ordering it earlier' ($r.Output -match 'earlier')
}

# ----------------------------------------------------------------- exe

if ('exe' -like $Filter) {
    Start-Case 'exe: an installer exit code decides the build'
    $disc = New-Disc 'exe'
    '@exit /b 7' | Set-Content -LiteralPath (Join-Path $disc 'setup.cmd') -Encoding ASCII

    $r = Invoke-Install @(New-AppEntry @{ name = 'Setup'; type = 'exe'; source = 'setup.cmd' }) $disc
    Confirm-That '7 is a failure by default' ($r.ExitCode -ne 0)
    Confirm-That 'the code is reported' ($r.Output -match '7')

    $r2 = Invoke-Install @(New-AppEntry @{ name = 'Setup'; type = 'exe'; source = 'setup.cmd'; success_exit_codes = @(0, 7) }) $disc
    Confirm-That '7 passes once success_exit_codes says so' ($r2.ExitCode -eq 0)
}

# ----------------------------------------------------------------- git

if ('git' -like $Filter) {
    Start-Case 'git: a clean image has none, and the failure says what to do'
    $disc = New-Disc 'git'
    $dest = Join-Path $work 'out-git'
    # The PATH a clean Windows actually ships with, which has no git in it
    $bare = "$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\system32\Wbem;$env:SystemRoot\system32\WindowsPowerShell\v1.0"

    $r = Invoke-Install @(New-AppEntry @{
            name = 'Tools'; type = 'git'; url = 'https://example.invalid/x.git'; dest = $dest
        }) $disc $bare
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'says git is not installed' ($r.Output -match 'git is not installed')
    Confirm-That 'offers the apps disc as the alternative' ($r.Output -match 'apps disc')
}

# --------------------------------------------------------------- order

if ('order' -like $Filter) {
    Start-Case 'order: apps run top to bottom, which is the only dependency there is'
    $disc = New-Disc 'order'
    New-Item -Path (Join-Path $disc 'First') -ItemType Directory -Force | Out-Null
    'one' | Set-Content (Join-Path $disc 'First\a.txt')
    New-Item -Path (Join-Path $disc 'Second') -ItemType Directory -Force | Out-Null
    'two' | Set-Content (Join-Path $disc 'Second\b.txt')
    $d1 = Join-Path $work 'out-first'
    $d2 = Join-Path $work 'out-second'

    $r = Invoke-Install @(
        (New-AppEntry @{ name = 'First'; type = 'copy'; source = 'First'; dest = $d1 }),
        (New-AppEntry @{ name = 'Second'; type = 'copy'; source = 'Second'; dest = $d2 })
    ) $disc
    Confirm-That 'exits zero' ($r.ExitCode -eq 0)
    Confirm-That 'both install' ((Test-Path $d1) -and (Test-Path $d2))
    Confirm-That 'reports two' ($r.Output -match '2 app\(s\) installed')
    Confirm-That 'first is logged before second' ($r.Output.IndexOf('First') -lt $r.Output.IndexOf('Second'))
}

if ('order-stops' -like $Filter) {
    Start-Case 'order: a failure stops the list where it failed'
    $disc = New-Disc 'stop'
    New-Item -Path (Join-Path $disc 'Good') -ItemType Directory -Force | Out-Null
    'ok' | Set-Content (Join-Path $disc 'Good\a.txt')
    $dLate = Join-Path $work 'out-late'

    $r = Invoke-Install @(
        (New-AppEntry @{ name = 'Missing'; type = 'copy'; source = 'NotThere'; dest = (Join-Path $work 'out-nope') }),
        (New-AppEntry @{ name = 'Later'; type = 'copy'; source = 'Good'; dest = $dLate })
    ) $disc
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'the app after the failure never runs' (-not (Test-Path $dLate))
}

# -------------------------------------------------------------- shapes

if ('unknown-type' -like $Filter) {
    Start-Case 'an unknown type is refused by name'
    $disc = New-Disc 'unk'
    'x' | Set-Content (Join-Path $disc 'f.txt')
    $r = Invoke-Install @(New-AppEntry @{ name = 'Odd'; type = 'rpm'; source = 'f.txt'; dest = (Join-Path $work 'o') }) $disc
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'lists the types it knows' ($r.Output -match 'copy, archive, msi, exe or git')
}

if ('empty' -like $Filter) {
    Start-Case 'an empty list is not an error'
    $disc = New-Disc 'empty'
    $r = Invoke-Install @() $disc
    Confirm-That 'exits zero' ($r.ExitCode -eq 0)
    Confirm-That 'says there was nothing to do' ($r.Output -match 'No apps requested')
}

if ('shortcut' -like $Filter) {
    Start-Case 'shortcut: a target that is not there is reported, not fatal'
    $disc = New-Disc 'sc'
    New-Item -Path (Join-Path $disc 'App') -ItemType Directory -Force | Out-Null
    'x' | Set-Content (Join-Path $disc 'App\real.exe')
    $dest = Join-Path $work 'out-sc'
    $r = Invoke-Install @(New-AppEntry @{ name = 'App'; type = 'copy'; source = 'App'; dest = $dest; shortcut = 'ghost.exe' }) $disc
    Confirm-That 'exits zero' ($r.ExitCode -eq 0)
    Confirm-That 'says the target is missing' ($r.Output -match 'does not exist')
}

if ('extractor-works' -like $Filter) {
    Start-Case 'archive: a declared extractor is called with src and dest substituted'
    $disc = New-Disc 'extw'
    Copy-Item (Join-Path $fixtures 'encrypted.7z') (Join-Path $disc 'enc.7z')
    # Stands in for 7z.exe: proves the template is substituted and the result
    # is taken from the staging directory, without installing anything
    $stub = Join-Path $work 'stub-extractor.cmd'
    @(
        '@echo off'
        'if not exist "%~2" mkdir "%~2"'
        'copy /y "%~1" "%~2\extracted.bin" >nul'
    ) | Set-Content -LiteralPath $stub -Encoding ASCII
    $dest = Join-Path $work 'out-extw'

    $r = Invoke-Install @(New-AppEntry @{
            name = 'Secrets'; type = 'archive'; source = 'enc.7z'; dest = $dest
            extractor = $stub; extractor_args = @('{src}', '{dest}')
        }) $disc
    Confirm-That 'exits zero' ($r.ExitCode -eq 0)
    Confirm-That 'what the extractor wrote reaches the destination' (Test-Path (Join-Path $dest 'extracted.bin'))
}

if ('url-no-filename' -like $Filter) {
    Start-Case 'url: a link with no file name in it does not become the work directory'
    $disc = New-Disc 'urlnf'
    $dest = Join-Path $work 'out-urlnf'

    $r = Invoke-Install @(New-AppEntry @{
            name = 'Redirected'; type = 'archive'; url = 'https://example.invalid/fwlink/?id=1'; dest = $dest
        }) $disc
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'fails on the download, not on a directory' ($r.Output -match 'download failed')
    Confirm-That 'nothing reaches the destination' (-not (Test-Path $dest))
}

if ('marker-absolute' -like $Filter) {
    Start-Case 'marker: an installer proves itself with a full path'
    $disc = New-Disc 'mabs'
    '@exit /b 0' | Set-Content -LiteralPath (Join-Path $disc 'setup.cmd') -Encoding ASCII
    $proof = Join-Path $work 'installed-here.txt'
    'x' | Set-Content $proof

    $r = Invoke-Install @(New-AppEntry @{ name = 'Setup'; type = 'exe'; source = 'setup.cmd'; marker = $proof }) $disc
    Confirm-That 'exits zero when the full path is there' ($r.ExitCode -eq 0)

    $r2 = Invoke-Install @(New-AppEntry @{ name = 'Setup'; type = 'exe'; source = 'setup.cmd'; marker = (Join-Path $work 'nowhere.txt') }) $disc
    Confirm-That 'exits non-zero when it is not' ($r2.ExitCode -ne 0)
}

if ('marker-relative-nodest' -like $Filter) {
    Start-Case 'marker: a relative one with no dest is refused, not guessed at'
    $disc = New-Disc 'mrel'
    '@exit /b 0' | Set-Content -LiteralPath (Join-Path $disc 'setup.cmd') -Encoding ASCII

    $r = Invoke-Install @(New-AppEntry @{ name = 'Setup'; type = 'exe'; source = 'setup.cmd'; marker = 'somewhere.exe' }) $disc
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'asks for the full path' ($r.Output -match 'full path')
}

# ------------------------------------------------- Test-ImageState

# It reads the same manifest back on the finished machine, so an app that was
# installed and then lost between provisioners still fails the build
function Invoke-ImageState {
    param([array] $Apps, [string] $Tag)
    $manifest = Join-Path $work "state-$Tag.json"
    ConvertTo-Json @($Apps) -Depth 6 | Set-Content -LiteralPath $manifest -Encoding UTF8
    $env:AppsManifest = $manifest
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testImageState 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
    } finally {
        $ErrorActionPreference = $prev
        Remove-Item Env:\AppsManifest -ErrorAction SilentlyContinue
    }
}

# The machine running the tests is not a built image, so unrelated assertions
# in this script fail here by design - auto-logon, for one. These cases look at
# the app lines and at whether the app is among the failures, never at the exit
# code, which belongs to the whole image.
if ('state-present' -like $Filter) {
    Start-Case 'image state: an app that is on disk is reported present'
    $dest = Join-Path $work 'state-ok'
    New-Item -Path $dest -ItemType Directory -Force | Out-Null
    'x' | Set-Content (Join-Path $dest 'app.exe')

    $r = Invoke-ImageState @(New-AppEntry @{ name = 'Present'; type = 'copy'; dest = $dest; marker = 'app.exe' }) 'present'
    Confirm-That 'reports the app present' ($r.Output -match 'App Present\s+present')
    Confirm-That 'reports the marker present' ($r.Output -match 'marker app\.exe\s+present')
    Confirm-That 'the app is not among the failures' ($r.Output -notmatch '- App Present')
}

if ('state-absent' -like $Filter) {
    Start-Case 'image state: an app that vanished fails the build'
    $r = Invoke-ImageState @(New-AppEntry @{ name = 'Gone'; type = 'copy'; dest = (Join-Path $work 'never-made'); marker = 'x.exe' }) 'absent'
    Confirm-That 'exits non-zero' ($r.ExitCode -ne 0)
    Confirm-That 'reports it absent' ($r.Output -match 'App Gone\s+absent')
    Confirm-That 'lists it among the failures' ($r.Output -match '- App Gone')
}

# -------------------------------------------------------------- report

Write-Host ''
$failed = 0
foreach ($name in $results.Keys) {
    $claims = $results[$name]
    $bad = @($claims | Where-Object { -not $_.Holds })
    if ($bad.Count -eq 0) {
        Write-Host ("  PASS  " + $name) -ForegroundColor Green
    } else {
        $failed++
        Write-Host ("  FAIL  " + $name) -ForegroundColor Red
        foreach ($c in $bad) { Write-Host ("          not true: " + $c.Claim) -ForegroundColor Red }
    }
}

Write-Host ''
Write-Host ("$($results.Count) case(s), $failed failed")

if ($failed -eq 0) {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Left in place for inspection: $work" -ForegroundColor Yellow
}

exit $failed
