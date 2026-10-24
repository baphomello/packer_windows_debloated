# Redistributables the payload may need. Nothing is installed unless asked for:
# a minimal image stays minimal by default.
#
# WebView2 is the one worth knowing about. Remove-Bloat.ps1 uninstalls Edge, and
# any payload that hosts a browser control - a .NET launcher, an Electron-style
# UI - needs that runtime present on its own.
#
# Many older applications carry their private VC runtimes next to their
# executable and need no redistributable at all. Check before turning these on.

$packages = @()
if ($env:InstallWebView2 -eq 'true') {
    $packages += @{ Name = 'WebView2 Evergreen'; Url = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'; File = 'MicrosoftEdgeWebview2Setup.exe'; Args = @('/silent', '/install') }
}
if ($env:InstallVcRedist -eq 'true') {
    $packages += @{ Name = 'VC++ 2015-2022 x86'; Url = 'https://aka.ms/vs/17/release/vc_redist.x86.exe'; File = 'vc_redist.x86.exe'; Args = @('/install', '/quiet', '/norestart') }
    $packages += @{ Name = 'VC++ 2015-2022 x64'; Url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'; File = 'vc_redist.x64.exe'; Args = @('/install', '/quiet', '/norestart') }
}

if ($packages.Count -eq 0) {
    Write-Output 'No runtimes requested.'
    exit 0
}

$work = 'C:\Windows\Temp\runtimes'
New-Item -Path $work -ItemType Directory -Force | Out-Null

foreach ($pkg in $packages) {
    $path = Join-Path $work $pkg.File
    & curl.exe --location --silent --show-error --fail --retry 3 --output $path $pkg.Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed for $($pkg.Name) ($($pkg.Url))"
    }

    $proc = Start-Process -FilePath $path -ArgumentList $pkg.Args -Wait -PassThru
    # 1638 is "a newer version is already installed", 3010 is "reboot pending"
    if ($proc.ExitCode -notin @(0, 1638, 3010)) {
        throw "$($pkg.Name) installer exited with $($proc.ExitCode)"
    }
    Write-Output "$($pkg.Name): exit $($proc.ExitCode)"
}

Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue

if ($env:InstallWebView2 -eq 'true') {
    $webview = Get-ChildItem 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application' -Directory -ErrorAction SilentlyContinue |
        Select-Object -Last 1
    Write-Output "WebView2 runtime: $(if ($webview) { $webview.Name } else { 'NOT FOUND' })"
}

exit 0
