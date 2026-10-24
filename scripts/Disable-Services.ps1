# Services this image has no use for. Every entry is something a single-purpose
# VM with no printer, no camera, no Store and no domain never calls.
#
# Deliberately left running. Each one is something a desktop application, an
# installer or an anticheat reaches for, and the cost of keeping it is nil:
#   BFE, MpsSvc        firewall filters; software adds its own rules through them
#   CryptSvc           signature verification, including for kernel drivers
#   Winmgmt            WMI, queried by installers and anticheats at startup
#   Schedule, AppInfo  task scheduler and UAC elevation
#   W32Time            a skewed clock breaks TLS and signed sessions
#   Audiosrv, AudioEndpointBuilder   applications that open an audio device at launch
#   TermService, SessionEnv, UmRdpService   this is how the VM is operated
#   Themes, ProfSvc, gpsvc, EventLog, Dnscache, NlaSvc, netprofm, Wcmsvc

$disable = @(
    # Telemetry and diagnostics
    'DiagTrack', 'dmwappushservice', 'diagnosticshub.standardcollector.service', 'diagsvc',
    'DPS', 'WdiServiceHost', 'WdiSystemHost', 'WerSvc', 'wercplsupport',

    # Indexing and prefetching: pure IO cost on a single-purpose machine
    'WSearch', 'SysMain',

    # Hardware this VM does not have
    'Spooler', 'PrintNotify', 'Fax', 'stisvc', 'WbioSrvc', 'SCardSvr', 'ScDeviceEnum',
    'SEMgrSvc', 'SensorService', 'SensrSvc', 'SensorDataService', 'camsvc', 'GameInputSvc',
    'TabletInputService', 'SharedRealitySvc', 'SpatialGraphFilter', 'MixedRealityOpenXRSvc',

    # Consumer and Store plumbing
    'RetailDemo', 'MapsBroker', 'lfsvc', 'PhoneSvc', 'TapiSrv', 'WalletService', 'WpcMonSvc',
    'InstallService', 'LicenseManager', 'WpnService', 'NcbService', 'CDPSvc', 'WMPNetworkSvc',
    'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc', 'AssignedAccessManagerSvc',

    # The update stack itself is handled in Disable-WindowsUpdate.ps1
    'edgeupdate', 'edgeupdatem', 'MicrosoftEdgeElevationService',

    # Remote and networking features unused here
    'RemoteRegistry', 'RemoteAccess', 'SharedAccess', 'icssvc', 'TrkWks', 'Netlogon', 'CscService',
    'wisvc', 'AppVClient', 'UevAgentService'
)

# Per-user service templates: Set-Service cannot see them, only the template key
$disableUserServices = @(
    'OneSyncSvc', 'MessagingService', 'PimIndexMaintenanceSvc', 'UnistoreSvc', 'UserDataSvc',
    'CDPUserSvc', 'WpnUserService', 'BcastDVRUserService', 'PrintWorkflowUserSvc',
    'DevicePickerUserSvc', 'DevicesFlowUserSvc', 'ConsentUxUserSvc'
)

$done = 0
foreach ($name in $disable) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) { continue }
    try {
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
        $done++
    } catch {
        Write-Output "Service kept: ${name} ($($_.Exception.Message))"
    }
}

foreach ($name in $disableUserServices) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (-not (Test-Path -LiteralPath $key)) { continue }
    try {
        Set-ItemProperty -LiteralPath $key -Name 'Start' -Value 4 -ErrorAction Stop
        $done++
    } catch {
        Write-Output "User service kept: ${name} ($($_.Exception.Message))"
    }
}

# BITS is left on manual start: updaters and launchers transfer through it
Set-Service -Name BITS -StartupType Manual -ErrorAction SilentlyContinue

function Disable-Task {
    param([Parameter(Mandatory)][string] $FullPath)
    $leaf = Split-Path $FullPath -Leaf
    $parent = Split-Path $FullPath -Parent
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq '\') { $parent = '' }
    try {
        Disable-ScheduledTask -TaskPath "$parent\" -TaskName $leaf -ErrorAction Stop | Out-Null
    } catch {
        Write-Output "Task absent or protected: $FullPath"
    }
}

$tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\Maintenance\WinSAT',
    '\Microsoft\Windows\Defrag\ScheduledDefrag',
    '\Microsoft\Windows\Clip\License Validation',
    '\Microsoft\Windows\InstallService\ScanForUpdates',
    '\Microsoft\Windows\InstallService\ScanForUpdatesAsUser',
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan',
    '\Microsoft\Windows\WindowsUpdate\Scheduled Start',
    '\MicrosoftEdgeUpdateTaskMachineCore',
    '\MicrosoftEdgeUpdateTaskMachineUA',
    # Named individually rather than by folder: \Shell\ also holds
    # CreateObjectTask, which is COM activation for the shell itself
    '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
    '\Microsoft\Windows\Shell\IndexerAutomaticMaintenance'
)

foreach ($task in $tasks) {
    Disable-Task -FullPath $task
}

# Whole folders whose every task is for hardware, services or features this
# image does not have. Enumerated instead of listed, because the contents move
# between Windows builds.
foreach ($folder in @(
    '\Microsoft\Windows\Flighting\',
    '\Microsoft\Windows\RetailDemo\',
    '\Microsoft\Windows\Speech\',
    '\Microsoft\Windows\Maps\',
    '\Microsoft\Windows\Printing\',
    '\Microsoft\Windows\PushToInstall\',
    '\Microsoft\Windows\License Manager\',
    '\Microsoft\Windows\WwanSvc\',
    '\Microsoft\Windows\Power Efficiency Diagnostics\',
    '\Microsoft\Windows\MemoryDiagnostic\',
    '\Microsoft\Windows\WindowsBackup\',
    '\Microsoft\Windows\Device Information\',
    '\Microsoft\Windows\Diagnosis\',
    '\Microsoft\Windows\DiskFootprint\',
    '\Microsoft\Windows\Offline Files\'
)) {
    foreach ($task in (Get-ScheduledTask -TaskPath $folder -ErrorAction SilentlyContinue)) {
        try {
            Disable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop | Out-Null
        } catch {
            Write-Output "Task protected: $($task.TaskPath)$($task.TaskName)"
        }
    }
}

Write-Output "Disabled $done services."

exit 0
