// Minimal Windows image: a debloated Windows 11 plus the apps you list, of your
// choosing. See profiles/ for worked examples.
//
// Plugin:  https://github.com/hashicorp/packer-plugin-hyperv
// oscdimg: ships with the Windows ADK (Deployment Tools), used for the CDs.
packer {
  // 1.16.0 is the first release whose HCL2 accepts optional() inside an object
  // type constraint, which is what lets the apps manifest be a typed list with
  // defaults instead of a free-form blob validated in the guest.
  required_version = ">= 1.16.0"
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "~> 1"
    }
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = "~> 1"
    }
  }
}

// ---------------------------------------------------------------- Windows source

variable "iso_url" {
  type        = string
  description = "Path or URL of the Windows ISO"
}
variable "iso_checksum" {
  type        = string
  description = "Checksum of the Windows ISO, or \"none\" to skip the check"
  default     = "none"
}
variable "windows_image_name" {
  type        = string
  description = "Edition to install. List them with Get-WindowsImage -ImagePath <mounted>:\\sources\\install.wim"
  default     = "Windows 11 Pro"
}
variable "windows_product_key" {
  type        = string
  description = "Generic, non-activating edition key, so setup never asks which edition to install"
  default     = "W269N-WFGWX-YVC9B-4J6C9-T83GX"
}
variable "ui_language" {
  type        = string
  description = "Windows UI language present in the ISO"
  default     = "en-US"
}
variable "system_locale" {
  type        = string
  description = "Locale for non-Unicode programs. Legacy applications read their data files in this ANSI codepage"
  default     = "en-US"
}
variable "input_locale" {
  type        = string
  description = "Keyboard layout"
  default     = "en-US"
}
variable "timezone" {
  type        = string
  description = "Guest timezone. A badly skewed clock breaks anything doing TLS or signed sessions"
  default     = "UTC"
}

// ---------------------------------------------------------------- Build VM

variable "vm_name" {
  type        = string
  description = "VM and image name"
  default     = "WINMIN"
}
variable "computer_name" {
  type        = string
  description = "Windows hostname: 1-15 characters, letters, digits and hyphens. Empty uses vm_name, which then has to satisfy the same rule. Randomized again on every clone when generalize is true"
  default     = ""
  validation {
    condition     = var.computer_name == "" || (length(var.computer_name) <= 15 && can(regex("^[A-Za-z0-9-]*[A-Za-z-][A-Za-z0-9-]*$", var.computer_name)))
    error_message = "The computer_name must be 1-15 characters of letters, digits and hyphens, and cannot be all digits."
  }
}
variable "vm_cpus" {
  type        = number
  description = "vCPUs during the build"
  default     = 4
}
variable "vm_memory" {
  type        = number
  description = "Startup memory in MB. Windows 11 setup refuses less than 4096"
  default     = 4096
}
variable "vm_disk_size" {
  type        = number
  description = "Declared disk size in MB. Windows 11 setup refuses less than 65536; a dynamic disk only grows to what is used"
  default     = 65536
}
variable "dynamic_memory" {
  type        = bool
  description = "Let Hyper-V reclaim unused guest RAM"
  default     = true
}
// ---- shared across targets ----------------------------------------------

variable "boot_command" {
  type        = list(string)
  description = "UEFI firmware asks for a keypress to boot the installer, on every target tried so far"
  default     = ["a<enter><wait>"]
}
variable "boot_wait" {
  type        = string
  description = "How long to wait before typing boot_command"
  default     = "1s"
}
variable "shutdown_timeout" {
  type        = string
  description = "How long sysprep has to generalize and power the machine off"
  default     = "30m"
}

// ---- qemu only -----------------------------------------------------------

