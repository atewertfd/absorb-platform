# Checks the Windows runner with the probe target (tool/windows_shell_probe.dart),
# which starts libmpv, SMTC, WebView2 and the Windows shell channel but never
# signs in or reads account data. Times how long absorb.exe takes to exit after
# its window is closed, and runs the shell checks (minimum size, full screen,
# always on top, keep awake, taskbar, tray, single instance, start with Windows).
# Never point this at the real app: it would use the owner's data.
# The probe is built into the usual Release folder, so -Build always rebuilds
# the normal app at the end with dev.ps1 build's flags (GITHUB_BUILD=true).
# Close a running Release absorb.exe first; the owner's beta copy is untouched.
#
#   .\tool\verify-windows-shell.ps1 -Build      # build probe, run, rebuild app
#   .\tool\verify-windows-shell.ps1             # run against an existing probe build
#
# The probe keeps its settings under HKCU\Software\Absorb Plus\Probe and its
# startup entry as "Absorb Plus (probe)"; both are removed at the end.
param(
  [string]$Flutter = 'C:\Users\pc\develop\flutter\bin\flutter.bat',
  [switch]$Build,
  [int]$ExitBudgetMs = 3000,
  [string[]]$Scenarios = @('bare', 'audio play', 'audio stream', 'audio play webview',
    'audio play stream shell autostart', 'audio play shell tray', 'single')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root 'build\windows\x64\runner\Release\absorb.exe'
$logDir = Join-Path $root 'build\windows-shell-probe'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Add-Type -Namespace AbsorbProbe -Name Native -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
public delegate bool EnumProc(IntPtr hwnd, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc proc, IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, System.Text.StringBuilder name, int max);
public static IntPtr FindAppWindow(uint pid) {
  IntPtr found = IntPtr.Zero;
  EnumWindows((h, l) => {
    uint owner; GetWindowThreadProcessId(h, out owner);
    var name = new System.Text.StringBuilder(64); GetClassName(h, name, 64);
    if (owner == pid && name.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") { found = h; return false; }
    return true;
  }, IntPtr.Zero);
  return found;
}
'@

function Get-ThreadReport([System.Diagnostics.Process]$p) {
  $p.Refresh()
  $modules = @($p.Modules | ForEach-Object {
      [pscustomobject]@{ Name = $_.ModuleName; Base = [int64]$_.BaseAddress; End = [int64]$_.BaseAddress + $_.ModuleMemorySize }
    })
  foreach ($t in $p.Threads) {
    $start = [int64]$t.StartAddress
    $mod = $modules | Where-Object { $start -ge $_.Base -and $start -lt $_.End } | Select-Object -First 1
    '  thread {0,6} {1,-8} start {2}' -f $t.Id, $t.ThreadState, $(if ($mod) { $mod.Name } else { '?' })
  }
}

function Start-Probe([string]$name, [string[]]$extra, [string]$flush) {
  $out = Join-Path $logDir "$name.out.log"
  $err = Join-Path $logDir "$name.err.log"
  Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue
  $probeArgs = @('--probe') + $extra
  if ($flush) { $probeArgs += "flush=$flush" }
  $p = Start-Process -FilePath $exe -ArgumentList $probeArgs -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
  $deadline = (Get-Date).AddSeconds(45)
  while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
    if ((Test-Path $out) -and (Select-String -LiteralPath $out -Pattern '^PROBE (READY|FAIL)' -Quiet)) { break }
    Start-Sleep -Milliseconds 200
  }
  return [pscustomobject]@{ Process = $p; Out = $out }
}

function Wait-Exit($p, [int]$ms) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $exited = $p.WaitForExit($ms)
  return [pscustomobject]@{ Exited = $exited; Ms = $sw.ElapsedMilliseconds }
}

