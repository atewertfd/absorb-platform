<#
.SYNOPSIS
  Samples RAM and CPU of a running Absorb Plus build (read-only).

.DESCRIPTION
  Finds absorb.exe by path, samples it once a second, and prints working set,
  private memory and CPU (as a percentage of one core). It only reads process
  counters; it never starts, stops, or changes the app. Run the same scenario
  (idle on Home, playing a book, scrolling the library, downloading) on two
  builds to compare them.

.EXAMPLE
  .\tool\measure-windows-usage.ps1 -Seconds 60 -Label "idle on Home"
#>
param(
  [string]$ExePath = (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\absorb.exe'),
  [int]$Seconds = 30,
  [string]$Label = ''
)

$target = (Resolve-Path $ExePath -ErrorAction SilentlyContinue).Path
if (-not $target) { Write-Error "Not found: $ExePath"; exit 1 }
$process = Get-Process -Name absorb -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -eq $target } | Select-Object -First 1
if (-not $process) { Write-Error "absorb.exe from $target is not running"; exit 1 }

$version = (Get-Item $target).VersionInfo.ProductVersion
$cpuStart = $process.TotalProcessorTime
$started = Get-Date
$workingSet = @()
for ($i = 0; $i -lt $Seconds; $i++) {
  Start-Sleep -Seconds 1
  $process.Refresh()
  if ($process.HasExited) { Write-Error 'absorb.exe exited while sampling'; exit 1 }
  $workingSet += [math]::Round($process.WorkingSet64 / 1MB, 1)
}
$elapsed = ((Get-Date) - $started).TotalSeconds
$cpu = ($process.TotalProcessorTime - $cpuStart).TotalSeconds / $elapsed * 100
$stats = $workingSet | Measure-Object -Minimum -Maximum -Average

[pscustomobject]@{
  Version        = $version
  Label          = $Label
  Seconds        = $Seconds
  UptimeMinutes  = [math]::Round(((Get-Date) - $process.StartTime).TotalMinutes, 1)
  WorkingSetMB   = '{0} avg ({1}-{2})' -f [math]::Round($stats.Average, 1), $stats.Minimum, $stats.Maximum
  PrivateMB      = [math]::Round($process.PrivateMemorySize64 / 1MB, 1)
  CpuPctOneCore  = [math]::Round($cpu, 1)
  Threads        = $process.Threads.Count
  Handles        = $process.HandleCount
} | Format-List
