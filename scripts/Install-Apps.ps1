# Installs everything the apps manifest asks for, in the order it asks.
#
# One list, several ways in: a folder copied as-is, an archive unpacked, an MSI
# or an EXE installer run, a repository cloned. Order matters, and it is the
# only ordering there is: an app that needs a tool declares that tool earlier in
# the same list.
#
# Nothing here guesses. Windows ships tar.exe (libarchive), which reads zip, 7z,
# tar.gz and tar.xz, so those need no extra software. It cannot read an
# encrypted archive - worse, it writes empty files and then fails - and a clean
# image has no git. In both cases this stops and names what is missing rather
# than choosing a tool on the user's behalf.

$manifest = 'C:\Windows\Temp\apps.json'
if (-not (Test-Path -LiteralPath $manifest)) {
    Write-Output 'No app manifest, nothing to install.'
    exit 0
}

# Windows PowerShell 5.1 hands a top-level JSON array back as a single object
# rather than enumerating it, so @() around it wraps the array instead of the
# apps in it. Piping is what unrolls it.
$apps = @((Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
if ($apps.Count -eq 0) {
    Write-Output 'No apps requested.'
    exit 0
}

function Get-Field {
    param($App, [string] $Name, $Default = '')
    if (-not $App.PSObject.Properties[$Name]) { return $Default }
    $value = $App.$Name
    if ($null -eq $value) { return $Default }
    if ($value -is [string] -and $value -eq '') { return $Default }
    return $value
}

# Found by volume label, not by letter: the unattend CD is attached too and the
# letters depend on the order Windows enumerated them
function Get-AppsDisc {
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne 'CDRom' -or -not $drive.IsReady) { continue }
        if ($drive.VolumeLabel -ne $env:AppsLabel) { continue }
        return $drive.RootDirectory.FullName
    }
    return $null
}

$disc = Get-AppsDisc
$work = 'C:\Windows\Temp\apps'
New-Item -Path $work -ItemType Directory -Force | Out-Null

