# What the image removes, and what it deliberately keeps

Every switch below is a Packer variable, all defaulting to `true`. Set one to
`false` and that whole group is skipped.

| Variable | Script | Effect |
| --- | --- | --- |
| `disable_windows_update` | `Disable-WindowsUpdate.ps1` | Policy, a WSUS server that does not exist, services, scheduled tasks, reserved storage |
| `disable_defender` | `Disable-Defender.ps1` | Policies, exclusions including the system drive, scheduled scans |
| `remove_appx` | `Remove-Bloat.ps1` | Preinstalled apps, capabilities, optional features |
| `remove_edge` | `Remove-Bloat.ps1` | Edge uninstall attempt; WebView2 is always kept |
| `disable_firewall` | `Set-Policies.ps1` | Filtering off on all three profiles |
| `disable_vbs` | `Set-Policies.ps1` | Virtualization based security and the guest hypervisor |
| `disable_ipv6` | `Set-Policies.ps1` | Every IPv6 interface except loopback |
| `dark_mode` | `Set-Appearance.ps1` | Dark theme in three hives, plus a solid background and logon screen |
| `settings_page_visibility` | `Set-Policies.ps1` | Trims the Settings app down to an allowlist of pages |

## Windows Update, in three layers

Any one layer alone gets repaired by the OS, so all three are applied:

1. **Policy** so nothing asks for updates.
2. **A dead update server** (`WUServer = http://127.0.0.1:8530`) so a manual
   check fails immediately instead of reaching Microsoft.
3. **Services and tasks** disabled through both `Set-Service` and the registry.
   `WaaSMedicSvc` matters most here: it is what turns `wuauserv` back on.

Setup itself is told to skip Dynamic Update, so the install never pulls patches
either.

## Defender, honestly

Tamper protection has **no supported script path**. Defender's own ELAM driver
reverts writes to `Features\TamperProtection` while it is running, whatever
privileges the writer holds. The script attempts it, attempts the service start
types too, and then **prints what the state actually is**:

```
Defender after changes -> AntivirusEnabled=True RealTimeProtectionEnabled=False IsTamperProtected=True
```