function Invoke-Scenario([string]$scenario) {
  $name = ($scenario -replace '[^a-z0-9]+', '-')
  $words = $scenario -split ' ' | Where-Object { $_ -and $_ -ne 'bare' }
  $flush = Join-Path $logDir "$name.flush.txt"
  Remove-Item -LiteralPath $flush -ErrorAction SilentlyContinue
  $wantsFlush = $words -contains 'shell'
  $probe = Start-Probe $name $words $flush
  $p = $probe.Process
  $lines = @()
  try {
    if ($p.HasExited) { return @("FAIL  [$scenario] exited before ready (code $($p.ExitCode))") }
    if (-not (Select-String -LiteralPath $probe.Out -Pattern '^PROBE READY' -Quiet)) { return @("FAIL  [$scenario] not ready") }
    Start-Sleep -Milliseconds 1000
    $checks = @(Select-String -LiteralPath $probe.Out -Pattern '^PROBE CHECK' | ForEach-Object { '      ' + $_.Line })
    $lines += $checks
    $p.Refresh()
    $hwnd = [AbsorbProbe.Native]::FindAppWindow([uint32]$p.Id)
    if ($p.MainWindowHandle -eq 0) { return $lines + "FAIL  [$scenario] no visible main window" }
    [void]$p.CloseMainWindow()
    if ($words -contains 'tray') {
      # Close to tray: the window hides and the process keeps running.
      $early = Wait-Exit $p 2500
      $hidden = -not [AbsorbProbe.Native]::IsWindowVisible($hwnd)
      if ($early.Exited -or -not $hidden) { return $lines + "FAIL  [$scenario] closing did not hide to the tray (exited=$($early.Exited) hidden=$hidden)" }
      $lines += "      tray: window hidden, process still running after close"
      # tool/dev.ps1's way to quit a copy that sits in the tray.
      $quit = [AbsorbProbe.Native]::RegisterWindowMessage('AbsorbPlus.QuitRequest')
      [void][AbsorbProbe.Native]::PostMessage($hwnd, $quit, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    $result = Wait-Exit $p 15000
    $flushed = Test-Path $flush
    if (-not $result.Exited) {
      $report = (Get-ThreadReport $p) -join "`n"
      return $lines + "HANG  [$scenario] still running 15 s after close (flushed=$flushed)`n$report"
    }
    $ok = $result.Ms -le $ExitBudgetMs -and $p.ExitCode -eq 0 -and ($flushed -or -not $wantsFlush) -and
      -not ($checks -match 'CHECK FAIL')
    $verdict = if ($ok) { 'PASS ' } else { 'FAIL ' }
    return $lines + "$verdict [$scenario] exited in $($result.Ms) ms, code $($p.ExitCode), progress saved=$flushed"
  } finally {
    # Stop only the process this script started.
    if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() }
  }
}

function Invoke-SingleInstance {
  $first = Start-Probe 'single-first' @() $null
  $p = $first.Process
  try {
    if ($p.HasExited) { return "FAIL  [single] first copy exited early" }
    Start-Sleep -Milliseconds 1000
    $hwnd = [AbsorbProbe.Native]::FindAppWindow([uint32]$p.Id)
    [void][AbsorbProbe.Native]::ShowWindow($hwnd, 6)  # SW_MINIMIZE
    Start-Sleep -Milliseconds 500
    $second = Start-Process -FilePath $exe -ArgumentList @('--probe') -PassThru
    $result = Wait-Exit $second 8000
    Start-Sleep -Milliseconds 500
    $restored = -not [AbsorbProbe.Native]::IsIconic($hwnd)
    if (-not $result.Exited) { $second.Kill(); return "FAIL  [single] second launch kept running" }
    $verdict = if ($restored -and $second.ExitCode -eq 0) { 'PASS ' } else { 'FAIL ' }
    return "$verdict [single] second launch exited in $($result.Ms) ms (code $($second.ExitCode)); first window restored=$restored"
  } finally {
    if (-not $p.HasExited) { [void]$p.CloseMainWindow(); if (-not $p.WaitForExit(5000)) { $p.Kill() } }
  }
}

function Clear-ProbeState {
  Remove-Item -Path 'HKCU:\Software\Absorb Plus\Probe' -Recurse -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Absorb Plus (probe)' -ErrorAction SilentlyContinue
}

Push-Location $root
try {
  if ($Build) {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    & $Flutter build windows --release --no-pub -t tool/windows_shell_probe.dart
    if ($LASTEXITCODE -ne 0) { throw 'Probe target failed to build.' }
  }
  Clear-ProbeState
  $results = foreach ($s in $Scenarios) {
    if ($s -eq 'single') { Invoke-SingleInstance } else { Invoke-Scenario $s }
  }
  $results | ForEach-Object { Write-Output $_ }
  if ($results | Where-Object { $_ -match '^(FAIL|HANG)' }) { $failed = $true }
} finally {
  Clear-ProbeState
  if ($Build) {
    # Never leave the probe binary in place of the regular application.
    & $Flutter build windows --release --no-pub --dart-define=GITHUB_BUILD=true -t lib/main.dart
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Restoring the normal application build failed; do not distribute this output.' }
  }
  Pop-Location
}
if ($failed) { exit 1 }
