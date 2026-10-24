# Dark theme, and no wallpaper bitmap anywhere.
#
# The theme is a per-user setting, so one hive is not enough:
#   HKCU                   the auto-logon session
#   HKU\.DEFAULT           the logon screen and anything running as SYSTEM
#   C:\Users\Default       every profile created later, including the first
#                          boot of a sysprep clone
#
# The solid background is not only cosmetic: a wallpaper is a bitmap decoded
# and held per session, and this image has no use for one.

if ($env:DarkMode -ne 'true') {
    Write-Output 'dark_mode is false, leaving the theme alone.'
    exit 0
}

function Set-RegValue {
    param([string] $Path, [string] $Name, $Value, [string] $Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Set-UserAppearance {
    param([Parameter(Mandatory)][string] $Root)

    Set-RegValue -Path "$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name 'AppsUseLightTheme' -Value 0
    Set-RegValue -Path "$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name 'SystemUsesLightTheme' -Value 0
    Set-RegValue -Path "$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name 'EnableTransparency' -Value 0

    Set-RegValue -Path "$Root\Control Panel\Desktop" -Name 'Wallpaper' -Value '' -Type String
    Set-RegValue -Path "$Root\Control Panel\Desktop" -Name 'WallpaperStyle' -Value '0' -Type String
    Set-RegValue -Path "$Root\Control Panel\Desktop" -Name 'TileWallpaper' -Value '0' -Type String
    Set-RegValue -Path "$Root\Control Panel\Colors" -Name 'Background' -Value '0 0 0' -Type String
}

Set-UserAppearance -Root 'HKCU:'

# HKU is not mounted as a drive by default
if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -Scope Script | Out-Null
}
Set-UserAppearance -Root 'HKU:\.DEFAULT'

$defaultHive = 'C:\Users\Default\NTUSER.DAT'
if (Test-Path -LiteralPath $defaultHive) {
    # A run interrupted between load and unload leaves the hive mounted, and the
    # next load then fails on a name that already exists. Retrying a provisioner
    # has to start from the same place the first attempt did.
    & reg.exe unload 'HKU\PackerDefault' 2>&1 | Out-Null

    & reg.exe load 'HKU\PackerDefault' $defaultHive | Out-Null
    if ($LASTEXITCODE -eq 0) {
        try {
            Set-UserAppearance -Root 'HKU:\PackerDefault'
        } finally {
            # The hive stays locked until every handle into it is gone
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            & reg.exe unload 'HKU\PackerDefault' | Out-Null
        }
        Write-Output 'Default user profile set to dark.'
    } else {
        Write-Output "Could not load $defaultHive, new profiles will be light."
    }
}

# A solid colour instead of the logon background image
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'DisableLogonBackgroundImage' -Value 1

Write-Output 'Dark theme applied to the session, the logon screen and new profiles.'

exit 0