What does stick on an unmanaged machine is exclusions, including one for `C:\`,
which takes Defender off the IO path. That is the layer this image relies on.
For a machine with Defender physically removed, the route is offline surgery on
`install.wim` before installing, which this project does not do.

## Kept on purpose

These look like obvious debloat targets and are not. Anticheats and legacy
desktop applications depend on them, and a payload that needs none of this
loses nothing by their staying:

| Kept | Why |
| --- | --- |
| `BFE`, `MpsSvc` | Firewall filters; software queries the service even with filtering off |
| `CryptSvc` | Signature verification, including for kernel drivers |
| `Winmgmt` | WMI, queried by installers and anticheats at startup |
| `Schedule`, `AppInfo` | Task scheduler and UAC elevation |
| `W32Time` | A skewed clock gets the client rejected by the server |
| `Audiosrv`, `AudioEndpointBuilder` | Applications that open an audio device at launch fail without it |
| `TermService`, `SessionEnv`, `UmRdpService` | How the VM is operated |
| WebView2 (when `install_webview2`) | Payloads hosting a browser control need it, and Edge is gone |
| Shell packages (`FileExp`, `Client.CBS`, `Client.Core`, `StartMenuExperienceHost`, `CloudExperienceHost`) | The Windows 11 shell ships as packages, and a clone still boots through OOBE after sysprep |

The app removal list is explicit for the same reason: "remove everything except
a keep list" is how you end up with a VM that has no Start menu and a sysprep
that fails.

## Runtimes

Nothing is installed unless asked for: `install_webview2` and `install_vcredist`
both default to `false`.

Check what the payload actually needs before turning them on. Many older
applications ship private copies of the VC runtimes next to their executable
and need no redistributable at all: a game client from that era typically
carries VC90, VC100, VC110, VC140 and `D3DX9_42/43` in its own folder, and
installing them again changes nothing. WebView2 is the one
that usually does have to be installed, because Edge is uninstalled and any
payload hosting a browser control would otherwise find nothing.


## Where the tweak list comes from

The removals were cross-checked against three well-known debloat projects:
[ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil),
[Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) and
[LeDragoX/Win-Debloat-Tools](https://github.com/LeDragoX/Win-Debloat-Tools).

What those projects do and this one adopted:

| Group | What |
| --- | --- |
| Compatibility telemetry | `AITEnable`, `DisableInventory`, `DisableUAR`, `EnableEventTranscript` - the appraiser walks installed software in the background |
| Activity history | `EnableActivityFeed`, `PublishUserActivities`, `UploadUserActivities` |
| Input and speech personalization | implicit ink and text collection, trained data store, online speech, linguistic data |
| Location | consent store set to Deny, sensor override, Maps auto-update |
| Notifications | toasts and the notification center off: a toast over a full screen application steals focus |
| Accessibility shortcuts | sticky, filter and toggle keys off - they fire on key sequences games send constantly and put a modal dialog over everything |
| Background apps | `LetAppsRunInBackground`, `GlobalUserDisabled` |
| Taskbar surfaces | task view, chat, search box, Start recommendations, `Start_TrackProgs` |
| Storage Sense | off, so nothing is deleted on Windows' own schedule |
| Game Mode | **off**, see below |
| svchost grouping | `SvcHostSplitThresholdInKB` above installed RAM, which is worth hundreds of MB on a small VM |
| Shutdown | `WaitToKillServiceTimeout` down to 2 seconds |
| Pointer acceleration | off |
| Long paths | on |
| `CscService` | disabled (offline files) |
| IPv6 | every interface except loopback disabled, IPv4 preferred everywhere |
| Settings app | trimmed to an allowlist of pages |
| Dark mode | on, across all three hives, with a solid background |
| Store media codecs | AV1, AVC, HEIF, HEVC, MPEG2, RAW, VP9, WebM, WebP removed: Explorer and Photos are gone, and WebView2 carries Chromium's own |
| Cross-device, Calculator, compat enhancements | removed |
| Scheduled task folders | Flighting, RetailDemo, Speech, Maps, Printing, PushToInstall, License Manager, WwanSvc, power and memory diagnostics, backup, offline files |
| Boot menu timeout | 0 |

**Game Mode deserves a note.** Debloat scripts usually turn it *on*. This image
turns it *off*, and for the same reason it sets `Win32PrioritySeparation = 24`:
Game Mode starves everything that is not the single foreground game, which is
exactly wrong when a VM runs several equal workloads side by side.

## Dark mode is three hives, not one

Setting `AppsUseLightTheme` under `HKCU` only darkens the session that is
already logged on. The image writes it to three places:

| Hive | Covers |
| --- | --- |
| `HKCU` | the auto-logon session |
| `HKU\.DEFAULT` | the logon screen and anything running as SYSTEM |
| `C:\Users\Default\NTUSER.DAT` | every profile created later, including the first boot of a sysprep clone |

The same pass empties the wallpaper and sets a black desktop background, and
`DisableLogonBackgroundImage` gives the logon screen a solid colour. That is not
only cosmetic: a wallpaper is a bitmap decoded and held per session.

## Measured, and not worth doing

Trimming `C:\Windows\Web`, `C:\Windows\Help` and `C:\Windows\IME` is a
common suggestion. Measured on Windows 11, they are **27.7 MB, 6.7 MB and
6.4 MB**. Fighting TrustedInstaller for 40 MB, on an image where the component
store cleanup already recovers gigabytes, is not a good trade.

## Two that need a deliberate choice

**IPv6 (`disable_ipv6`, default on).** `DisabledComponents = 0xFF` disables
every IPv6 interface except loopback and makes Windows prefer IPv4 everywhere.
It takes effect on the next reboot. This is a real network change: a payload
that resolves or binds over IPv6 needs the switch set to `false`.

**Settings pages (`settings_page_visibility`).** The default is an allowlist,
not a blanket hide, because a few pages earn their place even on a disposable
VM:

| Kept page | Why |
| --- | --- |
| `display` | screen resolution, which a windowed application cares about |
| `sound` | picking an output when one exists |
| `network-status`, `network-ethernet` | the first place to look when the payload cannot reach anything |
| `dateandtime` | a skewed clock breaks TLS and gets signed sessions rejected |
| `remotedesktop` | how these VMs are operated |
| `about` | build number, which decides whether a bug report means anything |

Page names are ms-settings URIs without the prefix, from the
[official list](https://learn.microsoft.com/windows/apps/develop/launch/launch-settings-app).
Setting it to `""` leaves Settings alone; `hide:page1;page2` is the inverse
form.

## What was deliberately not taken

| Tweak | Seen in | Why not |
| --- | --- | --- |
| `RealTimeIsUniversal` (treat the RTC as UTC) | winutil | fights the hypervisor's time sync. A skewed clock breaks TLS and gets sessions rejected, which is a much worse failure than the problem it solves |
| `HwSchMode`, MPO overlay toggles | winutil, Win-Debloat-Tools | Hyper-V gives the guest no GPU. No effect |
| Edge, Brave and Office policy sets | winutil | that software is not in the image |
| Disabling `BFE`, `MpsSvc`, `CryptSvc`, `Winmgmt` | aggressive debloat generally | see the keep list above. `CryptSvc` alone is enough to stop a kernel driver from loading |
| `DisableWpbtExecution` | winutil | WPBT is firmware-injected. A VM has no firmware table to block |
| Hibernate registry values | winutil | `powercfg /hibernate off` already removes `hiberfil.sys` |
| System Restore frequency | winutil | restore is disabled outright, so the frequency is moot |
| Taskbar alignment, Explorer Home and Gallery | winutil, Win11Debloat | cosmetics with no resource effect |
