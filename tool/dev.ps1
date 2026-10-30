<#
.SYNOPSIS
  One entry point for everyday Absorb Plus work on Windows.

.DESCRIPTION
  check      pub get, analyze, full test suite, tool tests, removed-paths check
  build      Windows release into build\windows\x64\runner\Release, then
             verify the exe's version matches pubspec.yaml
  bump       next build number (+1) in pubspec.yaml, for every build the
             owner gets. The beta number (lib/build_info.dart) names the
             next beta to be published and stays put; after publishing one,
             run bump -NextBeta (or -Beta N to set it).
  footprint  how far the fork's lib/ code differs from upstream
  merge      merge upstream origin/main with the fork's rules
             (tool/upstream_merge.py); never commits
  server     the throwaway Audiobookshelf test server (tool/test-server),
             127.0.0.1:13378 only: server up | seed | down | reset
             (reset deletes only tool/test-server/data)
  itest      integration tests (test/integration, tag abs-server) against
             that server, credentials from tool/test-server/.env; never part
             of check

  Every command leaves the generated plugin registrant files as committed.

.EXAMPLE
  .\tool\dev.ps1 check
  .\tool\dev.ps1 build
  .\tool\dev.ps1 build -CloseRunning   # gracefully close a running Release build first
  .\tool\dev.ps1 bump
  .\tool\dev.ps1 server up; .\tool\dev.ps1 server seed; .\tool\dev.ps1 itest
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('check', 'build', 'bump', 'footprint', 'merge', 'server', 'itest')]
  [string]$Command,
  [Parameter(Position = 1)]
  [string]$Action = '',
  [int]$Beta = 0,
  [switch]$CloseRunning,
  [switch]$NextBeta,
  [switch]$Full
)
$script:ShowFull = [bool]$Full

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
# Full tool output goes to build\dev-logs\; the console gets one line per step
# (and the tail of the log only when a step fails). Keeps Claude's context
# small. Pass -Full to stream everything.
$logDir = Join-Path $root 'build\dev-logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
function Invoke-Step {
  param([string]$Name, [scriptblock]$Run, [string]$SummaryPattern = '')
  $log = Join-Path $logDir "$Name.log"
  if ($script:ShowFull) {
    & $Run 2>&1 | Tee-Object -FilePath $log
  } else {
    & $Run *> $log
  }
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    Write-Host "FAILED: $Name (exit $code). Last lines of $log :" -ForegroundColor Red
    Get-Content $log -Tail 40 | ForEach-Object { Write-Host "  $_" }
    throw "$Name failed"
  }
  $summary = if ($SummaryPattern) {
    (Select-String -Path $log -Pattern $SummaryPattern | Select-Object -Last 1).Line
  }
  Write-Host ("ok: $Name" + $(if ($summary) { " - $($summary.Trim())" } else { '' }))
}
function Invoke-Flutter {
  $words = @($args | Where-Object { $_ -notlike '-*' } | Select-Object -First 2)
  $name = 'flutter-' + ($words -join '-')
  $flutterArgs = $args
  Invoke-Step -Name $name -Run { & $flutter @flutterArgs } `
    -SummaryPattern 'No issues found|issues found|All tests passed|tests? passed|Built '
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
      Invoke-Flutter test --no-pub --reporter expanded
    } finally { Restore-Generated }
    Invoke-Step -Name 'tool-tests' -Run { python -m unittest discover -s tool/tests } `
      -SummaryPattern '^Ran \d+ tests'
    Invoke-Step -Name 'removed-paths' -Run { python tool/check_fork_removed.py } -SummaryPattern '^OK'
    Write-Host 'check passed' -ForegroundColor Green
  }

  'merge' {
    python tool/upstream_merge.py
    Write-Host 'Merge prepared (not committed). Resolve anything listed, then run check and build.' -ForegroundColor Yellow
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
    # Releases are batched: the beta number names the next beta to publish
    # and only moves after one is published (-NextBeta) or is set (-Beta N).
    $current = [int]$Matches[1]
    $beta = if ($Beta -gt 0) { $Beta } elseif ($NextBeta) { $current + 1 } else { $current }
    (Get-Content pubspec.yaml -Raw) -replace "(?m)^version:\s*\S+", "version: $next" |
      Set-Content pubspec.yaml -NoNewline
    $info -replace 'const int kBetaNumber = \d+;', "const int kBetaNumber = $beta;" |
      Set-Content lib/build_info.dart -NoNewline
    Write-Host "version $version -> $next, beta -> $beta (commit with: chore: bump build identifier to $next (Beta $beta))" -ForegroundColor Green
  }

  'server' {
    # Throwaway Audiobookshelf for integration tests. Never the owner's server.
    $serverDir = Join-Path $root 'tool\test-server'
    $compose = @('compose', '-f', (Join-Path $serverDir 'docker-compose.yml'))
    if ($Action -notin @('up', 'seed', 'down', 'reset')) {
      throw 'Usage: dev.ps1 server up|seed|down|reset'
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Docker engine is not running. Start Docker Desktop and retry.' }
    switch ($Action) {
      'up' {
        Invoke-Step -Name 'server-up' -Run { docker @compose up -d }
        $deadline = (Get-Date).AddSeconds(120)
        $ready = $false
        while (-not $ready -and (Get-Date) -lt $deadline) {
          try {
            $ready = (Invoke-WebRequest 'http://127.0.0.1:13378/healthcheck' -TimeoutSec 3).StatusCode -eq 200
          } catch { Start-Sleep -Seconds 2 }
        }
        if (-not $ready) { throw 'Test server did not answer on 127.0.0.1:13378 within 120 s (docker compose logs abs).' }
        Write-Host 'ok: server ready on http://127.0.0.1:13378'
      }
      'seed' {
        Invoke-Step -Name 'server-seed' -Run { python (Join-Path $serverDir 'seed.py') } -SummaryPattern '^seed: done'
      }
      'down' { Invoke-Step -Name 'server-down' -Run { docker @compose down } }
      'reset' {
        Invoke-Step -Name 'server-down' -Run { docker @compose down -v --remove-orphans }
        # Only ever the git-ignored data folder, and never through a link.
        $data = Join-Path $serverDir 'data'
        if (Test-Path -LiteralPath $data) {
          $links = @(Get-ChildItem -LiteralPath $data -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
          if ($links.Count -gt 0) { throw "Refusing to delete ${data}: it contains a link ($($links[0].FullName))" }
          Remove-Item -LiteralPath $data -Recurse -Force
        }
        Write-Host "ok: server reset ($data removed; .env kept for reuse)"
      }
    }
  }

  'itest' {
    # Integration tests against tool/test-server. dart_test.yaml skips the
    # abs-server tag everywhere else, so --run-skipped is what enables them;
    # each suite still skips itself when the server or credentials are missing.
    $envFile = Join-Path $root 'tool\test-server\.env'
    if (Test-Path -LiteralPath $envFile) {
      foreach ($line in Get-Content -LiteralPath $envFile) {
        if ($line -match '^\s*(ABS_TEST_\w+)\s*=\s*(.*)$') {
          Set-Item -Path "env:$($Matches[1])" -Value $Matches[2].Trim()
        }
      }
    } else {
      Write-Host 'No tool/test-server/.env: tests will skip (run server up, then server seed).' -ForegroundColor Yellow
    }
    try {
      Invoke-Step -Name 'flutter-itest' `
        -Run { & $flutter test --no-pub --tags abs-server --run-skipped --concurrency=1 --reporter expanded test/integration } `
        -SummaryPattern '^\d+:\d+ \+\d+.*(passed|skipped|failed)'
    } finally { Restore-Generated }
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
