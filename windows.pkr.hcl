// Minimal Windows image: a debloated Windows 11 plus a payload folder of your
// choosing. See profiles/ for worked examples.
//
// Plugin:  https://github.com/hashicorp/packer-plugin-hyperv
// oscdimg: ships with the Windows ADK (Deployment Tools), used for the CDs.
packer {
  required_version = ">= 1.11.0"
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
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
  type        = string
  description = "vCPUs during the build"
  default     = "4"
}
variable "vm_memory" {
  type        = string
  description = "Startup memory in MB. Windows 11 setup refuses less than 4096"
  default     = "4096"
}
variable "vm_disk_size" {
  type        = string
  description = "Declared VHDX size in MB. Windows 11 setup refuses less than 65536; a dynamic VHDX only grows to what is used"
  default     = "65536"
}
variable "dynamic_memory" {
  type        = bool
  description = "Let Hyper-V reclaim unused guest RAM"
  default     = true
}
variable "generation" {
  type        = number
  description = "Hyper-V VM generation. Windows 11 needs 2 (UEFI)"
  default     = 2
}
variable "secure_boot" {
  type        = bool
  description = "Secure Boot, required by the Windows 11 setup check"
  default     = true
}
variable "tpm" {
  type        = bool
  description = "vTPM, required by the Windows 11 setup check"
  default     = true
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

// ---------------------------------------------------------------- Payload

variable "install_payload" {
  type        = bool
  description = "Copy a folder into the image"
  default     = true
}
variable "payload_source_dir" {
  type        = string
  description = "Folder on the host, copied as-is into the image. Whatever is in it travels"
  default     = ""
}
variable "payload_iso" {
  type        = string
  description = "ISO built from payload_source_dir and attached as a second DVD. Empty derives \"<payload_source_dir>.iso\""
  default     = ""
}
variable "payload_install_dir" {
  type        = string
  description = "Where the payload lands in the guest. Empty derives \"C:\\<folder name>\", so moving payload_source_dir is a one-variable change"
  default     = ""
}
variable "payload_label" {
  type        = string
  description = "Volume label of the payload ISO. The guest finds the disc by this, not by drive letter"
  default     = "PAYLOAD"
}
variable "payload_marker" {
  type        = string
  description = "File that must exist in the payload, checked on the disc and again after the copy. Empty skips the check"
  default     = ""
}
variable "payload_shortcut" {
  type        = string
  description = "Executable inside the payload to put on the public desktop, relative to payload_install_dir. Empty creates no shortcut"
  default     = ""
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
  description = "Additional provisioning scripts, relative to this template, run after the payload is copied"
  default     = []
}
variable "install_webview2" {
  type        = bool
  description = "Install the WebView2 runtime. Needed by any payload hosting a browser control, since Edge is uninstalled"
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
  description = "Directories Defender should not scan. The payload directory is added on its own."
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
  description = "Attempt the Edge uninstall. WebView2 is always kept, the launcher needs it"
  default     = true
}
variable "remove_appx" {
  type        = bool
  description = "Remove the preinstalled apps, capabilities and optional features"
  default     = true
}
variable "disable_ipv6" {
  type        = bool
  description = "Disable every IPv6 interface except loopback. It is a network change: turn it off if anything in the payload resolves or binds over IPv6"
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

  // One variable moves the whole payload: the ISO and the install directory
  // follow payload_source_dir unless they are set explicitly
  payload_iso         = var.payload_iso != "" ? var.payload_iso : "${var.payload_source_dir}.iso"
  payload_install_dir = var.payload_install_dir != "" ? var.payload_install_dir : (var.payload_source_dir != "" ? "C:\\${basename(var.payload_source_dir)}" : "C:\\Payload")

  tools_files = flatten([for dir in var.tools_dirs : [for f in fileset("${path.root}/${dir}", "*.ps1") : "${path.root}/${dir}/${f}"]])

  // Both branches live in the script rather than here: it has to report why
  // sysprep refused, and a retried shutdown must not generalize twice.
  shutdown_command = "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Windows\\Panther\\Invoke-Shutdown.ps1"

}

source "hyperv-iso" "windows" {
  // Gen 2 UEFI boots from the ISO and still asks for a keypress
  boot_command = ["a<enter><wait>"]
  boot_wait    = "1s"

  vm_name                          = var.vm_name
  cpus                             = var.vm_cpus
  memory                           = var.vm_memory
  enable_dynamic_memory            = var.dynamic_memory
  disk_size                        = var.vm_disk_size
  generation                       = var.generation
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

  // The payload rides in as a second DVD. Nothing is served over the network
  // during the build.
  secondary_iso_images = var.install_payload ? [local.payload_iso] : []

  communicator   = "winrm"
  winrm_username = var.admin_username
  winrm_password = var.admin_password
  winrm_port     = "5985"
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = var.winrm_timeout

  shutdown_command = local.shutdown_command
  shutdown_timeout = "30m"

  cd_label = "unattend"
  cd_content = {
    "autounattend.xml" = templatefile("${path.root}/config/autounattend.pkrtpl.xml", {
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

build {
  sources = ["source.hyperv-iso.windows"]

  // Policies first: they decide what the later removals have to fight with
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

  provisioner "powershell" {
    elevated_user            = var.admin_username
    elevated_password        = var.admin_password
    elevated_execute_command = local.strict_powershell
    environment_vars = [
      "InstallPayload=${var.install_payload}",
      "PayloadInstallDir=${local.payload_install_dir}",
      "PayloadLabel=${var.payload_label}",
      "PayloadMarker=${var.payload_marker}",
      "PayloadShortcut=${var.payload_shortcut}"
    ]
    scripts = concat(["${path.root}/scripts/Copy-Payload.ps1"], [for s in var.extra_scripts : "${path.root}/${s}"])
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
      "PagefileSizeMb=${var.pagefile_size_mb}",
      "InstallPayload=${var.install_payload}",
      "PayloadInstallDir=${local.payload_install_dir}",
      "PayloadMarker=${var.payload_marker}"
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

  post-processor "shell-local" {
    environment_vars = [
      "OutputDirectory=${var.output_directory}/${var.vm_name}",
      "VmName=${var.vm_name}"
    ]
    execute_command = ["powershell.exe", "{{.Vars}} {{.Script}}"]
    env_var_format  = "$env:%s='%s'; "
    script          = "${path.root}/scripts/Optimize-Vhdx.ps1"
  }
}
