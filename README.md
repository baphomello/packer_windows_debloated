# Minimal Windows VM

A Packer template that builds a **minimal Windows 11 image plus the
applications you list**. No browser, no Store, no indexing, no telemetry, no Windows
Update, and no runtimes beyond what you ask for.

It exists for the case where a VM has exactly one job: run one application,
repeatably, on hardware you do not want to spend on Windows itself. Build once,
clone the VHDX, point each clone at its own configuration.

Nothing in the template knows what your applications are. A list goes in, an
image comes out, and everything specific to them lives in a **profile** or in
your own variable file - never in a script.

```
apps folder     -->  ISO  -->  second DVD  -->  copied, unpacked or installed
Windows ISO     -->  unattended install  -->  debloat  -->  VHDX  -->  clone N times
```

Need a worked example with tools and networking on top, or want to contribute
one? See **[profiles/README.md](profiles/README.md)**.

## Requirements

| Item | Why |
| --- | --- |
| One hypervisor, any of four | Hyper-V, KVM/qemu, VirtualBox or VMware. See [targets](#targets) |
| Packer >= 1.16.0 | the apps manifest is a typed list, and `optional()` inside an object type constraint is rejected by every earlier release |
| `oscdimg.exe` in PATH (Windows ADK, Deployment Tools) | builds the unattend CD and the apps CD |
| An elevated PowerShell | creating VMs, mounting and compacting VHDX |
| A Windows ISO | `iso_url` |
| Free space on the `output_directory` drive | about 20 GB plus the apps ISO, doubled when exporting. `Build-Image.ps1` checks before it creates anything |

On Windows, the repo must sit on a drive letter: Hyper-V cannot reach
`\\wsl.localhost\...`, so `output_directory` has to be a local path.

## Quick start

```powershell
Copy-Item example.pkrvars.hcl local.pkrvars.hcl
notepad local.pkrvars.hcl          # ISO, apps folder, apps list, password
.\Build-Image.ps1
```

Only `iso_url` and `admin_password` have no usable default. The result is
`<output_directory>\<vm_name>\` with an exported VM and a VHDX that has already
been compacted. The final size is printed by the post-processor.

### Where the build writes

| Variable | Default | Holds |
| --- | --- | --- |
| `output_directory` | `C:/HyperV/packer` | the build VM, its VHDX and the export |
| `build_temp_dir` | user `TEMP` | the unattend ISO and the downloaded-ISO cache |
| `apps_iso` | `<apps_source_dir>.iso` | the apps disc |

All three are independent, so a cramped C: is one variable away from a roomier
drive and back. `skip_export = true` halves the peak disk use by keeping only
the build VM folder.

## Targets

One template, one set of provisioning scripts, four hypervisors. The scripts
never learn which one they are running on:

| Target | `-only=` | Produces |
| --- | --- | --- |
| Hyper-V | `hyperv-iso.windows` | a VM folder with a VHDX |
| KVM / qemu | `qemu.windows` | `qcow2`, or `raw` via `qemu_format` |
| VirtualBox | `virtualbox-iso.windows` | an OVA |
| VMware | `vmware-iso.windows` | a VMX folder |

```powershell
packer build -only=qemu.windows -var-file=local.pkrvars.hcl windows.pkr.hcl
```

`Build-Image.ps1` takes `-Target` for the same choice, and defaults to Hyper-V.
Without one of them a build would try all four at once.

### What made this portable

Windows 11 setup checks for TPM 2.0 and Secure Boot, and whether a hypervisor
can offer them varies: Hyper-V Gen 2 has both, VirtualBox before 7.0 has no
vTPM, qemu needs `swtpm` installed separately. The answer file now writes the
`LabConfig` bypass keys during `windowsPE`, so the same media installs
everywhere. `secure_boot` and `tpm` default to `false` and can be turned back
on wherever the target supports them - the image no longer depends on it.

### virtio, on KVM only

Windows setup carries no virtio driver, so with `qemu_disk_interface = "virtio"`
it finds no disk at all and stops. Two ways out:

```hcl
# point setup at the virtio-win drivers, mounted as a third disc
driver_path = "E:\amd64\w11"

# or give up the fast path and need no driver
qemu_disk_interface = "sata"
qemu_net_device     = "e1000"
```

`driver_path` is empty by default and the block disappears from the answer
file, so the other three targets never see it.

### Where the host still shows through

Everything in `scripts/` runs in the guest and is portable. Three things are
not, and all three are Hyper-V or Windows:

| | |
| --- | --- |
| `Build-Image.ps1` | packs the apps ISO with `oscdimg`, checks free space. `packer build` works without it |
| `Optimize-Vhdx.ps1` | compacts a VHDX; the post-processor is scoped to the Hyper-V target |
| `tools/host/Get-SysprepFailure.ps1` | PowerShell Direct, which only Hyper-V has |

## When a step fails

The build runs with `-on-error=ask`, so a failure stops at a prompt instead of
destroying an hour of work:

```
[c] Clean up and exit, [a] abort without cleanup, or [r] retry step?
```

| Answer | Use it when |
| --- | --- |
| `a` | you want to look inside the VM. It keeps running and nothing is deleted |
| `r` | the cause was transient, or you fixed something from inside the guest |
| `c` | you are done with this attempt |

`winrm_timeout` (default `2h`) bounds the wait before the guest answers. It has
to cover the unattended install and OOBE, so it is generous - but an answer file
Windows refused is only ever reported when it runs out.

### What a retry reaches

`r` re-runs the **whole** failed step, and Packer re-uploads the provisioner
scripts from disk every time. So a fix in a script lands on the next `r` without
restarting the build:

| Change | Picked up by `r` |
| --- | --- |
| A script under `scripts/`, `config/` or a profile | yes, it is re-uploaded |
| `windows.pkr.hcl` or a variable file | no, variables are fixed when the build starts |
| A transient failure: a download, a service slow to stop | yes |
| A deterministic one: a script your antivirus blocks | no, it fails identically |

Which is why every provisioner is written to survive a second pass: registry
writes are idempotent, an app that is already installed is skipped, runtimes already present
are skipped instead of downloaded again, a registry hive left mounted by an
interrupted run is unloaded before it is loaded, and the shutdown detects an
image that is already generalized instead of running sysprep on it twice.

### A successful retry still ends as a failed build

The prompt means its own warning literally:

```
[r] retry step (build may fail even if retry succeeds)
```

A step that fails records the error in Packer's state bag, and a retry that
succeeds does not clear it. So the step really does run again and really does
work - the VM shuts down, the disks are compacted, the artifacts are collated -
and then the build ends on the error from the first attempt, runs the cleanup
provisioner and unregisters the VM.

What survives that is the point: the **output directory is kept**. A build that
fails before the artifact exists prints `Deleting output directory...`, and one
that fails after it exists does not. So check the disk before believing
`no artifacts were created`:

```powershell
Get-ChildItem 'C:\HyperV\packer\your-vm-name' -Recurse -File |
    Select-Object FullName, @{n='GB';e={[math]::Round($_.Length/1GB,2)}}
```

The image is there, but the `Optimize-Vhdx.ps1` post-processor is not:
post-processors never run on a failed build, so the VHDX keeps every block the
build ever touched. Compact it by hand, with the file detached from any VM:

```powershell
Optimize-VHD -Path 'C:\HyperV\packer\your-vm-name\Virtual Hard Disks\your-vm-name.vhdx' -Mode Full
```

### "Timeout while waiting for machine to shut down"

This almost always means sysprep refused to generalize, and it is the one
failure the build cannot explain by itself. Packer's Hyper-V builder starts the
shutdown command with its output pointed at buffers it never reads, so nothing
sysprep says reaches the console - the step just waits out `shutdown_timeout`
and reports a timeout.

So answer **`a`**, which leaves the VM running, and read the reason from the
host:

```powershell
.\tools\host\Get-SysprepFailure.ps1 -VMName your-vm-name
```

That goes in over PowerShell Direct, which needs no network and still works on a
half-generalized guest. It prints `C:\sysprep-failed.log`, written by the
shutdown script, falling back to sysprep's own `setuperr.log`.

Answering `c` deletes the VM and the logs with it, leaving nothing to read.

The cause this build hit, and the one to suspect first, is drive encryption:

```
SYSPRP BitLocker-Sysprep: BitLocker is on for the OS volume. (0x80310039)
```

Windows 11 24H2 encrypts the OS volume by itself during OOBE of a clean
install, and sysprep will not generalize an encrypted volume. The answer file
now sets `PreventDeviceEncryption` before OOBE runs, and
`Disable-DriveEncryption.ps1` is the first provisioner to run, decrypting the
volume anyway if it finds it encrypted. First, because everything after it
reads and writes that volume: undoing the encryption early is both the smallest
decryption and the fastest rest-of-build.

`Test-SysprepReady.ps1` runs just before the shutdown and names what is likely
to stop sysprep: an encrypted OS volume, and appx packages installed for a user
but not provisioned for all users, which is the `0x80073cf2` failure that
follows removing apps. The appx half reports and never removes, because the
list is long, mostly inbox packages, and a wrong guess on the last step before
shutdown costs the whole build.

Setting `generalize = false` builds without sysprep entirely. Every clone then
shares this image's SID and hostname, which is fine for one VM and not for
several on one network.

## The build does not flatter itself

Every switch is checked against the finished image before the shutdown, so a
variable that asked for something absent fails the build instead of shipping an
image that quietly ignored it:

```
== Asserted: a variable asked for it, so it has to be here
Defender policy          1
Windows Update policy    1
wuauserv start type      Disabled
Firewall profiles        False
VBS policy               0
Auto-logon               1
Pagefile entry           C:\pagefile.sys 4096 4096
App Landverse            present
  marker Ragexe.exe      present
```

Only deterministic artifacts are asserted: the registry value a script writes,
never behaviour Windows may still refuse. What it can veto - Defender's
real-time protection under tamper protection, the Edge uninstall outside some
regions - is reported instead, because neither is a build error.

## Apps

A list, installed in the order written. Copy a folder, unpack an archive, run
an MSI or an EXE, clone a repository:

```hcl
apps = [
  { name = "MyApp", type = "copy", source = "MyApp", dest = "C:/MyApp",
    marker = "MyApp.exe", shortcut = "MyApp.exe" },
  { name = "7-Zip", type = "msi", source = "7z2408-x64.msi" },
]
```

Sources ride in on a second DVD, built from one folder on the host:

```
apps_source_dir  --oscdimg-->  apps_iso  --second DVD-->  each app's dest
```

So a build whose apps all use `source` serves nothing over HTTP or SMB and
downloads nothing. An app can use `url` instead, which gives that up
deliberately. The ISO is a cache, rebuilt only when something in the folder is
newer, and the guest finds the disc by **volume label**, not drive letter.

`.zip`, `.7z`, `.tar.gz` and `.tar.xz` unpack with the `tar.exe` Windows already
ships, so no extractor is installed for them. An **encrypted** archive stops the
build and names what is missing, rather than picking an extractor for you - and
`git` does the same, because a clean Windows image has none.

Order is the only dependency mechanism: an app that needs a tool puts that tool
above it.

**[docs/apps.md](docs/apps.md)** has every field, the measured archive support
matrix, and why the encrypted case fails instead of guessing.

## Extension points

Four variables, no forking required:

| Variable | What it does |
| --- | --- |
| `profile_name` | the profile to layer in, so the build needs no arguments |
| `extra_scripts` | PowerShell scripts run after the apps are installed |
| `tools_dirs` | directories whose `*.ps1` land in `C:\Tools` for operating the VM afterwards |
| `tools_config` | a free-form object written to `C:\Tools\config.json` for those tools to read |

A profile is just those four pointed at a directory, and
**[profiles/README.md](profiles/README.md)** is how to write one. `tools_config`
is what makes a built image re-configurable: edit the JSON on a clone instead of
rebuilding for each VM.

Every image also ships `C:\Tools\Get-ImageSummary.ps1`, which prints the state
the build actually produced: Defender, Windows Update, firewall, VBS, pagefile,
disabled service count and the tools config.

## What the image does

| Present | Absent |
| --- | --- |
| Windows 11 Pro, auto-logon, RDP | Edge, Store, OneDrive, Xbox, Widgets, Copilot/Recall |
| Your apps and tools | Windows Update, search indexing, Defender off your apps' IO path |
| Only the runtimes you asked for | WinRE, hiberfil.sys, crash dumps, System Restore |
| | Spooler, telemetry, 60+ services a single-purpose VM never uses |

Each removal group is a switch (`disable_windows_update`, `disable_firewall`,
`remove_edge`, `remove_appx`, `disable_vbs`, `disable_ipv6`, `dark_mode`,
`settings_page_visibility`), and `defender_exclusions` lists the directories
Defender should leave alone.
The tweak list was cross-checked against
[winutil](https://github.com/ChrisTitusTech/winutil),
[Win11Debloat](https://github.com/Raphire/Win11Debloat) and
[Win-Debloat-Tools](https://github.com/LeDragoX/Win-Debloat-Tools); what was
taken, what was **kept on purpose**, and what was rejected and why, is in
**[docs/debloat.md](docs/debloat.md)**.

## Several VMs

```powershell
# per VM after cloning: edit one JSON, no rebuild
notepad C:\Tools\config.json

# or bake the difference at build time
.\Build-Image.ps1 -Var vm_name=WIN2 -Var computer_name=WIN2
```

`computer_name` falls back to `vm_name`, and Windows takes **1-15 characters of
letters, digits and hyphens** for a hostname. A name it rejects abandons the
whole answer file: no account is created, WinRM never opens, and the build sits
on the connect timeout. `Build-Image.ps1` refuses such a name before it creates
anything, so set `computer_name` separately when the VM deserves a longer name.

Cloning the built VHDX:

```powershell
$src = 'D:\hyperv\packer\WINMIN\Virtual Hard Disks\WINMIN.vhdx'
1..3 | ForEach-Object {
    $name = "WIN$_"
    $disk = "D:\hyperv\$name\$name.vhdx"
    New-Item -ItemType Directory -Path (Split-Path $disk) -Force | Out-Null
    Copy-Item $src $disk
    New-VM -Name $name -Generation 2 -MemoryStartupBytes 4GB -VHDPath $disk -SwitchName 'Default Switch'
    Set-VM -Name $name -ProcessorCount 2 -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes 6GB
    Set-VMFirmware -VMName $name -EnableSecureBoot On
    Enable-VMTPM -VMName $name
}
```

Use a differencing disk (`New-VHD -Differencing -ParentPath $src`) to save
space. Every clone passes through OOBE once, gets its own SID, hostname and
machine GUID from sysprep, and lands on the same auto-logon desktop.

## Decisions worth knowing

| Decision | Why |
| --- | --- |
| Gen 2 + Secure Boot + vTPM | the Windows 11 setup hardware check |
| 64 GB declared disk | setup refuses less; a dynamic VHDX only grows to what is used |
| VBS/HVCI and the guest hypervisor off | CPU cost inside a VM, and the usual suspect when a kernel driver will not load |
| `sysprep /generalize` on shutdown | every clone gets its own SID, hostname and machine GUID |
| No Windows Update provisioner | the image is rebuilt, not patched; an update reboot kills every session at once |
| Fixed pagefile | a growing one fragments and inflates the dynamic VHDX |
| `Win32PrioritySeparation = 24` | several equal workloads share the CPU evenly instead of boosting the foreground |
| A folder copied, not installed, when the app allows it | no installer logs, no drift between VMs |
| App sources arrive as a second DVD | no HTTP, SMB or download during the build |
| Auto-logon, no lock, no sleep | the apps run in an interactive session that has to survive unattended |

## Known limits

| Limit | Status |
| --- | --- |
| Only Hyper-V is build-tested | the other three sources validate and are written from each builder's documented options, but no image has been built with them yet |
| No GPU, no sound card | none of these targets give the guest either by default. 3D applications fall back to software rendering (d3d9on12/WARP) |
| RDP disconnect | the session stays logged on, but the desktop stops composing and a D3D application can stall. Drive it through VMConnect, or hand the session back with `tscon 1 /dest:console` |
| Defender tamper protection | not scriptable, see [docs/debloat.md](docs/debloat.md). The build log prints the state it really ends in |
| `sysprep /generalize` | can fail if an appx is left half-removed. The shutdown prints sysprep's own log when it does; set `generalize = false` to build without it and accept identical SIDs across clones |
| Windows activation | the generic key installs but does not activate. Apply your own licence with `slmgr /ipk` + `slmgr /ato` |
| Plaintext password | lives in the auto-logon registry values and in `C:\Windows\Panther\sysprep-unattend.xml` inside the image. Use a password dedicated to these VMs |
| The image is not tested automatically | CI checks formatting, template validity and PowerShell lint. Nothing boots a VM |

## Layout

```
windows.pkr.hcl              one template, every variable has a default
example.pkrvars.hcl          copy to local.pkrvars.hcl (gitignored)
Build-Image.ps1              host checks, apps ISO, packer
config/
  autounattend.pkrtpl.xml      unattended install, rendered by Packer
  sysprep-unattend.pkrtpl.xml  read by sysprep to restore auto-logon on a clone
  shutdown.pkrtpl.ps1          the shutdown step: sysprep, or why it refused
  bootstrap-winrm.ps1          opens WinRM at first logon
scripts/                     provisioners, in build order
  Set-Policies.ps1             telemetry, cloud content, Copilot/Recall, Store, VBS, firewall
  Disable-WindowsUpdate.ps1    policy, dead update server, services, tasks, reserved storage
  Set-DefenderExclusions.ps1   directories Defender will not scan
  Disable-Services.ps1         services and scheduled tasks
  Remove-Bloat.ps1             appx, capabilities, features, Edge, OneDrive
  Set-Performance.ps1          power, pagefile, prefetch, visual effects, dumps
  Set-Autologon.ps1            auto-logon, no lock, no screensaver, silent elevation
  Install-Runtimes.ps1         WebView2 and VC++, both opt-in
  Install-Apps.ps1             the apps list: copy, archive, msi, exe, git
  Test-ImageState.ps1          fails the build when a requested change is absent
  Cleanup-System.ps1           WinRE, component store, logs, temp, TRIM
  Disable-DriveEncryption.ps1  sysprep refuses an encrypted OS volume
  Test-SysprepReady.ps1        lists what is likely to stop sysprep, before it runs
  Optimize-Vhdx.ps1            host-side VHDX compaction (post-processor)
tests/                       runs the provisioning scripts without a build
  Invoke-Tests.ps1             17 cases, seconds, no elevation
  fixtures/                    archives the tests cannot create with built-in tools
tools/                       its *.ps1 are copied to C:\Tools in the image
  Get-ImageSummary.ps1         what the build actually produced
  host/                        runs on the host, so it stays out of that copy
    Get-SysprepFailure.ps1     reads a kept VM over PowerShell Direct
profiles/
  README.md                    how to write one
  ragnarok-openkore/           worked example: app + tools + networking
docs/
  apps.md                      the apps list: types, fields, archive support
  debloat.md                   what is removed, what is kept, and why
```

## Development

```powershell
.\tests\Invoke-Tests.ps1              # seconds, no Hyper-V, no elevation
packer fmt .
packer validate -syntax-only windows.pkr.hcl
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./.psscriptanalyzer.psd1
```

CI runs these on every push. The PowerShell settings pin
`PSUseCompatibleSyntax` to 5.1, because that is what the guest runs.

`Invoke-Tests.ps1` runs the real provisioning scripts in a child process
against a manifest shaped the way `jsonencode` writes it, then reads the file
system rather than the script's own account of itself. It covers every app
type, the archive formats, the failure paths and the ordering. A build takes
hours and needs Hyper-V, elevation and an ISO; most of what goes wrong in one
is ordinary script logic, and this finds that in seconds. `-Filter` narrows it:

```powershell
.\tests\Invoke-Tests.ps1 -Filter encrypted*
```

What it cannot reach: anything needing a real disc, an installed MSI, or
elevation. The guest-only scripts are checked by the build itself, through
`Test-ImageState.ps1`.

## Licence

See [LICENSE](LICENSE).
