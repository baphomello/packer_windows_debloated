// Ragnarok Online client driven by OpenKore over XKore 1.
//
// Use it together with your own file, which carries the paths and the password:
//
//   .\Build-Image.ps1 -VarFile profiles/ragnarok-openkore/profile.pkrvars.hcl,local.pkrvars.hcl
//
// Set payload_source_dir in your local file: it is the game folder on your host.

// A Ragnarok client is not installed, it is a folder that runs where you put
// it. Whatever is in that folder travels with it: bridge DLLs, autologin.ini,
// GordoKore.ini.
install_payload  = true
payload_marker   = "Ragexe.exe"   // keep in step with tools_config.ClientExe
payload_shortcut = "Launcher.exe"

// The launcher is .NET Framework 4.8, which Windows already has, and hosts a
// WebView2 control, which it does not. The client carries its own VC90, VC100,
// VC110 and VC140 runtimes plus D3DX9_42/43, so no redistributable is needed.
install_webview2 = true
install_vcredist = false

// Several clients plus OpenKore sessions on one VM
pagefile_size_mb = 4096

// The operator tools for this profile, copied to C:\Tools in the image
tools_dirs    = ["tools", "profiles/ragnarok-openkore/tools"]
extra_scripts = ["profiles/ragnarok-openkore/scripts/Set-KoreNetwork.ps1"]

// Defaults the in-guest tools read when called with no arguments. Edit
// C:\Tools\config.json on a clone instead of rebuilding for each VM.
//
// Mode: none | route | gateway | alias   (see this profile's README)
// KoreHost must resolve inside ServerPrefix or GameGuard rejects the client.
// Nothing here is baked into a script: every key is also a parameter on the
// tool that reads it, so a clone is a file edit and never a rebuild.
tools_config = {
  Mode         = "none"
  KoreHost     = ""
  NextHop      = ""
  ServerPrefix = "172.65."
  BasePort     = 2350
  Instances    = 3
  GameDir      = "C:\\Ragnarok"
  ClientExe    = "Ragexe.exe"
  LaunchToken  = "1rag1"
  Profiles     = []
  PrefixLength = 24
}
