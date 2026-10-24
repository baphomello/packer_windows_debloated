# Windows Update is off for the life of the image, not just deferred.
#
# The reason is downtime: an update reboot kills every running session at once,
# and a patch that changes a kernel surface is exactly what breaks software
# bound to it. These VMs are disposable, so the image gets rebuilt, not patched.
#
# Three layers, because any one of them alone gets repaired by the OS:
#   policy      nothing asks for updates
#   dead server any manual check fails immediately instead of reaching Microsoft
#   services    the orchestrator and its medic cannot run to undo the above

if ($env:DisableWindowsUpdate -ne 'true') {
    Write-Output 'disable_windows_update is false, leaving Windows Update alone.'
    exit 0
}

function Set-RegValue {
    param([string] $Path, [string] $Name, $Value, [string] $Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

Set-RegValue -Path $wu -Name 'DisableWindowsUpdateAccess' -Value 1
Set-RegValue -Path $wu -Name 'DoNotConnectToWindowsUpdateInternetLocations' -Value 1
Set-RegValue -Path $wu -Name 'SetDisableUXWUAccess' -Value 1
Set-RegValue -Path $wu -Name 'ExcludeWUDriversInQualityUpdate' -Value 1
foreach ($source in @('QualityUpdates', 'FeatureUpdates', 'DriverUpdates', 'OtherUpdates')) {
    Set-RegValue -Path $wu -Name "SetPolicyDrivenUpdateSourceFor$source" -Value 1
}

# Pointing the update client at a WSUS server that does not exist turns a manual
# "check for updates" into an instant failure
Set-RegValue -Path $wu -Name 'WUServer' -Value 'http://127.0.0.1:8530' -Type String
Set-RegValue -Path $wu -Name 'WUStatusServer' -Value 'http://127.0.0.1:8530' -Type String
Set-RegValue -Path "$wu\AU" -Name 'UseWUServer' -Value 1
Set-RegValue -Path "$wu\AU" -Name 'NoAutoUpdate' -Value 1
Set-RegValue -Path "$wu\AU" -Name 'AutoInstallMinorUpdates' -Value 0
Set-RegValue -Path "$wu\AU" -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1

# Drivers and device metadata come from the ISO or not at all
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' -Name 'DontSearchWindowsUpdate' -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' -Name 'DontPromptForWindowsUpdate' -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'SearchOrderConfig' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' -Name 'PreventDeviceMetadataFromNetwork' -Value 1

$services = @('wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'DoSvc', 'uhssvc', 'sedsvc', 'InstallService')
foreach ($name in $services) {
    if (Get-Service -Name $name -ErrorAction SilentlyContinue) {
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
    }
    # The service keys resist Set-Service on some builds, and WaaSMedic flips
    # wuauserv back on, so the start type is written directly as well
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (Test-Path -LiteralPath $key) {
        try {
            Set-ItemProperty -LiteralPath $key -Name 'Start' -Value 4 -ErrorAction Stop
        } catch {
            Write-Output "Start type not written for ${name}: $($_.Exception.Message)"
        }
    }
}

foreach ($folder in @(
    '\Microsoft\Windows\UpdateOrchestrator\',
    '\Microsoft\Windows\WindowsUpdate\',
    '\Microsoft\Windows\InstallService\',
    '\Microsoft\Windows\WaaSMedic\'
)) {
    foreach ($task in (Get-ScheduledTask -TaskPath $folder -ErrorAction SilentlyContinue)) {
        try {
            Disable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop | Out-Null
        } catch {
            Write-Output "Task protected: $($task.TaskPath)$($task.TaskName)"
        }
    }
}

# Reserved storage holds back several GB for updates that will never arrive
& dism.exe /Online /Set-ReservedStorageState /State:Disabled
Write-Output "Reserved storage disable exit code: $LASTEXITCODE"

Write-Output '--- update services after changes ---'
foreach ($name in $services) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Output ("{0,-14} {1}" -f $svc.Name, $svc.StartType)
    }
}

exit 0
