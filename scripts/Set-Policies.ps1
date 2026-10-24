# Machine policies that strip everything this image will never use: telemetry,
# cloud content, Copilot/Recall, Store, Windows Update, Edge and SmartScreen.
# Policies run before the removals so nothing reinstalls itself behind us.

function Set-RegValue {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)] $Value,
        [string] $Type = 'DWord'
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

$pol = 'HKLM:\SOFTWARE\Policies\Microsoft'
$hklm = 'HKLM:\SOFTWARE\Microsoft'

$policies = @(
    # Telemetry and feedback
    @{ Path = "$pol\Windows\DataCollection"; Name = 'AllowTelemetry';                 Value = 0 }
    @{ Path = "$pol\Windows\DataCollection"; Name = 'AllowDeviceNameInTelemetry';     Value = 0 }
    @{ Path = "$pol\Windows\DataCollection"; Name = 'DoNotShowFeedbackNotifications'; Value = 1 }
    @{ Path = "$pol\Windows\DataCollection"; Name = 'DisableOneSettingsDownloads';    Value = 1 }
    @{ Path = "$pol\Windows\DataCollection"; Name = 'LimitDiagnosticLogCollection';   Value = 1 }
    @{ Path = "$pol\SQMClient\Windows";      Name = 'CEIPEnable';                     Value = 0 }
    @{ Path = "$pol\Windows\AdvertisingInfo"; Name = 'DisabledByGroupPolicy';         Value = 1 }

    # Consumer content, suggested apps, spotlight
    @{ Path = "$pol\Windows\CloudContent"; Name = 'DisableWindowsConsumerFeatures';      Value = 1 }
    @{ Path = "$pol\Windows\CloudContent"; Name = 'DisableCloudOptimizedContent';        Value = 1 }
    @{ Path = "$pol\Windows\CloudContent"; Name = 'DisableConsumerAccountStateContent';  Value = 1 }
    @{ Path = "$pol\Windows\CloudContent"; Name = 'DisableSoftLanding';                  Value = 1 }
    @{ Path = "$pol\Windows\CloudContent"; Name = 'DisableWindowsSpotlightFeatures';     Value = 1 }

    # Copilot and the on-device AI stack, including Recall's screenshot capture
    @{ Path = "$pol\Windows\WindowsCopilot"; Name = 'TurnOffWindowsCopilot';   Value = 1 }
    @{ Path = "$pol\Windows\WindowsAI";      Name = 'DisableAIDataAnalysis';   Value = 1 }
    @{ Path = "$pol\Windows\WindowsAI";      Name = 'AllowRecallEnablement';   Value = 0 }
    @{ Path = "$pol\Windows\WindowsAI";      Name = 'DisableClickToDo';        Value = 1 }
    @{ Path = "$pol\Windows\WindowsAI";      Name = 'DisableImageCreator';     Value = 1 }
    @{ Path = "$pol\Windows\WindowsAI";      Name = 'DisableCocreator';        Value = 1 }
    @{ Path = "$pol\Windows\WindowsAI";      Name = 'DisableGenerativeFill';   Value = 1 }
    @{ Path = "$pol\Dsh";                    Name = 'AllowNewsAndInterests';   Value = 0 }

    # Search stays local: no indexer, no web results
    @{ Path = "$pol\Windows\Windows Search"; Name = 'AllowCortana';                Value = 0 }
    @{ Path = "$pol\Windows\Windows Search"; Name = 'AllowCloudSearch';            Value = 0 }
    @{ Path = "$pol\Windows\Windows Search"; Name = 'DisableWebSearch';            Value = 1 }
    @{ Path = "$pol\Windows\Windows Search"; Name = 'ConnectedSearchUseWeb';       Value = 0 }
    @{ Path = "$pol\Windows\Windows Search"; Name = 'EnableDynamicContentInWSB';   Value = 0 }

    # Store: nothing here is ever installed from it
    @{ Path = "$pol\WindowsStore"; Name = 'RemoveWindowsStore'; Value = 1 }
    @{ Path = "$pol\WindowsStore"; Name = 'AutoDownload';       Value = 2 }

    # Windows Update is handled on its own in Disable-WindowsUpdate.ps1

    # Error reporting and crash upload
    @{ Path = "$pol\Windows\Windows Error Reporting"; Name = 'Disabled';             Value = 1 }
    @{ Path = "$pol\Windows\Windows Error Reporting"; Name = 'DontSendAdditionalData'; Value = 1 }

    # OneDrive never gets a chance to start
    @{ Path = "$pol\Windows\OneDrive"; Name = 'DisableFileSyncNGSC'; Value = 1 }

    # Edge is uninstalled in Remove-Bloat.ps1; these keep its updater from bringing it back
    @{ Path = "$pol\EdgeUpdate"; Name = 'InstallDefault';                Value = 0 }
    @{ Path = "$pol\EdgeUpdate"; Name = 'UpdateDefault';                 Value = 0 }
    @{ Path = "$pol\EdgeUpdate"; Name = 'AutoUpdateCheckPeriodMinutes';  Value = 0 }
    @{ Path = "$pol\EdgeUpdate"; Name = 'CreateDesktopShortcutDefault';  Value = 0 }

    # SmartScreen and the attachment manager would otherwise flag every
    # unsigned payload binary and self-update as an unknown publisher
    @{ Path = "$pol\Windows\System"; Name = 'EnableSmartScreen'; Value = 0 }
    @{ Path = "$hklm\Windows\CurrentVersion\Explorer"; Name = 'SmartScreenEnabled'; Value = 'Off'; Type = 'String' }

    # No logon animation, no first-run tour
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableFirstLogonAnimation'; Value = 0 }

    # Game Bar and the capture overlay inject themselves into foreground processes
    @{ Path = "$pol\Windows\GameDVR"; Name = 'AllowGameDVR'; Value = 0 }

    # Application compatibility telemetry: the appraiser walks installed
    # software in the background and reports it
    @{ Path = "$pol\Windows\AppCompat"; Name = 'AITEnable';        Value = 0 }
    @{ Path = "$pol\Windows\AppCompat"; Name = 'DisableInventory'; Value = 1 }
    @{ Path = "$pol\Windows\AppCompat"; Name = 'DisableUAR';       Value = 1 }
    @{ Path = "$hklm\Windows\CurrentVersion\Diagnostics\DiagTrack\EventTranscriptKey"; Name = 'EnableEventTranscript'; Value = 0 }

    # Timeline and activity history, uploaded to the account that is not here
    @{ Path = "$pol\Windows\System"; Name = 'EnableActivityFeed';    Value = 0 }
    @{ Path = "$pol\Windows\System"; Name = 'PublishUserActivities'; Value = 0 }
    @{ Path = "$pol\Windows\System"; Name = 'UploadUserActivities';  Value = 0 }

    # Typing and speech personalization
    @{ Path = "$pol\InputPersonalization"; Name = 'AllowLinguisticDataCollection'; Value = 0 }
    @{ Path = "$pol\Windows\AppPrivacy";  Name = 'LetAppsRunInBackground';        Value = 2 }

    # A VM has no location to report, and the sensor stack polls for one anyway
    @{ Path = "$hklm\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"; Name = 'Value'; Value = 'Deny'; Type = 'String' }
    @{ Path = 'HKLM:\SYSTEM\Maps'; Name = 'AutoUpdateEnabled'; Value = 0 }

    # Start menu recommendations fetch content in the background
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'; Name = 'HideRecommendedSection'; Value = 1 }
    @{ Path = "$pol\Windows\Explorer"; Name = 'HideRecommendedSection'; Value = 1 }

    # Driver co-installers arrive with vendor software attached
    @{ Path = "$hklm\Windows\CurrentVersion\Device Installer"; Name = 'DisableCoInstallers'; Value = 1 }
)

