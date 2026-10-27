# Removes the preinstalled apps, capabilities and features.
#
# The list is explicit instead of "remove everything except a keep list": the
# Windows 11 shell itself ships as packages (FileExp, Client.CBS, Client.Core,
# StartMenuExperienceHost, CloudExperienceHost), and a clone still has to boot
# through OOBE after sysprep. Naming what goes keeps that from breaking.

if ($env:RemoveAppx -ne 'true' -and $env:RemoveEdge -ne 'true') {
    Write-Output 'remove_appx and remove_edge are false, nothing to remove.'
    exit 0
}

$appx = @(
    'Clipchamp.Clipchamp'
    'Microsoft.3DBuilder'
    'Microsoft.549981C3F5F10'
    'Microsoft.BingNews'
    'Microsoft.BingSearch'
    'Microsoft.BingWeather'
    'Microsoft.Copilot'
    'Microsoft.Edge.GameAssist'
    'Microsoft.GamingApp'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.Messaging'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MicrosoftJournal'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.MixedReality.Portal'
    'Microsoft.MSPaint'
    'Microsoft.Office.OneNote'
    'Microsoft.OneDriveSync'
    'Microsoft.OutlookForWindows'
    'Microsoft.Paint'
    'Microsoft.People'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.ScreenSketch'
    'Microsoft.SkypeApp'
    'Microsoft.StorePurchaseApp'
    'Microsoft.Todos'
    'Microsoft.Wallet'
    'Microsoft.WidgetsPlatformRuntime'
    'Microsoft.Windows.Ai.Copilot.Provider'
    'Microsoft.Windows.DevHome'
    'Microsoft.Windows.Photos'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsCamera'
    'microsoft.windowscommunicationsapps'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.WindowsStore'
    'Microsoft.WindowsTerminal'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'MicrosoftCorporationII.MicrosoftFamily'
    'MicrosoftCorporationII.QuickAssist'
    'MicrosoftTeams'
    'MSTeams'
    'MicrosoftWindows.Client.WebExperience'
    'MicrosoftWindows.CrossDevice'
    'Microsoft.WindowsCalculator'
    'Microsoft.ApplicationCompatibilityEnhancements'

    # Store codecs for Explorer and Photos, both of which are gone. A desktop
    # application decodes its own audio and video, and WebView2 carries Chromium's
    # codecs rather than using these.
    'Microsoft.AV1VideoExtension'
    'Microsoft.AVCEncoderVideoExtension'
    'Microsoft.HEIFImageExtension'
    'Microsoft.HEVCVideoExtension'
    'Microsoft.MPEG2VideoExtension'
    'Microsoft.RawImageExtension'
    'Microsoft.VP9VideoExtensions'
    'Microsoft.WebMediaExtensions'
    'Microsoft.WebpImageExtension'
)

# Kept on purpose: Notepad, for editing a payload's ini files from inside the VM

# Both halves matter: sysprep /generalize fails when a package is installed for
# a user but no longer provisioned for all users
$removed = 0
$appxToRemove = if ($env:RemoveAppx -eq 'true') { $appx } else { @() }
foreach ($name in $appxToRemove) {
    foreach ($pkg in (Get-AppxPackage -Name $name -AllUsers -ErrorAction SilentlyContinue)) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            $removed++
        } catch {
            Write-Output "Appx kept: $($pkg.PackageFullName)"
        }
    }
    foreach ($prov in (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $name)) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
            $removed++
        } catch {
            Write-Output "Provisioned appx kept: $($prov.PackageName)"
        }
    }
}

$capabilities = @(
    'App.StepsRecorder'
    'App.Support.QuickAssist'
    'Browser.InternetExplorer'
    'Hello.Face.18967'
    'Hello.Face.Migration.18967'
    'Language.Handwriting'
    'Language.OCR'
    'Language.Speech'
    'Language.TextToSpeech'
    'MathRecognizer'
    'Media.WindowsMediaPlayer'
    'Microsoft.Windows.MSPaint'
    'Microsoft.Windows.PowerShell.ISE'
    'Microsoft.Windows.WordPad'
    'OneCoreUAP.OneSync'
    'Print.Fax.Scan'
    'Print.Management.Console'
    'XPS.Viewer'
)

$wantedCapabilities = if ($env:RemoveAppx -eq 'true') { $capabilities } else { @() }
foreach ($prefix in $wantedCapabilities) {
    foreach ($cap in (Get-WindowsCapability -Online | Where-Object { $_.Name -like "$prefix*" -and $_.State -eq 'Installed' })) {
        try {
            Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
            $removed++
        } catch {
            Write-Output "Capability kept: $($cap.Name)"
        }
    }
}

# Recall ships as an optional feature on recent builds; the policy in
# Set-Policies.ps1 disables it, this removes the payload
$features = @(
    'Recall'
    'MediaPlayback'
    'WindowsMediaPlayer'
    'Printing-XPSServices-Features'
    'WorkFolders-Client'
    'MicrosoftWindowsPowerShellV2Root'
    'SmbDirect'
)

$wantedFeatures = if ($env:RemoveAppx -eq 'true') { $features } else { @() }
foreach ($feature in $wantedFeatures) {
    $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
    if (-not $f -or $f.State -ne 'Enabled') { continue }
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop | Out-Null
        $removed++
    } catch {
        Write-Output "Feature kept: $feature"
    }
}

# Edge: Microsoft only honours this uninstall in some regions, so the result is
# reported rather than assumed. WebView2 is left installed because a payload
# launcher may host a browser control.
if ($env:RemoveEdge -eq 'true') {
    foreach ($pkg in (Get-AppxPackage -Name 'Microsoft.MicrosoftEdge.Stable' -AllUsers -ErrorAction SilentlyContinue)) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            $removed++
        } catch {
            Write-Output "Edge appx kept: $($pkg.PackageFullName)"
        }
    }
}

$edgeSetup = $null
if ($env:RemoveEdge -eq 'true') {
    $edgeSetup = Get-ChildItem 'C:\Program Files (x86)\Microsoft\Edge\Application' -Filter 'setup.exe' -Recurse -ErrorAction SilentlyContinue |
        Where-Object FullName -like '*\Installer\setup.exe' | Select-Object -First 1
}
if ($edgeSetup) {
    Start-Process -FilePath $edgeSetup.FullName `
        -ArgumentList '--uninstall', '--system-level', '--verbose-logging', '--force-uninstall' `
        -Wait -ErrorAction SilentlyContinue
}
$edgeLeft = Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
Write-Output "Edge still installed: $edgeLeft"

foreach ($oneDrive in @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe")) {
    if (Test-Path $oneDrive) {
        Start-Process -FilePath $oneDrive -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
    }
}

Write-Output "Removed $removed packages, capabilities and features."

exit 0
