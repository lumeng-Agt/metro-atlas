param(
  [string]$Godot = ".tools/godot-runtime/Godot_v4.7.2-stable_win64_console.exe",
  [string]$DataDir = ""
)
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $DataDir) { $DataDir = Join-Path $projectRoot ("test-artifacts/story-restart-" + [guid]::NewGuid().ToString("N")) }
if (-not [System.IO.Path]::IsPathRooted($DataDir)) { throw "DataDir must be absolute" }
Write-Host "Isolated data directory: $DataDir"
for ($round=0; $round -lt 5; $round++) {
  $output = & $Godot --headless --path $projectRoot --script res://tests/story_restart_process.gd -- "--data-dir=$DataDir" "--round=$round" 2>&1
  $ok = $?
  # A wrapper script on PATH leaves $LASTEXITCODE null, and $null -ne 0 is
  # true, so judge by $? and the output instead.
  $output | Write-Output
  $bad = $output | Select-String -Pattern 'SCRIPT ERROR:|Failed to load script'
  if (-not $ok -or $bad) {
    if ($bad) { $bad | Select-Object -First 10 | ForEach-Object { Write-Output "OFFENDING: $($_.Line)" } }
    throw "Independent restart round failed: $round"
  }
}
