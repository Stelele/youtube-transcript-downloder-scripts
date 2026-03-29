param(
    [Parameter(Mandatory=$true)]
    [string]$ChannelsFile
)

$ErrorActionPreference = "Stop"

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$singleScript = Join-Path $baseDir "get-transcripts.ps1"

if (-not (Test-Path $ChannelsFile)) {
    throw "Channels file not found: $ChannelsFile"
}

$channels = Get-Content $ChannelsFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -ne "" -and -not $line.StartsWith("#")) { $line }
}

if ($channels.Count -eq 0) {
    Write-Host "No channels found in $ChannelsFile"
    return
}

Write-Host "Loaded $($channels.Count) channel(s) from $ChannelsFile"
Write-Host ""

$results = @{}
$totalDone = 0
$totalFailed = 0

foreach ($ch in $channels) {
    Write-Host "========================================"
    Write-Host "Processing: $ch"
    Write-Host ""

    $exitCode = 0
    & powershell -ExecutionPolicy Bypass -File $singleScript -ChannelName $ch 2>$null
    $exitCode = $LASTEXITCODE

    $safeName = $ch -replace "[@\s]", "-" -replace "[<>:`"/\\|?*!]", "" -replace "-+", "-"
    $chDir = Join-Path $baseDir "output\$safeName"
    $txtCount = 0
    if (Test-Path $chDir) {
        $txtCount = @(@(Get-ChildItem -LiteralPath $chDir -Filter "*.txt" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "archive.txt" })).Count
    }

    if ($exitCode -eq 0) {
        Write-Host ""
        Write-Host "Done: $ch ($txtCount transcripts)"
        $results[$ch] = @{ Status = "Done"; Count = $txtCount }
        $totalDone++
    } else {
        Write-Host ""
        Write-Host "Failed: $ch (exit code: $exitCode)"
        $results[$ch] = @{ Status = "Failed"; Error = "Exit code $exitCode" }
        $totalFailed++
    }

    Write-Host ""
}

Write-Host "========================================"
Write-Host "Summary"
Write-Host "========================================"

foreach ($ch in $channels) {
    $r = $results[$ch]
    if ($r.Status -eq "Done") {
        Write-Host "Done:      $ch ($($r.Count) transcripts)"
    } else {
        Write-Host "Failed:    $ch - $($r.Error)"
    }
}

Write-Host ""
Write-Host "Completed: $totalDone | Failed: $totalFailed"
