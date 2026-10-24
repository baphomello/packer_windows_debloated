# Packer runs this as shutdown_command, so it has one job: leave the machine
# powered off.
#
# When sysprep refuses, its reason sits in a log file inside a VM that Packer is
# about to delete. So the log is printed here, where the build console keeps it.

$ErrorActionPreference = 'Stop'

$sysprepDir = 'C:\Windows\System32\Sysprep'
$succeeded = Join-Path $sysprepDir 'Sysprep_succeeded.tag'
$pantherDir = Join-Path $sysprepDir 'Panther'

function Stop-Machine {
    # p:4:1 records a planned application shutdown, so the next boot does not
    # open the "why did this machine stop" dialog
    & shutdown.exe /s /t 5 /f /d p:4:1
    exit 0
}

if ('${generalize}' -ne 'true') {
    Write-Output 'generalize is false, shutting down without sysprep.'
    Stop-Machine
}

# A retried shutdown step must not generalize twice: the second run fails on an
# already generalized image and leaves the VM running.
if (Test-Path -LiteralPath $succeeded) {
    Write-Output 'Image is already generalized, shutting down.'
    Stop-Machine
}

& "$sysprepDir\sysprep.exe" /quiet /generalize /oobe /shutdown /mode:vm /unattend:'C:\Windows\Panther\sysprep-unattend.xml'
$code = $LASTEXITCODE

# A successful sysprep powers the machine off from here, and nothing below runs
Start-Sleep -Seconds 30

if (Test-Path -LiteralPath $succeeded) {
    Write-Output 'sysprep reported success.'
    Stop-Machine
}

Write-Output "sysprep exited with $code and the machine is still running. Its own log follows."
foreach ($name in @('setuperr.log', 'setupact.log')) {
    $log = Join-Path $pantherDir $name
    if (-not (Test-Path -LiteralPath $log)) { continue }
    Write-Output "--- $log (last 40 lines) ---"
    Get-Content -LiteralPath $log -Tail 40
}
Write-Output "Answer [a] at the Packer prompt to keep this VM, then read $pantherDir in full."
Write-Output 'Or set generalize = false to build without sysprep.'

exit 1
