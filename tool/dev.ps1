<#
.SYNOPSIS
  One entry point for everyday Absorb Plus work on Windows.

.DESCRIPTION
  check      pub get, analyze, full test suite
  build      Windows release into build\windows\x64\runner\Release, then
             verify the exe's version matches pubspec.yaml
  bump       next build number (+1) and next beta number, in pubspec.yaml
             and lib/build_info.dart (use -Beta N to set the beta number)
  footprint  how far the fork's lib/ code differs from upstream

  Every command leaves the generated plugin registrant files as committed.

.EXAMPLE
  .\tool\dev.ps1 check
  .\tool\dev.ps1 build
  .\tool\dev.ps1 build -CloseRunning   # gracefully close a running Release build first
  .\tool\dev.ps1 bump
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('check', 'build', 'bump', 'footprint')]
  [string]$Command,
  [int]$Beta = 0,
  [switch]$CloseRunning
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$flutter = if ($env:FLUTTER) { $env:FLUTTER }
  elseif (Test-Path 'C:\Users\pc\develop\flutter\bin\flutter.bat') { 'C:\Users\pc\develop\flutter\bin\flutter.bat' }
  else { 'flutter' }
# NuGet (installed per user by winget) is needed by the WebView plugin build.
$wingetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
if ((Test-Path $wingetLinks) -and ($env:Path -notlike "*$wingetLinks*")) {
  $env:Path = "$env:Path;$wingetLinks"
}

$generated = @(
  'linux/flutter/generated_plugin_registrant.cc',
  'linux/flutter/generated_plugin_registrant.h',
  'linux/flutter/generated_plugins.cmake',
  'windows/flutter/generated_plugin_registrant.cc',
  'windows/flutter/generated_plugin_registrant.h',
  'windows/flutter/generated_plugins.cmake'
)
function Restore-Generated {
  # Only after building: a --no-pub build needs the locally regenerated list.
  git restore --source=HEAD -- @generated 2>$null
}
function Invoke-Flutter {
  & $flutter @args
  if ($LASTEXITCODE -ne 0) { throw "flutter $($args -join ' ') failed ($LASTEXITCODE)" }
}
function Get-PubspecVersion {
  $line = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
  return $line.Matches[0].Groups[1].Value
}

switch ($Command) {
  'check' {
    try {
      Invoke-Flutter pub get
      Invoke-Flutter analyze --no-pub --no-fatal-infos
      Invoke-Flutter test --no-pub
    } finally { Restore-Generated }
    Write-Host 'check passed' -ForegroundColor Green
  }

  'build' {
    $exe = Join-Path $root 'build\windows\x64\runner\Release\absorb.exe'
    $running = Get-Process -Name absorb -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -eq $exe }
    if ($running) {
      if (-not $CloseRunning) {
        throw "The Release absorb.exe is running (pid $($running.Id)). Close it or pass -CloseRunning."
      }
      foreach ($p in $running) { [void]$p.CloseMainWindow() }
      $deadline = (Get-Date).AddSeconds(15)
      while ((Get-Date) -lt $deadline -and
             (Get-Process -Id $running.Id -ErrorAction SilentlyContinue)) {
        Start-Sleep -Milliseconds 500
      }
      if (Get-Process -Id $running.Id -ErrorAction SilentlyContinue) {
        throw 'absorb.exe did not close; close it manually and retry.'
      }
    }
    if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
      throw 'NuGet CLI not found. Install it with: winget install Microsoft.NuGet'
    }
    try {
      Invoke-Flutter pub get
      Invoke-Flutter build windows --release --no-pub --dart-define=GITHUB_BUILD=true
    } finally { Restore-Generated }
    $expected = Get-PubspecVersion
    $actual = (Get-Item $exe).VersionInfo.ProductVersion
    if ($actual -ne $expected) { throw "absorb.exe reports $actual but pubspec.yaml says $expected" }
    Write-Host "built $exe ($actual, $((Get-Item $exe).LastWriteTime))" -ForegroundColor Green
  }

  'bump' {
    $version = Get-PubspecVersion
    if ($version -notmatch '^(\d+\.\d+\.\d+)\+(\d+)$') { throw "Unexpected version: $version" }
    $next = "$($Matches[1])+$([int]$Matches[2] + 1)"
    $info = Get-Content lib/build_info.dart -Raw
    if ($info -notmatch 'const int kBetaNumber = (\d+);') { throw 'kBetaNumber not found' }
    $beta = if ($Beta -gt 0) { $Beta } else { [int]$Matches[1] + 1 }
    (Get-Content pubspec.yaml -Raw) -replace "(?m)^version:\s*\S+", "version: $next" |
      Set-Content pubspec.yaml -NoNewline
    $info -replace 'const int kBetaNumber = \d+;', "const int kBetaNumber = $beta;" |
      Set-Content lib/build_info.dart -NoNewline
    Write-Host "version $version -> $next, beta -> $beta (commit with: chore: bump build identifier to $next (Beta $beta))" -ForegroundColor Green
  }

  'footprint' {
    git fetch origin main --quiet
    git diff --stat origin/main -- lib ':!lib/l10n' | Select-Object -Last 1
    Write-Host 'Largest differences from upstream (fork-only files count in full):'
    git diff --numstat origin/main -- lib ':!lib/l10n' |
      ForEach-Object { $c = $_ -split "`t"; [pscustomobject]@{ Lines = [int]$c[0] + [int]$c[1]; File = $c[2] } } |
      Sort-Object Lines -Descending | Select-Object -First 10 | Format-Table -AutoSize
  }
}
