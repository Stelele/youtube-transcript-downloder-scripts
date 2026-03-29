param(
    [Parameter(Mandatory=$true)]
    [string]$ChannelName
)

$ErrorActionPreference = "Stop"

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaultYtDlpPath = Join-Path $baseDir "yt-dlp.exe"

function Get-YtDlp {
    $resolvedPath = $null

    if (Test-Path $defaultYtDlpPath) {
        $resolvedPath = $defaultYtDlpPath
    } else {
        foreach ($dir in $env:PATH -split ";") {
            $candidate = Join-Path $dir "yt-dlp.exe"
            if (Test-Path $candidate) {
                $resolvedPath = $candidate
                break
            }
        }
    }

    if ($null -eq $resolvedPath) {
        Write-Host "yt-dlp not found - downloading latest release to $defaultYtDlpPath..."
        try {
            Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $defaultYtDlpPath -UserAgent "Mozilla/5.0" -TimeoutSec 30
            $resolvedPath = $defaultYtDlpPath
            Write-Host "  Downloaded yt-dlp $((& $resolvedPath --version 2>$null))"
        } catch {
            throw "Failed to download yt-dlp. Download manually from https://github.com/yt-dlp/yt-dlp/releases/latest"
        }
    }

    try {
        $localVersion = & $resolvedPath --version 2>$null
        if ([string]::IsNullOrWhiteSpace($localVersion)) { throw }
    } catch {
        Write-Host "yt-dlp at $resolvedPath is corrupt or unusable - re-downloading..."
        try {
            Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $resolvedPath -UserAgent "Mozilla/5.0" -TimeoutSec 30
            $localVersion = & $resolvedPath --version 2>$null
        } catch {
            throw "Failed to re-download yt-dlp. Download manually from https://github.com/yt-dlp/yt-dlp/releases/latest"
        }
    }

    try {
        $apiResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest" -TimeoutSec 10 -UserAgent "Mozilla/5.0"
        $remoteVersion = $apiResponse.tag_name -replace "^v", ""
        $downloadUrl = $null
        foreach ($asset in $apiResponse.assets) {
            if ($asset.name -eq "yt-dlp.exe") {
                $downloadUrl = $asset.browser_download_url
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
            $downloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/download/v${remoteVersion}/yt-dlp.exe"
        }

        if ($localVersion -ne $remoteVersion) {
            Write-Host "Updating yt-dlp ${localVersion} -> ${remoteVersion}..."
            Invoke-WebRequest -Uri $downloadUrl -OutFile $resolvedPath -UserAgent "Mozilla/5.0" -TimeoutSec 30
            Write-Host "  Updated to $remoteVersion"
        } else {
            Write-Host "yt-dlp is up to date ($localVersion)"
        }
    } catch {
        Write-Host "Warning: could not check for yt-dlp updates - using version $localVersion"
    }

    return $resolvedPath
}

$ytDlpPath = Get-YtDlp

$outputDir = Join-Path $baseDir "output"
$safeChannelName = $ChannelName -replace "[@\s]", "-" -replace "[<>:`"/\|?*!]", "" -replace "-+", "-"
$channelDir = Join-Path $outputDir $safeChannelName
$archiveFile = Join-Path $channelDir "archive.txt"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}
if (-not (Test-Path $channelDir)) {
    New-Item -ItemType Directory -Path $channelDir | Out-Null
}

$channelUrl = "https://www.youtube.com/@$ChannelName"

$idPattern = "^[a-zA-Z0-9_-]{11}$"
$doneIds = @{}

Get-ChildItem -LiteralPath $channelDir -Filter "*.txt" | ForEach-Object {
    if ($_.Name -match "\[([a-zA-Z0-9_-]{11})\](?:\.en)?\.txt$") {
        $doneIds[$matches[1]] = $true
    }
}

if ($doneIds.Count -gt 0 -and -not (Test-Path $archiveFile)) {
    Write-Host "Populating archive from existing transcripts..."
    $doneIds.Keys | ForEach-Object { Add-Content -Path $archiveFile -Value "youtube $_" }
}