# Virtualization based security costs CPU inside an already virtual machine and
# is the usual suspect when a kernel anticheat driver fails to load
if ($env:DisableVbs -eq 'true') {
    $policies += @(
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'RequirePlatformSecurityFeatures';   Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Enabled'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'HVCIMATRequired'; Value = 0 }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'LsaCfgFlags'; Value = 0 }
    )
}

foreach ($p in $policies) {
    $type = if ($p.ContainsKey('Type')) { $p.Type } else { 'DWord' }
    Set-RegValue -Path $p.Path -Name $p.Name -Value $p.Value -Type $type
}

# Per-user content push for the auto-logon account
$cdm = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($name in @(
    'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
    'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled',
    'SystemPaneSuggestionsEnabled', 'SubscribedContent-310093Enabled',
    'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
    'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled',
    'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
    'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled'
)) {
    Set-RegValue -Path $cdm -Name $name -Value 0
}

# Notifications: a toast over a full screen application steals focus, and
# nobody is at the console to read it anyway
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'ToastEnabled' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'DisableNotificationCenter' -Value 1
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 1

# Typing, inking and speech personalization for this user
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' -Name 'RestrictImplicitInkCollection' -Value 1
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' -Name 'RestrictImplicitTextCollection' -Value 1
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' -Name 'HarvestContacts' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings' -Name 'AcceptedPrivacyPolicy' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' -Name 'HasAccepted' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' -Name 'NumberOfSIUFInPeriod' -Value 0

# Taskbar surfaces that only exist to pull content down
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowTaskViewButton' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarMn' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackProgs' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0

# End task from the taskbar, for killing a hung payload without Task Manager
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name 'TaskbarEndTask' -Value 1

# Storage Sense deletes files on its own schedule. Nothing here should vanish
# because Windows decided the disk was filling up.
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -Name '01' -Value 0

Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'ShowStartupPanel' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'UseNexusForGameBarEnabled' -Value 0

# Game Mode starves everything that is not the single foreground game. With
# several equal workloads on one VM that is exactly the wrong trade.
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments' -Name 'SaveZoneInformation' -Value 1

# 0xFF disables every IPv6 interface except loopback and prefers IPv4
# everywhere. This is a network change, which is why it is a switch: a payload
# that resolves or binds over IPv6 needs disable_ipv6 set to false.
if ($env:DisableIpv6 -eq 'true') {
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -Value 0xFF
    Write-Output 'IPv6 disabled (takes effect after the next reboot).'
}

# Trimming the Settings app is not about disk, it is about surface: fewer pages
# that fetch content, fewer things to click into on a machine nobody
# administers. The default keeps display, sound, network, clock and About.
if ($env:SettingsPageVisibility) {
    Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -Name 'SettingsPageVisibility' -Value $env:SettingsPageVisibility -Type String
    Write-Output "Settings pages: $env:SettingsPageVisibility"
}

# Automatic maintenance wakes the machine up to run tasks this image has no use for
Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' -Name 'MaintenanceDisabled' -Value 1

# Single-purpose VMs on a private switch: filtering only adds a variable to the
# payload's traffic. MpsSvc keeps running either way, because software queries
# the firewall service itself.
if ($env:DisableFirewall -eq 'true') {
    Set-NetFirewallProfile -All -Enabled False
}
Write-Output "Firewall profiles enabled: $((Get-NetFirewallProfile).Enabled -join ', ')"

Write-Output 'Policies applied.'

exit 0
