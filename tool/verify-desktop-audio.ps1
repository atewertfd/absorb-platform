param([string]$Flutter = 'flutter')

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent
Push-Location $projectDirectory
$testProcess = $null
try {
    & $Flutter build windows --release -t tool/desktop_audio_smoke.dart
    if ($LASTEXITCODE -ne 0) { throw 'Audio smoke target failed to build.' }
    $stdoutLog = Join-Path $projectDirectory 'build/desktop-audio-smoke.stdout.log'
    $stderrLog = Join-Path $projectDirectory 'build/desktop-audio-smoke.stderr.log'
    $executable = Join-Path $projectDirectory 'build/windows/x64/runner/Release/absorb.exe'
    $testProcess = Start-Process -FilePath $executable -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    if (-not $testProcess.WaitForExit(60000)) {
        # Stop only the process created by this invocation, never another app.
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'Audio smoke test timed out.'
    }
    Get-Content -LiteralPath $stdoutLog
    Get-Content -LiteralPath $stderrLog
    $report = Get-Content -LiteralPath $stdoutLog -Raw
    if ($testProcess.ExitCode -ne 0 -or $report -notmatch '(?m)^DESKTOP_AUDIO_SMOKE PASS\r?$') {
        throw "Audio smoke test failed (exit $($testProcess.ExitCode)). See build/desktop-audio-smoke.*.log."
    }
    Write-Output 'Native audio smoke test passed with a clean exit.'
} finally {
    try {
        if ($null -ne $testProcess -and -not $testProcess.HasExited) {
            $testProcess.Kill()
            $testProcess.WaitForExit()
        }
        # Never leave the smoke-test binary in place of the regular application.
        & $Flutter build windows --release -t lib/main.dart
        if ($LASTEXITCODE -ne 0) { throw 'Restoring the normal application build failed; do not distribute this output.' }
    } finally {
        Pop-Location
    }
}
