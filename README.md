# Minimal Windows VM for Hyper-V

A Packer template that builds a **minimal Windows 11 image plus a payload folder
of your choosing**. No browser, no Store, no indexing, no telemetry, no Windows
Update, and no runtimes beyond what you ask for.

It exists for the case where a VM has exactly one job: run one application,
repeatably, on hardware you do not want to spend on Windows itself. Build once,
clone the VHDX, point each clone at its own configuration.

Nothing in the template knows what your payload is. A folder goes in, an image
comes out, and everything specific to your application lives in a **profile** or
in your own variable file - never in a script.

```
payload folder  -->  ISO  -->  second DVD  -->  C:\<payload>
Windows ISO     -->  unattended install  -->  debloat  -->  VHDX  -->  clone N times
```

Need a worked example with tools and networking on top, or want to contribute
one? See **[profiles/README.md](profiles/README.md)**.

## Requirements

| Item | Why |
| --- | --- |
| Windows host with Hyper-V | the `hyperv-iso` builder |
| Packer >= 1.11 | `required_version` |
| `oscdimg.exe` in PATH (Windows ADK, Deployment Tools) | builds the unattend CD and the payload CD |
| An elevated PowerShell | creating VMs, mounting and compacting VHDX |
| A Windows ISO | `iso_url` |
| Free space on the `output_directory` drive | about 20 GB plus the payload, doubled when exporting. `Build-Image.ps1` checks before it creates anything |

The repo must sit on a drive letter. Hyper-V cannot reach `\\wsl.localhost\...`,
so `output_directory` has to be a local Windows path.

## Quick start

```powershell
Copy-Item example.pkrvars.hcl local.pkrvars.hcl
notepad local.pkrvars.hcl          # ISO, payload folder, password
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
| `payload_iso` | `<payload_source_dir>.iso` | the payload disc |

All three are independent, so a cramped C: is one variable away from a roomier
drive and back. `skip_export = true` halves the peak disk use by keeping only
the build VM folder.

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

`r` re-runs the whole failed step, so the provisioners are written to be safe to
run twice: registry writes are idempotent, the payload copy is incremental, and
the shutdown detects an image that is already generalized instead of running
sysprep on it a second time. When sysprep does refuse, it prints its own
`setuperr.log` into the build console, because the VM that holds it is about to
be deleted.

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
Payload directory        present
Payload marker           present
```

Only deterministic artifacts are asserted: the registry value a script writes,
never behaviour Windows may still refuse. What it can veto - Defender's
real-time protection under tamper protection, the Edge uninstall outside some
regions - is reported instead, because neither is a build error.

## The payload

Anything that runs from a folder. It is copied in, not installed:

```
payload_source_dir  --oscdimg-->  payload_iso  --second DVD-->  robocopy --> payload_install_dir
```

Nothing is served over HTTP or SMB and nothing is downloaded during the build.
The ISO is a cache, rebuilt only when something in the folder is newer. The
guest finds the disc by **volume label**, not drive letter.

Moving the payload is **one variable**: `payload_iso` defaults to
`<payload_source_dir>.iso` and `payload_install_dir` to `C:\<folder name>`.

```hcl
payload_source_dir = "D:/payloads/MyApp"   # -> D:/payloads/MyApp.iso -> C:\MyApp
payload_marker     = "MyApp.exe"           # build fails early if this is missing
payload_shortcut   = "MyApp.exe"           # goes on the public desktop
```

An installer-based application still works: make the payload the installer
directory and add the silent install to `extra_scripts`.

## Extension points

Four variables, no forking required:

| Variable | What it does |
| --- | --- |
| `profile_name` | the profile to layer in, so the build needs no arguments |
| `extra_scripts` | PowerShell scripts run after the payload is copied |
| `tools_dirs` | directories whose `*.ps1` land in `C:\Tools` for operating the VM afterwards |
| `tools_config` | a free-form object written to `C:\Tools\config.json` for those tools to read |

A profile is just those four pointed at a directory, and
**[profiles/README.md](profiles/README.md)** is how to write one. `tools_config`
is what makes a built image re-configurable: edit the JSON on a clone instead of
rebuilding for each VM.

Every image also ships `C:\Tools\Get-ImageSummary.ps1`, which prints the state
the build actually produced: Defender, Windows Update, firewall, VBS, pagefile,
disabled service count and the payload config.

## What the image does

| Present | Absent |
| --- | --- |
| Windows 11 Pro, auto-logon, RDP | Edge, Store, OneDrive, Xbox, Widgets, Copilot/Recall |
| Your payload and tools | Windows Update, Defender real-time, search indexing |
| Only the runtimes you asked for | WinRE, hiberfil.sys, crash dumps, System Restore |
| | Spooler, telemetry, 60+ services a single-purpose VM never uses |

Each removal group is a switch (`disable_defender`, `disable_windows_update`,
`disable_firewall`, `remove_edge`, `remove_appx`, `disable_vbs`, `disable_ipv6`,
`dark_mode`, `settings_page_visibility`).
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
| Payload copied, not installed | no installer logs, no drift between VMs |
| Payload arrives as a second DVD | no HTTP, SMB or download during the build |
| Auto-logon, no lock, no sleep | the payload runs in an interactive session that has to survive unattended |

## Known limits

| Limit | Status |
| --- | --- |
| Hyper-V only | the template has one source. A `vmware-iso` or `qemu` source would be a welcome addition |
| No GPU, no sound card | Hyper-V gives the guest neither. 3D applications fall back to software rendering (d3d9on12/WARP) |
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
Build-Image.ps1              host checks, payload ISO, packer
config/
  autounattend.pkrtpl.xml      unattended install, rendered by Packer
  sysprep-unattend.pkrtpl.xml  read by sysprep to restore auto-logon on a clone
  shutdown.pkrtpl.ps1          the shutdown step: sysprep, or why it refused
  bootstrap-winrm.ps1          opens WinRM at first logon
scripts/                     provisioners, in build order
  Set-Policies.ps1             telemetry, cloud content, Copilot/Recall, Store, VBS, firewall
  Disable-WindowsUpdate.ps1    policy, dead update server, services, tasks, reserved storage
  Disable-Defender.ps1         policies, exclusions, honest reporting
  Disable-Services.ps1         services and scheduled tasks
  Remove-Bloat.ps1             appx, capabilities, features, Edge, OneDrive
  Set-Performance.ps1          power, pagefile, prefetch, visual effects, dumps
  Set-Autologon.ps1            auto-logon, no lock, no screensaver, silent elevation
  Install-Runtimes.ps1         WebView2 and VC++, both opt-in
  Copy-Payload.ps1             finds the disc by label, copies, ACLs, shortcut
  Test-ImageState.ps1          fails the build when a requested change is absent
  Cleanup-System.ps1           WinRE, component store, logs, temp, TRIM
  Optimize-Vhdx.ps1            host-side VHDX compaction (post-processor)
tools/                       copied to C:\Tools in the image
  Get-ImageSummary.ps1         what the build actually produced
profiles/
  README.md                    how to write one
  ragnarok-openkore/           worked example: payload + tools + networking
docs/
  debloat.md                   what is removed, what is kept, and why
```

## Development

```powershell
packer fmt .
packer validate -syntax-only windows.pkr.hcl
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./.psscriptanalyzer.psd1
```

CI runs all three on every push. The PowerShell settings pin
`PSUseCompatibleSyntax` to 5.1, because that is what the guest runs.

## Licence

See [LICENSE](LICENSE).
