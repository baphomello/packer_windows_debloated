# Packer runs this as shutdown_command, so it has one job: leave the machine
# powered off.
#
# Nothing written here reaches the build console. The Hyper-V builder starts the
# command with its stdout and stderr pointed at buffers it never reads, so when
# sysprep refuses, the reason is written to a file in the guest instead and the
# machine is deliberately left running. Answer [a] at the Packer prompt to keep
# it, then read that file with tools\host\Get-SysprepFailure.ps1 from the host.

$ErrorActionPreference = 'Stop'

$sysprepDir = 'C:\Windows\System32\Sysprep'
$succeeded = Join-Path $sysprepDir 'Sysprep_succeeded.tag'
$pantherDir = Join-Path $sysprepDir 'Panther'
$report = 'C:\sysprep-failed.log'

function Stop-Machine {
    # p:4:1 records a planned application shutdown, so the next boot does not
    # open the "why did this machine stop" dialog
    & shutdown.exe /s /t 5 /f /d p:4:1
    exit 0
}

if ('${generalize}' -ne 'true') {
    Stop-Machine
}

# A retried shutdown step must not generalize twice: the second run fails on an
# already generalized image and leaves the VM running.
if (Test-Path -LiteralPath $succeeded) {
    Stop-Machine
}

Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue

& "$sysprepDir\sysprep.exe" /quiet /generalize /oobe /shutdown /mode:vm /unattend:'C:\Windows\Panther\sysprep-unattend.xml'
$code = $LASTEXITCODE

# A successful sysprep powers the machine off from here, and nothing below runs
Start-Sleep -Seconds 30

if (Test-Path -LiteralPath $succeeded) {
    Stop-Machine
}

$lines = @("sysprep exited with $code at $(Get-Date -Format s) and the machine is still running.")
foreach ($name in @('setuperr.log', 'setupact.log')) {
    $log = Join-Path $pantherDir $name
    if (-not (Test-Path -LiteralPath $log)) {
        $lines += "--- $log is not there ---"
        continue
    }
    $lines += "--- $log (last 60 lines) ---"
    $lines += Get-Content -LiteralPath $log -Tail 60
}
Set-Content -LiteralPath $report -Value $lines -Encoding UTF8

exit 1
