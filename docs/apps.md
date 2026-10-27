# Installing apps into the image

One list, `apps`, installed in the order it is written. That order is the only
dependency mechanism there is: an app that needs a tool puts that tool above it.

```hcl
apps = [
  { name = "7-Zip",   type = "msi",     source = "7z2408-x64.msi" },
  { name = "Secrets", type = "archive", source = "secrets.7z", dest = "C:/Secrets",
    extractor = "C:/Program Files/7-Zip/7z.exe" },
]
```

## Where the files come from

Each app reads from exactly one of:

| Field | Means |
| --- | --- |
| `source` | a path on the install CD, relative to its root. `"."` is the whole CD |
| `url` | fetched with `curl.exe` during the build |

`app_sources` lists directories on the machine running packer, and packer puts
each one on the install CD under its own name. Nothing is packed beforehand,
and it is one mechanism on every hypervisor rather than four:

```hcl
app_sources = ["D:/Baphokore/Landverse", "/home/mello/openkore"]

apps = [
  { name = "Client",   type = "copy", source = "Landverse", dest = "C:/Landverse" },
  { name = "OpenKore", type = "copy", source = "openkore",  dest = "C:/OpenKore" },
]
```

The `source` is the last part of the `app_sources` path, because that is the
name the directory takes on the CD. A path under it works too, which is how an
installer carried inside one of them is reached: `source = "Landverse/vc.msi"`.

A build whose apps all use `source` touches no network. A `url` gives that up,
which is sometimes the right trade and never a silent one.

The CD is rebuilt on every build, so a large `app_sources` costs a few minutes
each time. That is the price of having no separate packing step and no
per-hypervisor way of attaching a second disc.

## Types

| Type | What it does | Needs |
| --- | --- | --- |
| `copy` | robocopy the folder as-is | `dest` |
| `archive` | unpack into `dest` | `dest` |
| `msi` | `msiexec /i`, args default to `/qn /norestart` | |
| `exe` | run the installer with `args` | |
| `git` | `git clone --depth 1` into `dest` | `dest`, `url`, and git |

## Every field

| Field | Default | Applies to |
| --- | --- | --- |
| `name` | required | all - it is what the build log and the failures say |
| `type` | required | all |
| `source` / `url` | one of them required | all except `git`, which takes `url` |
| `dest` | required for `copy`, `archive`, `git` | |
| `args` | `[]`, `/qn /norestart` for `msi` | `msi`, `exe`, `git` |
| `marker` | none | proof the install landed, or the build fails. A name under `dest`, or a full path - which is what an `msi` or `exe` with no `dest` needs |
| `shortcut` | none | an executable under `dest`, put on the public desktop |
| `extractor` | none | `archive`: full path of a tool to unpack with instead of `tar.exe` |
| `extractor_args` | `["x", "{src}", "-o{dest}", "-y"]` | `archive`: `{src}` and `{dest}` are substituted |
| `success_exit_codes` | `[0, 1638, 3010]` | `exe` |
| `grant_users` | `true` | gives Users modify on `dest` |
| `exclude_from_defender` | `true` | adds `dest` as a Defender exclusion |

`packer validate` checks the types, the required fields and the
`source`/`url` exclusivity in seconds, long before a VM exists. It does **not**
catch a misspelled field name: HCL drops attributes the type does not declare,
so `shortcutt = "x"` validates and then does nothing. Check the spelling against
the table above.

## What unpacks without installing anything

Windows ships `tar.exe`, which is bsdtar over libarchive. Measured on
Windows 11 26H2 with bsdtar 3.8.9:

| Archive | `tar.exe` | `Expand-Archive` |
| --- | --- | --- |
| `.zip` | yes | yes |
| `.7z` | yes | no, zip only |
| `.tar.gz`, `.tar.xz` | yes | no |
| `.7z` with an encrypted payload | **no** | no |
| `.7z` with `-mhe=on`, encrypted headers | **no** | no |

So a plain `.7z` needs no extractor at all, and `extractor` exists for what
libarchive will not read.

## Encrypted archives fail, deliberately

`tar.exe` answers an encrypted `.7z` by creating every file in it **empty** and
then exiting non-zero:

```
tar -xf enc.7z -C out
→ exit 1   "The file content is encrypted, but currently not supported"
→ out/ now holds 2 files, 0 bytes each
```

A directory of zero-byte files is indistinguishable from a successful install
to anyone looking at the folder. Two things follow.

Every archive is unpacked into a staging directory first and moved into `dest`
only once it unpacked to something, so a failure never leaves half an app
behind.

And the build stops rather than choosing an extractor for you. Which one you
want - 7-Zip, WinRAR, NanaZip - is a decision about your image, not something
this project should make on your behalf:

```
Secrets: this archive is encrypted and tar.exe cannot read it, so it
extracted nothing usable. Declare an extractor on this app - extractor =
'C:/Program Files/7-Zip/7z.exe' with extractor_args, and install it from an
earlier entry in the list.
```

The fix is two entries, in order:

```hcl
apps = [
  { name = "7-Zip", type = "msi", source = "7z2408-x64.msi" },
  {
    name           = "Secrets"
    type           = "archive"
    source         = "secrets.7z"
    dest           = "C:/Program Files/Secrets"
    extractor      = "C:/Program Files/7-Zip/7z.exe"
    extractor_args = ["x", "{src}", "-o{dest}", "-pYOURPASSWORD", "-y"]
  },
]
```

A password written there is in the var file, in the manifest on the build VM,
and in anything that reads either. Treat it as a build secret, not a stored one.

## git is not in a clean Windows

Neither is any other developer tool. A `git` app on a stock image stops with:

```
Tools: git is not installed, and a clean Windows image does not ship it.
Add an entry that installs git earlier in the list, or carry the files on
the apps disc instead.
```

Install it first, from the disc or a url, and the clone works:

```hcl
apps = [
  { name = "Git", type = "exe", source = "Git-2.47.0-64-bit.exe",
    args = ["/VERYSILENT", "/NORESTART"] },
  { name = "OpenKore", type = "git", url = "https://github.com/OpenKore/openkore.git",
    dest = "C:/OpenKore" },
]
```

Cloning during a build also pins nothing: a later rebuild gets whatever the
branch holds then. An archive on the disc is reproducible; a clone is current.
Pick per app.

## What the build checks

`Install-Apps.ps1` fails the build on a missing source, a failed extraction, a
non-zero installer exit outside `success_exit_codes`, and a `marker` that is not
there afterwards.

`Test-ImageState.ps1` then reads the same manifest back at the end of the build
and asserts every `dest` and every `marker` again, on the finished machine:

```
App Landverse            present
  marker Ragexe.exe      present
```
