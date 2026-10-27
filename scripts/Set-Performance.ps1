# Trades every background nicety for CPU, RAM and disk the clients can use.

$pagefileMb = [int]($env:PagefileSizeMb)
$mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'

function Set-RegValue {
    param([string] $Path, [string] $Name, $Value, [string] $Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# The session must never go idle: the clients keep running in it
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
foreach ($setting in @('monitor-timeout-ac', 'monitor-timeout-dc', 'disk-timeout-ac', 'disk-timeout-dc',
                       'standby-timeout-ac', 'standby-timeout-dc', 'hibernate-timeout-ac', 'hibernate-timeout-dc')) {
    powercfg /change $setting 0
}

# No hiberfil.sys: it is the size of RAM for a feature a VM never uses
powercfg /hibernate off

# The guest has no use for its own hypervisor, and leaving it off keeps VBS
# from coming back on the next boot
bcdedit /set hypervisorlaunchtype off | Out-Null

# Nobody is at the console to pick an entry, and there is only one
bcdedit /timeout 0 | Out-Null

# A crash dump the size of RAM, written into a dynamic VHDX, on a VM that gets
# rebuilt rather than debugged
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'CrashDumpEnabled' -Value 0
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'LogEvent' -Value 0
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'AutoReboot' -Value 1

# Fixed pagefile: a growing one fragments the dynamic VHDX and undoes the
# compaction done at the end of the build
if ($pagefileMb -lt 1) {
    Write-Output 'pagefile_size_mb is 0, leaving the pagefile managed by Windows.'
} else {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($cs.AutomaticManagedPagefile) {
            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false }
        }
    } catch {
        Write-Output "Automatic pagefile management not turned off: $($_.Exception.Message)"
    }

    # Written here rather than through Win32_PageFileSetting: while Windows is
    # still managing the pagefile there is no instance to change, and creating
    # one is what answered "Type mismatch for property InitialSize".
    Set-RegValue -Path $mm -Name 'PagingFiles' -Value @("C:\pagefile.sys $pagefileMb $pagefileMb") -Type MultiString

    # Read back instead of announced: the value only takes effect on the reboot
    # that follows, so the log should say what the machine will boot with
    $applied = (Get-ItemProperty -LiteralPath $mm -Name 'PagingFiles' -ErrorAction SilentlyContinue).PagingFiles
    $managed = (Get-CimInstance -ClassName Win32_ComputerSystem).AutomaticManagedPagefile
    Write-Output "Pagefile entry: $applied (automatic management: $managed, active after the next reboot)."
}

try {
    Disable-ComputerRestore -Drive 'C:\'
} catch {
    Write-Output "System Restore already off: $($_.Exception.Message)"
}
vssadmin delete shadows /all /quiet 2>&1 | Out-Null

# Prefetch and Superfetch only pay off on a machine that runs varied software
Set-RegValue -Path "$mm\PrefetchParameters" -Name 'EnablePrefetcher' -Value 0
Set-RegValue -Path "$mm\PrefetchParameters" -Name 'EnableSuperfetch' -Value 0
Set-RegValue -Path $mm -Name 'ClearPageFileAtShutdown' -Value 0

# Three clients are peers, not foreground and background: long fixed quanta
# with no foreground boost shares the CPU between them evenly
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 24

fsutil behavior set disablelastaccess 1 | Out-Null
fsutil behavior set disable8dot3 1 | Out-Null

# Windows splits services into one svchost process each above this much RAM,
# which costs hundreds of MB of overhead on a small VM. A threshold above the
# installed memory groups them back together.
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB' -Value 0x4000000

# Shutdown waits 5 seconds per service by default, which a VM that gets
# restarted often pays over and over
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'WaitToKillServiceTimeout' -Value '2000' -Type String

# Deep directory trees in a payload folder are a real failure mode for old
# applications that build paths by hand
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1

# Crash dumps are off, so the stop screen is the only evidence left when a
# kernel driver takes the VM down
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'DisplayParameters' -Value 1

# Pointer acceleration makes mouse movement depend on how fast it was moved,
# which is not what an application reading raw coordinates expects
Set-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type String

# The accessibility shortcuts fire on key sequences an application can send,
# and each one puts a modal dialog over whatever is running
Set-RegValue -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Value '122' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags' -Value '58' -Type String

# Visual effects: adjusted for best performance
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' -Name 'EnableAeroPeek' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ListviewAlphaSelect' -Value 0
Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0

exit 0
