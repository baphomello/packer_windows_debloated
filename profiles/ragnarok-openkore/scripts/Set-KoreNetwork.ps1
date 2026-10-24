# Applies the OpenKore link at build time, when the layout is known that early.
# It usually is not: each clone points at its own OpenKore instance, so the tool
# and its defaults stay in C:\Tools to be re-run per VM.

$config = 'C:\Tools\config.json'
if (-not (Test-Path -LiteralPath $config)) {
    Write-Output 'No config.json in the image, skipping.'
    exit 0
}

$mode = (Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).Mode
if (-not $mode -or $mode -eq 'none') {
    Write-Output 'kore_mode is none: configure this VM later with C:\Tools\Set-KoreLink.ps1.'
    exit 0
}

# Nothing is listening during the build, so the reachability probe is pointless here
& 'C:\Tools\Set-KoreLink.ps1' -SkipTest
exit 0
