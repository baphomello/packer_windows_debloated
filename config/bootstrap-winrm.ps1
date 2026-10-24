# Runs once from the unattend CD at first logon, before Packer can reach the guest.
# Plain HTTP with Basic auth is acceptable because the build network is the host's
# own virtual switch; the image never keeps these settings in production use.
$ErrorActionPreference = 'Stop'

# WinRM refuses to listen while the profile is Public, and the profile takes a
# moment to settle after OOBE.
for ($i = 0; $i -lt 30; $i++) {
    try {
        Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}

Enable-PSRemoting -Force -SkipNetworkProfileCheck

Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 2048
Set-Item -Path WSMan:\localhost\MaxTimeoutms -Value 1800000

# Without this a network logon by a local admin gets a filtered token
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    -Name LocalAccountTokenFilterPolicy -PropertyType DWord -Value 1 -Force | Out-Null

if (-not (Get-NetFirewallRule -Name 'Packer-WinRM-HTTP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'Packer-WinRM-HTTP' -DisplayName 'WinRM HTTP (Packer)' `
        -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any | Out-Null
}

Set-Service -Name WinRM -StartupType Automatic
Restart-Service -Name WinRM
