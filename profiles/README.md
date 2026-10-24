# Profiles

A profile is everything one kind of image needs, in one directory, so the build
stays `.\Build-Image.ps1` with no arguments. Nothing in the core knows a profile
exists: it is four variables pointed at a folder.

## Layout

```
profiles/<name>/
  profile.pkrvars.hcl    the variables that define this image
  README.md              what it builds and why
  scripts/*.ps1          provisioners, run in the guest at build time
  tools/*.ps1            operator tools, copied to C:\Tools in the image
```

Select it from your own variable file, and the build needs nothing else:

```hcl
profile_name = "<name>"
```

## The four variables

| Variable | What it does |
| --- | --- |
| `extra_scripts` | provisioners run in the guest, after the payload is copied |
| `tools_dirs` | directories whose `*.ps1` land in `C:\Tools` inside the image |
| `tools_config` | a free-form object written to `C:\Tools\config.json` |
| `payload_*` | what folder travels into the image, and how it is checked |

`tools_config` is what keeps an image reusable. It is the only thing that
separates one clone from another, so **nothing application-specific belongs in a
script**. A tool reads its defaults from `config.json` and takes the same values
as parameters:

```powershell
param([string] $GameDir, [string] $ClientExe)
$GameDir = Get-Setting -Name 'GameDir' -Value $GameDir -Fallback 'C:\App'
```

Edit the JSON on a clone, or pass a flag. Neither is a rebuild.

## Variables a profile should not set

Leave these to the person building: `iso_url`, `output_directory`,
`build_temp_dir`, `admin_username`, `admin_password`, `payload_source_dir`,
`switch_name`. They describe one machine, not one kind of image.

## Writing one

1. `mkdir profiles/<name>` and write `profile.pkrvars.hcl`.
2. Put the payload checks in it: `payload_marker` fails the build early when the
   wrong folder was packed, `payload_shortcut` lands on the public desktop.
3. Turn on only the runtimes the payload really needs. Most applications that
   predate the universal CRT carry their own.
4. Put per-VM values in `tools_config` and read them in the tools, never in a
   provisioner.
5. Write the README: what it builds, what the operator runs afterwards, and the
   constraint that made you choose this layout.

## Worked example

**[ragnarok-openkore](ragnarok-openkore/README.md)** — a game client folder
copied in, operator tools that point the VM at an external listener, and three
network layouts behind one `Mode` setting. It uses every extension point, so it
is the one to read before writing your own.
