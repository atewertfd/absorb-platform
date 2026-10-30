<#
.SYNOPSIS
  One-time setup so this PC can build phone APKs signed with the permanent
  Absorb Plus key (tool\dev.ps1 apk -Local). The owner runs this, not Claude.

.DESCRIPTION
  Asks for the keystore password (typed, never shown), checks it against the
  key with keytool, and writes android\key.properties, which git ignores.
  Nothing is printed or logged. The key and password file stay where they are.

.EXAMPLE
  pwsh -File tool\android-signing-setup.ps1
#>
param(
  [string]$Keystore = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Absorb Plus Android signing key\absorb-plus-upload.jks'),
  [string]$Alias = 'absorbplus'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'android\key.properties'

if (-not (Test-Path $Keystore)) { Write-Error "Key not found: $Keystore"; exit 1 }
$keytool = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' } else { 'keytool' }

$secure = Read-Host -AsSecureString 'Absorb Plus signing key password (from password.txt)'
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
if (-not $plain) { Write-Error 'No password entered.'; exit 1 }

# keytool reads the password from an environment variable, so it never
# appears on a command line.
$env:ABSORB_KEY_CHECK = $plain
try {
  & $keytool -list -keystore $Keystore -alias $Alias -storepass:env ABSORB_KEY_CHECK *> $null
  $ok = $LASTEXITCODE -eq 0
} finally {
  Remove-Item Env:ABSORB_KEY_CHECK -ErrorAction SilentlyContinue
}
if (-not $ok) { Write-Error 'That password does not open the key. Nothing was written.'; exit 1 }

# PKCS12 keystores use one password for the store and the key.
$storeFile = $Keystore -replace '\\', '/'
@(
  "storePassword=$plain",
  "keyPassword=$plain",
  "keyAlias=$Alias",
  "storeFile=$storeFile"
) | Set-Content -Path $target -Encoding ascii
$plain = $null

Write-Host "Done: this PC can now build signed phone APKs (android\key.properties, ignored by git)." -ForegroundColor Green