variable "qemu_format" {
  type        = string
  description = "qcow2 or raw"
  default     = "qcow2"
}
variable "qemu_accelerator" {
  type        = string
  description = "kvm on Linux. Use tcg to build without hardware acceleration, which works anywhere and is far slower"
  default     = "kvm"
}
variable "qemu_disk_interface" {
  type        = string
  description = "virtio is the fast path and needs driver_path set. sata boots with no extra driver at all"
  default     = "virtio"
}
variable "qemu_net_device" {
  type        = string
  description = "virtio-net needs driver_path set. e1000 works with the driver Windows already carries"
  default     = "virtio-net"
}
// Off by default since the answer file writes the LabConfig bypass keys, which
// is what lets one image build on a hypervisor that cannot offer either.
// Turning them on where they exist costs nothing and is closer to real hardware.
variable "secure_boot" {
  type        = bool
  description = "Secure Boot, where the target supports it"
  default     = false
}
variable "tpm" {
  type        = bool
  description = "A virtual TPM, where the target supports it"
  default     = false
}
variable "driver_path" {
  type        = string
  description = "Directory of storage and network drivers for Windows setup to load, as the guest sees it. KVM with virtio disks needs this or setup finds no disk; the other targets do not"
  default     = ""
}
variable "switch_name" {
  type        = string
  description = "Hyper-V virtual switch the build VM attaches to"
  default     = "Default Switch"
}
variable "winrm_timeout" {
  type        = string
  description = "How long to wait for the guest to come up before giving up. It covers the whole unattended install plus OOBE, so it is generous, but a broken answer file is only ever reported when it runs out"
  default     = "2h"
}
variable "headless" {
  type        = bool
  description = "Hide the VM console during the build"
  default     = false
}
variable "skip_export" {
  type        = bool
  description = "Skip the Hyper-V export. Leave false to get a portable VM folder to clone from"
  default     = false
}
variable "output_directory" {
  type        = string
  description = "Host directory for the build VM and the export. Must be a local Windows path, Hyper-V cannot use UNC"
  default     = "C:/HyperV/packer"
}
variable "build_temp_dir" {
  type        = string
  description = "Scratch directory for the unattend ISO and the downloaded-ISO cache. Empty leaves them in the user TEMP on C:. Only Build-Image.ps1 reads this, because Packer takes it from the environment and not from the template"
  default     = ""
}
variable "generalize" {
  type        = bool
  description = "Run sysprep /generalize on shutdown so every clone gets its own SID and machine GUID"
  default     = true
}

// ---------------------------------------------------------------- Credentials

variable "admin_username" {
  type        = string
  description = "Local administrator used by WinRM and by the auto-logon session"
  default     = "ro"
}
variable "admin_password" {
  type        = string
  description = "Password for admin_username"
  sensitive   = true
}

// ------------------------------------------------------------------- Apps

variable "app_sources" {
  type        = list(string)
  description = "Directories on this machine to put on the install CD, each landing at its root under its own name. An app's source is then a path inside one of them"
  default     = []
}
variable "cd_label" {
  type        = string
  description = "Volume label of that CD. The guest finds it by this, not by drive letter"
  default     = "unattend"
}
variable "apps" {
  // Installed in the order written. That order is the only dependency
  // mechanism there is: an app that needs a tool puts that tool above it.
  type = list(object({
    name = string
    // copy    a folder from the disc, as-is
    // archive zip, 7z, tar.gz or tar.xz, unpacked by the tar.exe Windows ships
    // msi     msiexec /i, args default to /qn /norestart
    // exe     an installer run with args
    // git     git clone, which needs git installed by an earlier app
    type               = string
    source             = optional(string, "")
    url                = optional(string, "")
    dest               = optional(string, "")
    args               = optional(list(string), [])
    marker             = optional(string, "")
    shortcut           = optional(string, "")
    extractor          = optional(string, "")
    extractor_args     = optional(list(string), [])
    success_exit_codes = optional(list(number), [])
    // Build-time only: run once every app is in, in reverse order
    uninstall             = optional(list(string), [])
    remove_paths          = optional(list(string), [])
    grant_users           = optional(bool, true)
    exclude_from_defender = optional(bool, true)
  }))
  description = "What to install, in order. See docs/apps.md"
  default     = []

  validation {
    condition     = alltrue([for a in var.apps : contains(["copy", "archive", "msi", "exe", "git"], a.type)])
    error_message = "Each app's type must be one of: copy, archive, msi, exe, git."
  }
  validation {
    condition     = alltrue([for a in var.apps : a.type == "git" || (a.source != "") != (a.url != "")])
    error_message = "Each app needs exactly one of source (on the apps disc) or url. A git app uses url."
  }
  validation {
    condition     = alltrue([for a in var.apps : contains(["msi", "exe"], a.type) || a.dest != ""])
    error_message = "A copy, archive or git app needs dest: the directory it lands in."
  }
  validation {
    condition     = alltrue([for a in var.apps : length(a.uninstall) != 1 || a.uninstall[0] != ""])
    error_message = "An app's uninstall is the program to run and then its arguments, so the first entry must be a path."
  }
  validation {
    condition     = alltrue([for a in var.apps : a.extractor != "" || length(a.extractor_args) == 0])
    error_message = "An app that sets extractor_args must also set extractor, the full path of the tool to run."
  }
}

