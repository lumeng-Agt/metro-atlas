param(
    [string]$Godot = ".tools\godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$DataDirectory = ""
)

$ErrorActionPreference = "Stop"
$ProjectDirectory = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$GodotPath = (Resolve-Path (Join-Path $ProjectDirectory $Godot)).Path
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $ProjectDirectory ("test-artifacts\restart-roundtrip-" + [guid]::NewGuid().ToString("N"))
}
New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null
$DataDirectory = (Resolve-Path $DataDirectory).Path.Replace("\", "/")
$env:APPDATA = Join-Path $DataDirectory "ignored-appdata"
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null

function Invoke-RoundTripProcess([string[]]$Arguments, [string]$Description) {
    Write-Host $Description
    & $GodotPath --headless --path $ProjectDirectory --script tests/restart_roundtrip_process_smoke.gd -- @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

Invoke-RoundTripProcess @("--data-dir=$DataDirectory", "--phase=seed") "Seed isolated save with a real two-station route and active passenger batch"
for ($cycle = 1; $cycle -le 5; $cycle++) {
    Invoke-RoundTripProcess @("--data-dir=$DataDirectory", "--cycle=$cycle") "Fresh process restart ${cycle}: load, advance, save and exit"
}
Write-Host "PASS: five independent Godot process restarts; isolated data: $DataDirectory"
