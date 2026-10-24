// Copy to local.pkrvars.hcl and edit. That file is gitignored.
//
// Only what has no sensible default is listed here. Everything else has one in
// windows.pkr.hcl: run `packer inspect windows.pkr.hcl` to see them all.
//
// For a worked example of a payload that also needs tools and networking, see
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

// ---- payload -----------------------------------------------------------

// The folder copied into the image, as-is. This single variable moves the
// whole payload: payload_iso defaults to "<payload_source_dir>.iso" and
// payload_install_dir to "C:\<folder name>".
install_payload    = true
payload_source_dir = "D:/payloads/MyApp"

// Optional: fail the build early if this file is missing, before and after the
// copy. Cheap insurance against packing the wrong folder.
payload_marker = "MyApp.exe"

// Optional: put this on the public desktop, relative to the install directory.
payload_shortcut = "MyApp.exe"

// ---- runtimes ----------------------------------------------------------

// Off by default: a minimal image stays minimal. Turn on what the payload
// actually needs. WebView2 matters for anything hosting a browser control,
// because Edge is uninstalled.
install_webview2 = false
install_vcredist = false

// ---- locale ------------------------------------------------------------

// system_locale sets the ANSI codepage legacy applications read data in.
timezone      = "UTC"
system_locale = "en-US"
input_locale  = "en-US"
ui_language   = "en-US"

// ---- Hyper-V -----------------------------------------------------------

switch_name = "Default Switch"
vm_name     = "WINMIN"

// ---- build behaviour ---------------------------------------------------

// false leaves a portable exported VM folder next to the build VM, which costs
// a second full copy of the VHDX. true halves the peak disk use.
skip_export = false

// sysprep /generalize on the last shutdown, so every clone gets its own SID,
// hostname and machine GUID. Set false if sysprep refuses on your image and you
// can live with identical SIDs across clones.
generalize = true