// ---------------------------------------------------------------- Extensions

variable "profile_name" {
  type        = string
  description = "Profile under profiles/ to build with. Only Build-Image.ps1 reads this, so the usual invocation needs no arguments at all"
  default     = ""
}
variable "tools_dirs" {
  type        = list(string)
  description = "Directories whose *.ps1 are copied to C:\\Tools in the image, for operating the VM after it is built"
  default     = ["tools"]
}
variable "tools_config" {
  // No type: this is free-form, written to C:\Tools\config.json for the tools
  // to read. Nested objects and lists are fine.
  description = "Settings the in-guest tools read when called without arguments"
  default     = {}
}
variable "extra_scripts" {
  type        = list(string)
  description = "Additional provisioning scripts, relative to this template, run after the apps are installed"
  default     = []
}
variable "install_webview2" {
  type        = bool
  description = "Install the WebView2 runtime. Needed by any app hosting a browser control, since Edge is uninstalled"
  default     = false
}
variable "install_vcredist" {
  type        = bool
  description = "Install the VC++ 2015-2022 redistributables. Many applications carry their own and need none"
  default     = false
}
variable "pagefile_size_mb" {
  type        = number
  description = "Fixed pagefile size. A growing pagefile fragments and inflates a dynamic VHDX. 0 leaves it managed by Windows"
  default     = 4096
}

// ---------------------------------------------------------------- Debloat switches

variable "defender_exclusions" {
  type        = list(string)
  description = "Directories Defender should not scan. Each app with a dest is excluded on its own"
  default     = []
}
variable "disable_windows_update" {
  type        = bool
  description = "Kill Windows Update: policy, dead update server, services and tasks"
  default     = true
}
variable "disable_firewall" {
  type        = bool
  description = "Turn off filtering on all three firewall profiles. MpsSvc keeps running either way"
  default     = true
}
variable "remove_edge" {
  type        = bool
  description = "Attempt the Edge uninstall. WebView2 is always kept, since an app may host a browser control"
  default     = true
}
variable "remove_appx" {
  type        = bool
  description = "Remove the preinstalled apps, capabilities and optional features"
  default     = true
}
variable "disable_ipv6" {
  type        = bool
  description = "Disable every IPv6 interface except loopback. It is a network change: turn it off if any app resolves or binds over IPv6"
  default     = true
}
variable "dark_mode" {
  type        = bool
  description = "Dark theme for apps and the shell"
  default     = true
}
variable "settings_page_visibility" {
  type        = string
  description = <<-EOT
    Value for the SettingsPageVisibility policy, which trims the Settings app.
    The default keeps only what is worth having on a disposable VM: screen
    resolution, sound, the network pages, the clock (a skewed one breaks signed
    sessions), Remote Desktop and About. Empty leaves Settings untouched.
    Page names are ms-settings URIs without the prefix; see
    https://learn.microsoft.com/windows/apps/develop/launch/launch-settings-app
    Format: "showonly:page1;page2" or "hide:page1;page2".
  EOT
  default     = "showonly:display;sound;network-status;network-ethernet;dateandtime;remotedesktop;about"
}
variable "disable_vbs" {
  type        = bool
  description = "Turn off virtualization based security and the guest hypervisor"
  default     = true
}

// ----------------------------------------------------------------

