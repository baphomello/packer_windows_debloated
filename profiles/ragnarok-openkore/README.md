# Profile: Ragnarok Online + OpenKore

A worked example of the payload mechanism: the payload is a Ragnarok Online
client folder, and the profile adds the tools and the network layout needed to
drive it from [OpenKore](https://openkore.com/) over XKore 1.

```powershell
# in local.pkrvars.hcl
profile_name = "ragnarok-openkore"
```

```powershell
.\Build-Image.ps1
```

`profile.pkrvars.hcl` carries everything specific to this use case. Your own
file carries the machine specifics: the ISO, the output directory, the password
and `payload_source_dir` pointing at the game folder.

What the profile adds on top of the base image:

| Piece | What it does |
| --- | --- |
| `payload_marker = "Ragexe.exe"` | fails the build early if the wrong folder was packed |
| `install_webview2 = true` | the launcher hosts a WebView2 control and Edge is uninstalled |
| `tools/Set-KoreLink.ps1` | configures how this VM reaches the OpenKore listener |
| `tools/Start-Clients.ps1` | launches N clients, one port per instance |
| `scripts/Set-KoreNetwork.ps1` | applies the link at build time when it is already known |

> The client is not installed, it is copied. Whatever sits in the source folder
> travels with it: bridge DLLs, `autologin.ini`, `GordoKore.ini`.

> **Running the game in a VM is not a settled question.** The OpenKore Latam
> tutorial says plainly not to, because GameGuard logs it. The game's published
> specs tell Mac users to use VMware or Parallels. This profile does not try to
> hide the hypervisor from the anticheat.

---

## Reaching OpenKore from the client VM

GameGuard refuses a client that connects to an address outside the official
server range. The community calls the result *Illegal Program*. So the OpenKore
listener has to live at an address inside **`172.65.0.0/16`**, on a port that
is not the real game port.

That is the whole constraint. Everything below is just how a given layout
satisfies it.

## The client side

The bridge DLL reads its target off the command line:

```
Ragexe.exe 1rag1 -ip 172.65.10.1 -port 2350 -al profile1
```

`C:\Tools\Start-Clients.ps1` builds those command lines from `config.json`.

## The OpenKore side

One OpenKore process per client: **XKore 1 listens per instance, it does not
multiplex**. Each instance gets the matching port in `control/config.txt`:

```
XKore 1
XKore_hookIp 172.65.10.1
XKore_port   2350
XKore_injectDLL 0
XKore_lookForProcess 0
```

Client 2 gets `2351`, client 3 `2352`, and so on from `kore_port_base`.

## Modes

`C:\Tools\Set-KoreLink.ps1 -Mode <mode>` configures the VM. The defaults come
from `C:\Tools\config.json`, which the build wrote from `tools_config`.

### route (OpenKore on another machine)

```
  Windows VM (clients)                      Linux VM (OpenKore)
 +-----------------------------+          +------------------------------+
 | Ragexe.exe                  |          | perl openkore.pl             |
 |   -ip   172.65.10.1         |  switch  |   XKore_hookIp 172.65.10.1   |
 |   -port 2350                +----------+   XKore_port   2350          |
 |                             |          |                              |
 | route /32:                  |          | ip addr add 172.65.10.1/32 \ |
 |  172.65.10.1 -> 192.168.1.50|          |    dev eth0                  |
 +-----------------------------+          +---------------+--------------+
                                                          | real connection
                                                          v  game server
```

```powershell
Set-KoreLink.ps1 -Mode route -KoreHost 172.65.10.1 -NextHop 192.168.1.50
```

A `/32` route and not a secondary address in a `/24`: `172.65.0.0/16` is a
Cloudflare range and the real game server lives in it. A `/24` would hijack 256
real addresses and can break the patcher. The `/32` diverts exactly one.

### gateway (the OpenKore host routes for this VM)

Put both VMs on an internal Hyper-V switch and let the Linux VM be the router,
DHCP server and DNS server for it. The default route already points at the
machine that owns `172.65.10.1`, so there is nothing to add:

```powershell
Set-KoreLink.ps1 -Mode gateway -KoreHost kore.lab.lan
```

This is the least per-VM configuration of the three. The Windows VM gets its
address, gateway and DNS from DHCP; `kore_host` can be a name the Linux VM
serves, and the script resolves it before handing the address to the client.
Reservations on the DHCP server keep each VM's address stable.

### alias (OpenKore on the same VM)

The single-machine layout from the community tutorial: the address is added to
this VM's adapter and OpenKore binds to it locally.

```powershell
Set-KoreLink.ps1 -Mode alias -KoreHost 172.65.10.1 -PrefixLength 24
```

### none

Nothing is configured at build time. This is the default, because the addresses
usually are not known when the image is built.

## Several VMs

Nothing has to be rebuilt. On each VM, edit `C:\Tools\config.json`:

```json
{
  "Mode": "route",
  "KoreHost": "172.65.10.1",
  "NextHop": "192.168.1.50",
  "ServerPrefix": "172.65.",
  "BasePort": 2360,
  "Instances": 3,
  "GameDir": "C:\\Landverse",
  "ClientExe": "Ragexe.exe",
  "LaunchToken": "1rag1",
  "Profiles": ["alpha", "beta", "gamma"]
}
```

then `Set-KoreLink.ps1` and `Start-Clients.ps1` with no arguments.

Every key is also a parameter on the tool that reads it, so one-off runs need no
file edit:

```powershell
Start-Clients.ps1 -GameDir C:\Client -ClientExe Ragexe.exe -Count 2
Set-KoreLink.ps1 -Mode alias -KoreHost 172.65.10.1 -ServerPrefix ''
```

| Key | Why it is a variable |
| --- | --- |
| `GameDir`, `ClientExe` | the client folder and executable differ per server |
| `LaunchToken` | the first argument the client expects, server-specific |
| `ServerPrefix` | the range the server accepts. Empty turns the warning off on a private server |
| `BasePort`, `Instances` | one OpenKore port per client, see above |

To bake the difference at build time instead, override on the command line:

```powershell
.\Build-Image.ps1 -ProfileName ragnarok-openkore -Var vm_name=RO2
```

A port plan that stays readable: VM *n* starts at `2350 + (n - 1) * 10`, which
leaves room for ten clients per VM before the next VM's range.

| VM | Clients | Ports |
| --- | --- | --- |
| RO1 | 3 | 2350-2352 |
| RO2 | 3 | 2360-2362 |
| RO3 | 3 | 2370-2372 |