Write-Host "Converting any existing VTT files..."
Get-ChildItem -LiteralPath $channelDir -Filter "*.vtt" | ForEach-Object {
    $vttPath = $_.FullName
    $txtPath = [IO.Path]::ChangeExtension($vttPath, ".txt")

    if ($_.Name -match "\[([a-zA-Z0-9_-]{11})\]") {
        $doneIds[$matches[1]] = $true
    }

    $wasCorrupted = $false
    if (Test-Path -LiteralPath $txtPath) {
        $txtContent = Get-Content -LiteralPath $txtPath -Raw
        if ($txtContent -match "<[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}>") {
            Write-Host "  Re-converting corrupted transcript: $($_.BaseName)"
            Remove-Item -LiteralPath $txtPath
            $wasCorrupted = $true
        } else {
            Remove-Item -LiteralPath $vttPath
            return
        }
    }

    try {
        $allLines = Get-Content -LiteralPath $vttPath
        $cleanLines = @()
        $prevLine = $null
        $lineCount = 0
        $maxLines = 50000

        foreach ($line in $allLines) {
            $lineCount++
            if ($lineCount -gt $maxLines) {
                Write-Host ("  SKIPPED (exceeded " + $maxLines + " lines): " + $_.BaseName)
                Remove-Item -LiteralPath $vttPath -ErrorAction SilentlyContinue
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
        Write-Host ("  Converted" + $suffix + " " + $_.BaseName)
    } catch {
        Write-Host ("  FAILED to convert: " + $_.BaseName + " - " + $_)
    }
}

Write-Host "Downloading transcripts for @$ChannelName (this may take several minutes)..."
$null = & $ytDlpPath --no-warnings --write-subs --write-auto-subs --sub-lang en --download-archive $archiveFile --format "worst" --output ($channelDir + "/%(title)s [%(id)s].%(ext)s") $channelUrl 2>$null

Write-Host "Converting new VTT to TXT and updating archive..."
Get-ChildItem -LiteralPath $channelDir -Filter "*.vtt" | ForEach-Object {
    $vttPath = $_.FullName
    $txtPath = [IO.Path]::ChangeExtension($vttPath, ".txt")

    if ($_.Name -match "\[([a-zA-Z0-9_-]{11})\]") {
        $vid = $matches[1]
        $isNew = -not $doneIds.ContainsKey($vid)
    } else {
        $vid = $null
        $isNew = $false
    }

    try {
        $allLines = Get-Content -LiteralPath $vttPath
        $cleanLines = @()
        $prevLine = $null
        $lineCount = 0
        $maxLines = 50000

        foreach ($line in $allLines) {
            $lineCount++
            if ($lineCount -gt $maxLines) {
                Write-Host ("  SKIPPED (exceeded " + $maxLines + " lines): " + $_.BaseName)
                Remove-Item -LiteralPath $vttPath -ErrorAction SilentlyContinue
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

        if ($vid -and $isNew) {
            $doneIds[$vid] = $true
            Add-Content -LiteralPath $archiveFile -Value ("youtube " + $vid)
            Write-Host ("  Downloaded + converted: " + $_.BaseName)
        } else {
            Write-Host ("  Converted: " + $_.BaseName)
        }
    } catch {
        Write-Host ("  FAILED to convert: " + $_.BaseName + " - " + $_)
    }
}

$mp4Files = Get-ChildItem -LiteralPath $channelDir -Filter "*.mp4" -ErrorAction SilentlyContinue
if ($mp4Files) {
    foreach ($mp4 in $mp4Files) {
        Write-Host "  Removing downloaded video file: $($mp4.Name)"
        Remove-Item -LiteralPath $mp4.FullName
    }
}

$txtCount = @(Get-ChildItem -LiteralPath $channelDir -Filter "*.txt" | Where-Object { $_.Name -notlike "archive.txt" })
Write-Host "Done. $($txtCount.Count) transcript(s) in $channelDir"
