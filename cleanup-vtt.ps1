param(
    [string]$ChannelName
)

$ErrorActionPreference = "Stop"

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir = Join-Path $baseDir "output"

if ($ChannelName) {
    $safeChannelName = $ChannelName -replace "[@\s]", "-" -replace "[<>:`"/\|?*!]", "" -replace "-+", "-"
    $channelDir = Join-Path $outputDir $safeChannelName
    $dirs = @($channelDir)
} else {
    $dirs = Get-ChildItem -LiteralPath $outputDir -Directory
}

$totalVtt = 0
$totalConverted = 0
$totalCorrupted = 0
$totalFailed = 0
$totalSkipped = 0

foreach ($dir in $dirs) {
    $vttFiles = Get-ChildItem -LiteralPath $dir.FullName -Filter "*.vtt" -ErrorAction SilentlyContinue
    $count = @($vttFiles).Count
    if ($count -eq 0) { continue }
    Write-Host "$($dir.Name): $count VTT file(s)"

    foreach ($vttFile in $vttFiles) {
        $vttPath = $vttFile.FullName
        $txtPath = [IO.Path]::ChangeExtension($vttPath, ".txt")
        $totalVtt++
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $lineCount = 0
        $maxLines = 50000

        if (Test-Path -LiteralPath $txtPath) {
            $txtContent = Get-Content -LiteralPath $txtPath -Raw
            if ($txtContent -match "<[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}>") {
                Write-Host "  Re-converting corrupted: $($vttFile.BaseName)"
                Remove-Item -LiteralPath $txtPath
                $wasCorrupted = $true
                $totalCorrupted++
            } else {
                Write-Host "  Removing orphan VTT (clean TXT exists): $($vttFile.BaseName)"
                Remove-Item -LiteralPath $vttPath
                continue
            }
        } else {
            $wasCorrupted = $false
        }

        try {
            $allLines = Get-Content -LiteralPath $vttPath
            $cleanLines = @()
            $prevLine = $null

            foreach ($line in $allLines) {
                $lineCount++
                if ($lineCount -gt $maxLines) {
                    Write-Host ("  SKIPPED (exceeded " + $maxLines + " lines): " + $vttFile.BaseName)
                    Remove-Item -LiteralPath $vttPath -ErrorAction SilentlyContinue
                    $stopwatch.Stop()
                    $totalSkipped++
                    continue
                }
                if ($line -match "^(?:WEBVTT|\d+$)") { continue }
                if ($line -match "^\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}") { continue }
                if ($line -match "^(?:Kind|Language|Note|Style|Region)\s*:") { continue }
                $line = $line -replace "<[^>]+>", ""
                $line = $line.Trim()
                if ($line -ne "" -and $line -ne $prevLine) {
                    $cleanLines += $line
                    $prevLine = $line
                }
            }

            $text = ($cleanLines -join "`n").Trim()
            $doubleNl = "`n" + "`n"
            $text = $text -replace '(\r?\n){2,}', $doubleNl

            Set-Content -LiteralPath $txtPath -Value $text -Encoding UTF8
            Remove-Item -LiteralPath $vttPath

            $suffix = if ($wasCorrupted) { " (was corrupted)" } else { "" }
            Write-Host ("  Converted" + $suffix + " " + $vttFile.BaseName)
            $totalConverted++
        } catch {
            Write-Host ("  FAILED: " + $vttFile.BaseName + " - " + $_)
            $totalFailed++
        }
    }
}

Write-Host ""
$msg = "Done. VTTs: " + $totalVtt + " | Converted: " + $totalConverted + " | Was-corrupted: " + $totalCorrupted + " | Failed: " + $totalFailed + " | Skipped: " + $totalSkipped
Write-Host $msg