locals {
  // $ErrorActionPreference does not abort a failing CDXML cmdlet under Packer's -Command
  strict_powershell = "powershell -executionpolicy bypass \"& { if (Test-Path variable:global:ProgressPreference){$ProgressPreference='SilentlyContinue'};. {{.Vars}}; $PSDefaultParameterValues['*:ErrorAction']='Stop'; &'{{.Path}}'; exit $LastExitCode }\""

  computer_name = var.computer_name != "" ? var.computer_name : var.vm_name

  tools_files = flatten([for dir in var.tools_dirs : [for f in fileset("${path.root}/${dir}", "*.ps1") : "${path.root}/${dir}/${f}"]])

  // Both branches live in the script rather than here: it has to report why
  // sysprep refused, and a retried shutdown must not generalize twice.
  shutdown_command = "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Windows\\Panther\\Invoke-Shutdown.ps1"

  // The install media every target boots from. Held here so the sources differ
  // only where the hypervisors actually differ.
  unattend_content = {
    "autounattend.xml" = templatefile("${path.root}/config/autounattend.pkrtpl.xml", {
      driver_path   = var.driver_path
      image_name    = var.windows_image_name
      product_key   = var.windows_product_key
      computer_name = local.computer_name
      timezone      = var.timezone
      system_locale = var.system_locale
      input_locale  = var.input_locale
      ui_language   = var.ui_language
      username      = var.admin_username
      password      = var.admin_password
    })
    "bootstrap-winrm.ps1" = file("${path.root}/config/bootstrap-winrm.ps1")
  }
}

source "hyperv-iso" "windows" {
  boot_command = var.boot_command
  boot_wait    = var.boot_wait

  vm_name                          = var.vm_name
  cpus                             = var.vm_cpus
  memory                           = var.vm_memory
  enable_dynamic_memory            = var.dynamic_memory
  disk_size                        = var.vm_disk_size
  generation                       = 2
  enable_secure_boot               = var.secure_boot
  enable_tpm                       = var.tpm
  enable_virtualization_extensions = false
  guest_additions_mode             = "disable"
  switch_name                      = var.switch_name
  headless                         = var.headless
  skip_export                      = var.skip_export
  output_directory                 = "${var.output_directory}/${var.vm_name}"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.admin_password
  winrm_port     = "5985"
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = var.winrm_timeout

  shutdown_command = local.shutdown_command
  shutdown_timeout = var.shutdown_timeout

  cd_label   = var.cd_label
  cd_files   = var.app_sources
  cd_content = local.unattend_content
}

// KVM on a Linux host. virtio is the fast path and the reason driver_path
// exists: Windows setup carries no virtio driver and would find no disk.
source "qemu" "windows" {
  boot_command = var.boot_command
  boot_wait    = var.boot_wait

  vm_name          = "${var.vm_name}.${var.qemu_format}"
  output_directory = "${var.output_directory}/${var.vm_name}"
  format           = var.qemu_format
  accelerator      = var.qemu_accelerator
  machine_type     = "q35"
  efi_boot         = true
  vtpm             = var.tpm
  cpus             = var.vm_cpus
  memory           = var.vm_memory
  disk_size        = "${var.vm_disk_size}M"
  disk_interface   = var.qemu_disk_interface
  net_device       = var.qemu_net_device
  headless         = var.headless

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.admin_password
  winrm_port     = 5985
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = var.winrm_timeout

  shutdown_command = local.shutdown_command
  shutdown_timeout = var.shutdown_timeout

  cd_label   = var.cd_label
  cd_files   = var.app_sources
  cd_content = local.unattend_content
}

// Runs on Windows, Linux and macOS, which makes it the portable answer when
// the host hypervisor is not the point.
source "virtualbox-iso" "windows" {
  boot_command = var.boot_command
  boot_wait    = var.boot_wait

  vm_name              = var.vm_name
  output_directory     = "${var.output_directory}/${var.vm_name}"
  guest_os_type        = "Windows11_64"
  firmware             = "efi"
  cpus                 = var.vm_cpus
  memory               = var.vm_memory
  disk_size            = var.vm_disk_size
  iso_interface        = "sata"
  headless             = var.headless
  guest_additions_mode = "disable"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.admin_password
  winrm_port     = 5985
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = var.winrm_timeout

  shutdown_command = local.shutdown_command
  shutdown_timeout = var.shutdown_timeout

  cd_label   = var.cd_label
  cd_files   = var.app_sources
  cd_content = local.unattend_content
}

