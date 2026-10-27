// Copy to local.pkrvars.hcl and edit. That file is gitignored.
//
// Only what has no sensible default is listed here. Everything else has one in
// windows.pkr.hcl: run `packer inspect windows.pkr.hcl` to see them all.
//
// For a worked example of an app that also needs tools and networking, see
// profiles/README.md.

// ---- required ----------------------------------------------------------

// Windows ISO. A local path builds faster than a URL.
iso_url      = "D:/iso/en-us_windows_11_consumer_editions_x64.iso"
iso_checksum = "none"

// Where the build VM and the exported image are written. Local Windows path:
// Hyper-V cannot use UNC, so a repo on \\wsl.localhost still needs this on a drive.
// Build-Image.ps1 checks the free space on this drive before it creates anything.
output_directory = "C:/HyperV/packer"

// Scratch for the unattend ISO and the downloaded-ISO cache. Empty leaves both
// in the user TEMP on C:. Point it at a roomier drive if C: is tight.
build_temp_dir = ""

// WinRM during the build, and the auto-logon session afterwards.
admin_username = "operator"
admin_password = "change-me"

// ---- apps --------------------------------------------------------------

// The folder packed into an ISO and attached to the build VM as a second DVD.
// Every app with a "source" reads from that disc, so the build needs no
// network. Leave empty if every app installs from a url.
apps_source_dir = "D:/apps"

// Optional: where that ISO is written. Empty derives "<apps_source_dir>.iso".
apps_iso = ""

// What to install, in order. The order is the only dependency mechanism:
// an app that needs a tool puts that tool above it.
//
//   type = "copy"     a folder from the disc, copied as-is
//   type = "archive"  zip, 7z, tar.gz, tar.xz - unpacked by the tar.exe
//                     Windows already ships, so no extractor is installed
//   type = "msi"      msiexec /i, args default to /qn /norestart
//   type = "exe"      an installer run with args
//   type = "git"      git clone, which needs git installed by an earlier app
//
// source is a path on the disc, "." meaning the whole disc. url is fetched
// during the build instead. See docs/apps.md for every field.
apps = [
  {
    name     = "MyApp"
    type     = "copy"
    source   = "MyApp"
    dest     = "C:/MyApp"
    marker   = "MyApp.exe" // fails the build if missing after the install
    shortcut = "MyApp.exe" // onto the public desktop
  },
  // {
  //   name = "7-Zip"
  //   type = "msi"
  //   source = "7z2408-x64.msi"
  // },
  // {
  //   name      = "Secrets"
  //   type      = "archive"
  //   source    = "secrets.7z"
  //   dest      = "C:/Program Files/Secrets"
  //   extractor = "C:/Program Files/7-Zip/7z.exe"   // encrypted: tar.exe cannot
  //   extractor_args = ["x", "{src}", "-o{dest}", "-pYOURPASSWORD", "-y"]
  // },
]

// ---- runtimes ----------------------------------------------------------

// Off by default: a minimal image stays minimal. Turn on what the apps
// actually needs. WebView2 matters for anything hosting a browser control,
// because Edge is uninstalled.
install_webview2 = false
install_vcredist = false

// ---- Defender ----------------------------------------------------------

// Directories Defender will not scan. Every app with a dest is excluded
// automatically, so this is for anything else with hot IO - tools, caches,
// a working directory. Use specific paths: a whole-volume exclusion is both
// broader than needed and refused by Defender's own script scanner.
defender_exclusions = []

// ---- locale ------------------------------------------------------------

// system_locale sets the ANSI codepage legacy applications read data in.
timezone      = "UTC"
system_locale = "en-US"
input_locale  = "en-US"
ui_language   = "en-US"

// ---- the VM ------------------------------------------------------------

vm_name = "WINMIN"

// Hyper-V only, ignored by the other targets.
switch_name = "Default Switch"

// Windows 11 setup checks for both, and the answer file writes the LabConfig
// bypass so it installs without them. Turn them on where the target has them.
secure_boot = false
tpm         = false

// ---- KVM / qemu only ----------------------------------------------------

// virtio is the fast path, and Windows setup carries no driver for it: leave
// these as they are and set driver_path, or drop to sata/e1000 and need none.
// qemu_disk_interface = "virtio"
// qemu_net_device     = "virtio-net"
// driver_path         = "E:\\amd64\\w11"

// kvm on Linux. tcg builds anywhere and is far slower.
// qemu_accelerator = "kvm"

// The Windows hostname, which falls back to vm_name when empty. Windows takes
// 1-15 characters of letters, digits and hyphens, and an invalid one kills the
// unattended install without saying so. Set it when vm_name is longer than that
// or carries underscores.
computer_name = ""

// Covers the whole unattended install plus OOBE. Lower it and a broken answer
// file is reported sooner; raise it on a slow host.
winrm_timeout = "2h"

// ---- build behaviour ---------------------------------------------------

// false leaves a portable exported VM folder next to the build VM, which costs
// a second full copy of the VHDX. true halves the peak disk use.
skip_export = false

// sysprep /generalize on the last shutdown, so every clone gets its own SID,
// hostname and machine GUID. Set false if sysprep refuses on your image and you
// can live with identical SIDs across clones.
generalize = true
