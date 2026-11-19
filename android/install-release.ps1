<#
.SYNOPSIS
  Builds LIT in release mode and installs or updates it on the connected phone,
  keeping all of its data.

.DESCRIPTION
  In VS Code: Ctrl+Shift+B (task "Install LIT on phone"). Or run:

      powershell -ExecutionPolicy Bypass -File android\install-release.ps1

  Why not the other ways:
  - Stopping a `flutter run` session force-stops the app, and Android then
    deletes every reminder it had scheduled (until LIT is opened again).
  - `flutter install` UNINSTALLS the old version first, deleting all data.

  This uses `adb install -r`, which replaces the app in place. If anything
  goes wrong, the app already on the phone and its data are left untouched.
#>
$ErrorActionPreference = 'Stop'
$package = 'com.lactationinductiontracker.app'
$root = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path (Join-Path $PSScriptRoot 'key.properties'))) {
  throw 'android\key.properties not found. Run android\create-release-key.ps1 first so the app is signed with your release key.'
}

# adb from the Android SDK recorded in local.properties, else PATH.
$adb = $null
$localProps = Join-Path $PSScriptRoot 'local.properties'
if (Test-Path $localProps) {
  $sdkLine = Get-Content $localProps | Where-Object { $_ -like 'sdk.dir=*' } | Select-Object -First 1
  if ($sdkLine) {
    $sdk = ($sdkLine -replace '^sdk.dir=', '') -replace '\\\\', '\' -replace '\\:', ':'
    $candidate = Join-Path $sdk 'platform-tools\adb.exe'
    if (Test-Path $candidate) { $adb = $candidate }
  }
}
if (-not $adb) { $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $adb) { throw 'adb not found. Install the Android SDK platform-tools.' }

$devices = @(& $adb devices | Select-String -Pattern "`tdevice$")
if ($devices.Count -eq 0) { throw 'No phone found. Connect it by USB with USB debugging on, and allow this computer if asked.' }
if ($devices.Count -gt 1) { throw 'More than one device is connected. Disconnect the others (or close emulators) and try again.' }

Push-Location $root
try {
  & flutter build apk --release
  if ($LASTEXITCODE -ne 0) { throw 'Build failed; nothing was installed.' }
}
finally { Pop-Location }

$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
Write-Host "Installing $apk ..."
$ErrorActionPreference = 'Continue' # adb reports failures on stderr
$output = (& $adb install -r $apk 2>&1 | ForEach-Object { "$_" }) -join "`n"
$ErrorActionPreference = 'Stop'
Write-Host $output

if ($output -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
  throw @'
The LIT on your phone was signed with a different key (probably installed before
your release key existed), so Android won't update it. Nothing was changed.
To switch it over:
  1. In LIT on the phone: Settings > Backup & data > Export backup.
  2. Uninstall LIT from the phone.
  3. Run this task again.
  4. In LIT: Settings > Backup & data > Restore from backup.
'@
}
if ($output -notmatch '(?m)^Success') { throw 'Install failed (see above). The app on your phone was not changed.' }

# Opening LIT reschedules its reminders.
& $adb shell am start -n "$package/.MainActivity" | Out-Null
Write-Host ''
Write-Host 'LIT is updated and open on your phone. Its data was kept and reminders are rescheduled.' -ForegroundColor Green
