<#
.SYNOPSIS
  Creates the release signing key for LIT and writes android/key.properties.

.DESCRIPTION
  Run once from the project folder:

      powershell -ExecutionPolicy Bypass -File android\create-release-key.ps1

  You'll be asked to choose a password. Every future release build must be
  signed with this key: Android only installs an update over the existing app
  when the signatures match. Back up the keystore file AND the password
  (a password manager is a good place for both). Without them you would have
  to uninstall LIT, which deletes its data, to install a new version.

  It never overwrites an existing keystore or key.properties.
#>
param(
  # Where to create the keystore. Outside the repository on purpose.
  [string]$KeystorePath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'LIT Signing Key\lit-release.jks'),
  [string]$KeyPropertiesPath = (Join-Path $PSScriptRoot 'key.properties'),
  [string]$Alias = 'lit',
  # Optional, for non-interactive use. When omitted you are prompted.
  [securestring]$Password
)

$ErrorActionPreference = 'Stop'

function Find-Keytool {
  $candidates = @(
    $(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' }),
    "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
    "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe"
  ) | Where-Object { $_ -and (Test-Path $_) }
  if ($candidates) { return @($candidates)[0] }
  $cmd = Get-Command keytool -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'keytool not found. Install Android Studio or set JAVA_HOME.'
}

function ConvertTo-PlainText([securestring]$s) {
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# Java .properties values: escape backslashes, and a leading space (which the
# loader would otherwise strip).
function ConvertTo-PropertyValue([string]$s) {
  $escaped = $s.Replace('\', '\\')
  if ($escaped.StartsWith(' ')) { $escaped = '\' + $escaped }
  $escaped
}

if (Test-Path $KeystorePath) { throw "A keystore already exists at '$KeystorePath'. Not overwriting it." }
if (Test-Path $KeyPropertiesPath) { throw "'$KeyPropertiesPath' already exists. Not overwriting it." }

if (-not $Password) {
  $Password = Read-Host 'Choose a password for the LIT signing key (min 6 characters)' -AsSecureString
  $confirm = Read-Host 'Type it again' -AsSecureString
  if ((ConvertTo-PlainText $Password) -cne (ConvertTo-PlainText $confirm)) { throw 'Passwords did not match.' }
}
$plain = ConvertTo-PlainText $Password
if ($plain.Length -lt 6) { throw 'The password must be at least 6 characters.' }
# PKCS12 keystores only accept plain ASCII passwords.
if ($plain -cnotmatch '^[\x20-\x7E]+$') {
  throw 'Use only standard keyboard characters (A-Z, 0-9, punctuation, spaces) in the password; accented letters and emoji are not supported.'
}

$keytool = Find-Keytool
New-Item -ItemType Directory -Force (Split-Path $KeystorePath) | Out-Null

# Pass the password through an environment variable, not the command line.
$env:LIT_SIGNING_PASSWORD = $plain
try {
  & $keytool -genkeypair -noprompt `
    -keystore $KeystorePath -storetype PKCS12 `
    -alias $Alias -keyalg RSA -keysize 2048 -validity 10000 `
    -dname 'CN=LIT Lactation Induction Tracker' `
    -storepass:env LIT_SIGNING_PASSWORD -keypass:env LIT_SIGNING_PASSWORD
  if ($LASTEXITCODE -ne 0) { throw "keytool failed with exit code $LASTEXITCODE." }
}
finally {
  Remove-Item Env:\LIT_SIGNING_PASSWORD -ErrorAction SilentlyContinue
}

$escaped = ConvertTo-PropertyValue $plain
$storeFile = (Resolve-Path $KeystorePath).Path.Replace('\', '/')
$content = @"
# LIT release signing. Created by create-release-key.ps1. Never commit this file.
storePassword=$escaped
keyPassword=$escaped
keyAlias=$Alias
storeFile=$storeFile
"@
# ASCII without a BOM, which is what Gradle's Properties loader expects.
[System.IO.File]::WriteAllText($KeyPropertiesPath, $content, [System.Text.Encoding]::ASCII)
$plain = $null; $escaped = $null

Write-Host ''
Write-Host "Keystore:       $KeystorePath"
Write-Host "Key properties: $KeyPropertiesPath"
Write-Host ''
Write-Host 'Back up the keystore file and your password now.' -ForegroundColor Yellow
