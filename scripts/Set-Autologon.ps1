# The clients run inside an interactive desktop session, so that session has to
# come up by itself after every boot and never lock, time out or sleep.

$user = $env:AdminUsername
$password = $env:AdminPassword

function Set-RegValue {
    param([string] $Path, [string] $Name, $Value, [string] $Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-RegValue -Path $winlogon -Name 'AutoAdminLogon' -Value '1' -Type String
Set-RegValue -Path $winlogon -Name 'DefaultUserName' -Value $user -Type String
Set-RegValue -Path $winlogon -Name 'DefaultPassword' -Value $password -Type String
Set-RegValue -Path $winlogon -Name 'ForceAutoLogon' -Value '1' -Type String

# A stale domain name survives the rename sysprep gives each clone and breaks
# the logon, so the value is removed instead of pinned to this hostname
Remove-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -ErrorAction SilentlyContinue

# Winlogon decrements AutoLogonCount on every auto-logon and, on reaching zero,
# deletes the count, deletes DefaultPassword and sets AutoAdminLogon to 0. An
# unlimited auto-logon is the absence of this value, never a zero in it.
Remove-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

Set-RegValue -Path $winlogon -Name 'DisableLockWorkstation' -Value 1

Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'InactivityTimeoutSecs' -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DisableLockWorkstation' -Value 1

Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveActive' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaverIsSecure' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveTimeOut' -Value '0' -Type String

# No password prompt when the console display wakes up
powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
powercfg /setactive SCHEME_CURRENT

# An unattended session has nobody to approve an elevation prompt, and plenty of
# desktop software elevates on launch. UAC stays on; only the prompt for this
# administrator is silenced.
$uac = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Set-RegValue -Path $uac -Name 'EnableLUA' -Value 1
Set-RegValue -Path $uac -Name 'ConsentPromptBehaviorAdmin' -Value 0
Set-RegValue -Path $uac -Name 'PromptOnSecureDesktop' -Value 0

# An expired password locks every client out of its session at once
Set-LocalUser -Name $user -PasswordNeverExpires $true
net accounts /maxpwage:unlimited | Out-Null

Write-Output "Auto-logon configured for ${user}."

exit 0
