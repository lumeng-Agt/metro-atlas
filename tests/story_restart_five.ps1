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
  $code = $LASTEXITCODE
  $output | Write-Output
  if ($code -ne 0 -or ($output | Select-String -Pattern 'SCRIPT ERROR:|Failed to load script')) { throw "Independent restart round failed: $round" }
}