// Workstation, Fusion and ESXi.
source "vmware-iso" "windows" {
  boot_command = var.boot_command
  boot_wait    = var.boot_wait

  vm_name          = var.vm_name
  output_directory = "${var.output_directory}/${var.vm_name}"
  guest_os_type    = "windows11-64"
  version          = 21
  // vmxnet3 needs VMware Tools, which this image does not install
  network_adapter_type = "e1000e"
  disk_adapter_type    = "lsisas1068"
  cpus                 = var.vm_cpus
  memory               = var.vm_memory
  disk_size            = var.vm_disk_size
  headless             = var.headless

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  vmx_data = { "firmware" = "efi" }

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.admin_password
  winrm_port     = 5985
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = var.winrm_timeout

  shutdown_command = local.shutdown_command
  shutdown_timeout = var.shutdown_timeout

  cd_label   = var.cd_label
  cd_files   = var.app_sources
  cd_content = local.unattend_content
}

build {
  // One set of provisioners, every target. Pick one with -only:
  //   packer build -only=qemu.windows .
  sources = [
    "source.hyperv-iso.windows",
    "source.qemu.windows",
    "source.virtualbox-iso.windows",
    "source.vmware-iso.windows",
  ]

  // First, because everything after it reads and writes this volume. Windows 11
  // 24H2 encrypts it during OOBE on its own, and until that is undone the
  // debloat, the app copy and the component store pass all pay for the
  // encryption on every block. Decrypting here is also decrypting the smallest
  // the disk will ever be.
  provisioner "powershell" {
    elevated_user            = var.admin_username
    elevated_password        = var.admin_password
    elevated_execute_command = local.strict_powershell
    scripts                  = ["${path.root}/scripts/Disable-DriveEncryption.ps1"]
  }

  // Policies next: they decide what the later removals have to fight with
  provisioner "powershell" {
    elevated_user            = var.admin_username
    elevated_password        = var.admin_password
    elevated_execute_command = local.strict_powershell
    environment_vars = [
      "DisableFirewall=${var.disable_firewall}",
      "DisableIpv6=${var.disable_ipv6}",
      "SettingsPageVisibility=${var.settings_page_visibility}",
      "DisableVbs=${var.disable_vbs}",
      "DefenderExclusions=${join(";", var.defender_exclusions)}",
      "DisableWindowsUpdate=${var.disable_windows_update}",
      "RemoveAppx=${var.remove_appx}",
      "RemoveEdge=${var.remove_edge}"
    ]
    scripts = [
      "${path.root}/scripts/Set-Policies.ps1",
      "${path.root}/scripts/Disable-WindowsUpdate.ps1",
      "${path.root}/scripts/Set-DefenderExclusions.ps1",
      "${path.root}/scripts/Disable-Services.ps1",
      "${path.root}/scripts/Remove-Bloat.ps1"
    ]
  }

  provisioner "windows-restart" {
    restart_check_command = "powershell -command \"& {Write-Output 'restarted.'}\""
    restart_timeout       = "15m"
  }

  provisioner "powershell" {
    elevated_user            = var.admin_username
    elevated_password        = var.admin_password
    elevated_execute_command = local.strict_powershell
    environment_vars = [
      "AdminUsername=${var.admin_username}",
      "AdminPassword=${var.admin_password}",
      "DarkMode=${var.dark_mode}",
      "PagefileSizeMb=${var.pagefile_size_mb}",
      "InstallWebView2=${var.install_webview2}",
      "InstallVcRedist=${var.install_vcredist}",
      "DisableWindowsUpdate=${var.disable_windows_update}"
    ]
    scripts = [
      // Again, and deliberately. The first pass runs while first boot is still
      // finishing, and the OOBE update tasks that cannot be disabled put
      // wuauserv back on demand start behind it. By now they have run.
      "${path.root}/scripts/Disable-WindowsUpdate.ps1",
      "${path.root}/scripts/Set-Performance.ps1",
      "${path.root}/scripts/Set-Appearance.ps1",
      "${path.root}/scripts/Set-Autologon.ps1",
      "${path.root}/scripts/Install-Runtimes.ps1"
    ]
  }

  provisioner "windows-restart" {
    restart_check_command = "powershell -command \"& {Write-Output 'restarted.'}\""
    restart_timeout       = "15m"
  }

  // Operator tools stay in the image so a clone can be re-pointed without a rebuild
  provisioner "file" {
    // Only the *.ps1 directly inside: a tools directory may also hold host-side
    // helpers, and those live in a subdirectory this pattern does not reach
    sources     = local.tools_files
    destination = "C:/Tools/"
  }

  provisioner "file" {
    destination = "C:/Tools/config.json"
    content     = jsonencode(var.tools_config)
  }

  // The manifest travels as JSON rather than as environment variables: a list
  // of objects has no honest flattening into NAME=value pairs.
  provisioner "file" {
    destination = "C:/Windows/Temp/apps.json"
    content     = jsonencode(var.apps)
  }

  provisioner "powershell" {
    elevated_user            = var.admin_username
    elevated_password        = var.admin_password
    elevated_execute_command = local.strict_powershell
    environment_vars         = ["AppsLabel=${var.cd_label}"]
    scripts                  = concat(["${path.root}/scripts/Install-Apps.ps1"], [for s in var.extra_scripts : "${path.root}/${s}"])
  }

  // Reads the image back and fails the build when a variable asked for something
  // that is not there. Before the cleanup, so a build that got it wrong says so
  // without first paying for the component store pass.
  provisioner "powershell" {
    elevated_user            = var.admin_username
    elevated_password        = var.admin_password
    elevated_execute_command = local.strict_powershell
    environment_vars = [
      "DefenderExclusions=${join(";", var.defender_exclusions)}",
      "DisableWindowsUpdate=${var.disable_windows_update}",
      "DisableFirewall=${var.disable_firewall}",
      "DisableVbs=${var.disable_vbs}",
      "RemoveEdge=${var.remove_edge}",
      "RemoveAppx=${var.remove_appx}",
      "PagefileSizeMb=${var.pagefile_size_mb}"
    ]
    scripts = ["${path.root}/scripts/Test-ImageState.ps1"]
  }

  // Panther is the one directory Cleanup-System.ps1 leaves alone, so what the
  // shutdown needs survives the last provisioner
  provisioner "file" {
    destination = "C:/Windows/Panther/Invoke-Shutdown.ps1"
    content = templatefile("${path.root}/config/shutdown.pkrtpl.ps1", {
      generalize = var.generalize
    })
  }

  // Sysprep reads this on shutdown to restore auto-logon on every clone
  provisioner "file" {
    destination = "C:/Windows/Panther/sysprep-unattend.xml"
    content = templatefile("${path.root}/config/sysprep-unattend.pkrtpl.xml", {
      timezone      = var.timezone
      system_locale = var.system_locale
      input_locale  = var.input_locale
      ui_language   = var.ui_language
      username      = var.admin_username
      password      = var.admin_password
    })
  }

  provisioner "powershell" {
    elevated_user            = var.admin_username
    elevated_password        = var.admin_password
    elevated_execute_command = local.strict_powershell
    scripts                  = ["${path.root}/scripts/Cleanup-System.ps1"]
  }

  // Last thing before the shutdown that runs sysprep, and the last output the
  // console will show: everything after this point is discarded by the builder.
  provisioner "powershell" {
    elevated_user            = var.admin_username
    elevated_password        = var.admin_password
    elevated_execute_command = local.strict_powershell
    environment_vars         = ["Generalize=${var.generalize}"]
    scripts                  = ["${path.root}/scripts/Test-SysprepReady.ps1"]
  }

  // Hyper-V only: the other targets either compact on their own or produce a
  // format Optimize-VHD cannot open
  post-processor "shell-local" {
    only = ["hyperv-iso.windows"]
    environment_vars = [
      "OutputDirectory=${var.output_directory}/${var.vm_name}",
      "VmName=${var.vm_name}"
    ]
    execute_command = ["powershell.exe", "{{.Vars}} {{.Script}}"]
    env_var_format  = "$env:%s='%s'; "
    script          = "${path.root}/scripts/Optimize-Vhdx.ps1"
  }
}