# Returns a path on local disk, whatever the app named as its origin
function Resolve-Source {
    param($App, [string] $Name)

    $url = Get-Field $App 'url'
    if ($url) {
        $file = Join-Path $work ([System.IO.Path]::GetFileName($url.Split('?')[0]))
        if (Test-Path -LiteralPath $file) { return $file }
        & curl.exe --location --silent --show-error --fail --retry 3 --output $file $url
        if ($LASTEXITCODE -ne 0) { throw "${Name}: download failed from $url" }
        return $file
    }

    $source = Get-Field $App 'source'
    if (-not $source) { throw "${Name}: needs either 'source' (on the apps disc) or 'url'." }
    if (-not $disc) {
        throw "${Name}: no disc labelled $($env:AppsLabel) is attached, so 'source' cannot be read. Check apps_source_dir and apps_label."
    }
    # A disc built from one application's folder has that folder as its root
    if ($source -eq '.') { return $disc.TrimEnd('\') }
    $path = Join-Path $disc $source
    if (-not (Test-Path -LiteralPath $path)) {
        throw "${Name}: '$source' is not on the apps disc at $disc."
    }
    return $path
}

# Applications that keep state next to their executable - and anticheats that
# rewrite their own files on every launch - need the session account to write
# there, which it does not get by default under a new folder on C:\
function Grant-UserWrite {
    param([string] $Path)
    & icacls.exe $Path /grant '*S-1-5-32-545:(OI)(CI)M' /T /C | Out-Null
}

function New-DesktopShortcut {
    param([string] $Target, [string] $WorkingDir)
    if (-not (Test-Path -LiteralPath $Target)) {
        Write-Output "  shortcut target $Target does not exist, skipped"
        return
    }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Target)
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut("C:\Users\Public\Desktop\$name.lnk")
    $lnk.TargetPath = $Target
    $lnk.WorkingDirectory = $WorkingDir
    $lnk.Save()
    Write-Output "  shortcut: $name"
}

function Install-Copy {
    param($App, [string] $Name, [string] $Source, [string] $Dest)
    & robocopy.exe $Source $Dest /E /COPY:DAT /R:2 /W:2 /MT:8 /NFL /NDL /NJH /NJS | Out-Null
    # robocopy returns a bitmask: under 8 means files were copied, 8 and up is a failure
    if ($LASTEXITCODE -ge 8) { throw "${Name}: robocopy failed with exit code $LASTEXITCODE" }
}

function Install-Archive {
    param($App, [string] $Name, [string] $Source, [string] $Dest)

    # Unpacked beside the destination first. tar.exe answers an encrypted
    # archive by creating every file empty and then failing, so a staging
    # directory is what keeps that wreckage from ever reaching $Dest.
    $stage = Join-Path $work ("stage-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $stage -ItemType Directory -Force | Out-Null

    try {
        $extractor = Get-Field $App 'extractor'
        if ($extractor) {
            if (-not (Test-Path -LiteralPath $extractor)) {
                throw "${Name}: extractor '$extractor' is not installed. Put the app that installs it earlier in the list."
            }
            $template = @(Get-Field $App 'extractor_args')
            # The 7-Zip spelling, because it is what people reach for first
            if ($template.Count -eq 0) { $template = @('x', '{src}', '-o{dest}', '-y') }
            $argv = foreach ($a in $template) { $a.Replace('{src}', $Source).Replace('{dest}', $stage) }
            & $extractor @argv | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "${Name}: $extractor exited with $LASTEXITCODE" }
        } else {
            $output = & tar.exe -xf $Source -C $stage 2>&1
            if ($LASTEXITCODE -ne 0) {
                $text = ($output | Out-String).Trim()
                if ($text -match 'encrypted') {
                    throw ("${Name}: this archive is encrypted and tar.exe cannot read it, so it extracted nothing usable. " +
                           "Declare an extractor on this app - extractor = 'C:/Program Files/7-Zip/7z.exe' with " +
                           "extractor_args, and install it from an earlier entry in the list.")
                }
                throw "${Name}: tar.exe could not extract $Source. $text"
            }
        }

        if (-not (Get-ChildItem -LiteralPath $stage -Recurse -File -ErrorAction SilentlyContinue)) {
            throw "${Name}: the archive unpacked to nothing."
        }

        New-Item -Path $Dest -ItemType Directory -Force | Out-Null
        & robocopy.exe $stage $Dest /E /MOVE /R:2 /W:2 /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "${Name}: moving the unpacked files into $Dest failed ($LASTEXITCODE)" }
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-Msi {
    param($App, [string] $Name, [string] $Source)
    $argv = @(Get-Field $App 'args')
    if ($argv.Count -eq 0) { $argv = @('/qn', '/norestart') }
    $argv = @('/i', $Source) + $argv
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argv -Wait -PassThru
    # 1638 is "a newer version is already installed", 3010 is "reboot pending"
    if ($proc.ExitCode -notin @(0, 1638, 3010)) {
        throw "${Name}: msiexec exited with $($proc.ExitCode)"
    }
    Write-Output "  msiexec: exit $($proc.ExitCode)"
}

function Install-Exe {
    param($App, [string] $Name, [string] $Source)
    $argv = @(Get-Field $App 'args' @())
    if ($argv.Count -gt 0) {
        $proc = Start-Process -FilePath $Source -ArgumentList $argv -Wait -PassThru
    } else {
        $proc = Start-Process -FilePath $Source -Wait -PassThru
    }
    $ok = @(Get-Field $App 'success_exit_codes')
    # 1638 is "a newer version is already installed", 3010 is "reboot pending"
    if ($ok.Count -eq 0) { $ok = @(0, 1638, 3010) }
    if ($proc.ExitCode -notin $ok) {
        throw "${Name}: the installer exited with $($proc.ExitCode), which is not in success_exit_codes."
    }
    Write-Output "  installer: exit $($proc.ExitCode)"
}

function Install-Git {
    param($App, [string] $Name, [string] $Dest)
    if (-not (Get-Command 'git.exe' -ErrorAction SilentlyContinue)) {
        throw ("${Name}: git is not installed, and a clean Windows image does not ship it. " +
               "Add an entry that installs git earlier in the list, or carry the files on the apps disc instead.")
    }
    $url = Get-Field $App 'url'
    if (-not $url) { throw "${Name}: a git app needs 'url'." }

    if (Test-Path -LiteralPath (Join-Path $Dest '.git')) {
        Write-Output '  already cloned'
        return
    }
    $argv = @('clone', '--depth', '1') + @(Get-Field $App 'args' @()) + @($url, $Dest)
    & git.exe @argv 2>&1 | ForEach-Object { Write-Output "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "${Name}: git clone failed with $LASTEXITCODE" }
}

$installed = 0
foreach ($app in $apps) {
    $name = Get-Field $app 'name'
    $type = (Get-Field $app 'type').ToString().ToLower()
    if (-not $name) { throw "Every app needs a 'name'." }
    if (-not $type) { throw "${name}: needs a 'type' (copy, archive, msi, exe or git)." }

    $dest = Get-Field $app 'dest'
    Write-Output "$name ($type)"

    if ($type -eq 'git') {
        if (-not $dest) { throw "${name}: a git app needs 'dest'." }
        Install-Git $app $name $dest
    } else {
        $source = Resolve-Source $app $name
        switch ($type) {
            'copy' {
                if (-not $dest) { throw "${name}: a copy app needs 'dest'." }
                Install-Copy $app $name $source $dest
            }
            'archive' {
                if (-not $dest) { throw "${name}: an archive app needs 'dest'." }
                Install-Archive $app $name $source $dest
            }
            'msi' { Install-Msi $app $name $source }
            'exe' { Install-Exe $app $name $source }
            default { throw "${name}: unknown type '$type'. Use copy, archive, msi, exe or git." }
        }
    }

    $marker = Get-Field $app 'marker'
    if ($marker) {
        $base = $dest
        if (-not $base) { $base = 'C:\' }
        if (-not (Test-Path -LiteralPath (Join-Path $base $marker))) {
            throw "${name}: '$marker' is missing from $base after the install, so something did not land."
        }
    }

    if ($dest -and (Test-Path -LiteralPath $dest)) {
        if ((Get-Field $app 'grant_users' $true) -eq $true) { Grant-UserWrite $dest }
        if ((Get-Field $app 'exclude_from_defender' $true) -eq $true) {
            try { Add-MpPreference -ExclusionPath $dest -ErrorAction Stop } catch {
                Write-Output "  exclusion not applied: $(($_.Exception.Message -replace '\s+', ' ').Trim())"
            }
        }
        $files = @(Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue)
        $size = ($files | Measure-Object Length -Sum).Sum
        Write-Output ("  {0}: {1} files, {2:N2} GB" -f $dest, $files.Count, ($size / 1GB))
    }

    $shortcut = Get-Field $app 'shortcut'
    if ($shortcut -and $dest) { New-DesktopShortcut (Join-Path $dest $shortcut) $dest }

    $installed++
}

# Everything asked for is installed by now, so failing to tidy the scratch
# directory is not a reason to fail the build
try {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Output "Scratch directory left behind: $work"
}

Write-Output "$installed app(s) installed."

exit 0
