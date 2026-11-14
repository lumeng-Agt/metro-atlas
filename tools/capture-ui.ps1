# UI 截图助手：一条命令驱动 Godot 界面并输出 PNG。
#
#   .\tools\capture-ui.ps1 -Scene workbench
#   .\tools\capture-ui.ps1 -Scene menu,station,saves -Size 1366x768
#
# 输出目录默认 test-artifacts/ui-shots/<时间戳>/，避免覆盖 docs 里的归档截图。

param(
    [string[]]$Scene = @("workbench"),
    [string]$Size = "1600x980",
    [string]$Godot = "",
    [string]$OutDir = "",
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $Godot = Join-Path $repo ".tools/godot-runtime/Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $Godot)) {
    throw "找不到 Godot: $Godot"
}
if (-not $OutDir) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path $repo "test-artifacts/ui-shots/$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 每次用独立数据目录，绝不碰玩家真实存档。
$dataDir = Join-Path $OutDir ".data"
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$results = @()
foreach ($s in $Scene) {
    Write-Host "==> 截图 scene=$s size=$Size" -ForegroundColor Cyan
    $job = Start-Job -ScriptBlock {
        param($Godot, $repo, $s, $Size, $dataDir, $OutDir)
        & $Godot --path $repo --script res://tools/capture_ui.gd -- `
            "--data-dir=$dataDir" "--scene=$s" "--size=$Size" "--out=$OutDir" 2>&1
        "EXITCODE=$LASTEXITCODE"
    } -ArgumentList $Godot, $repo, $s, $Size, $dataDir, $OutDir

    if (Wait-Job $job -Timeout $TimeoutSec) {
        $log = Receive-Job $job
        Remove-Job $job
        $log | Where-Object { $_ -match "CAPTURED|ERROR|error|SCRIPT" } | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" }
        $captured = $log | Where-Object { $_ -match "^CAPTURED " } | ForEach-Object { $_.ToString().Substring(9) }
        if ($captured) { $results += $captured }
    } else {
        Stop-Job $job; Remove-Job $job -Force
        Write-Warning "scene=$s 超时（${TimeoutSec}s），已终止"
    }
}

Write-Host ""
if ($results.Count -eq 0) {
    Write-Warning "没有生成任何截图。"
    exit 1
}
Write-Host "生成 $($results.Count) 张截图：" -ForegroundColor Green
$results | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "把这些路径交给 agent 即可让它'看见'界面。" -ForegroundColor DarkGray
