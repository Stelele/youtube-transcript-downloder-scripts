# YouTube Transcripts

Download and export YouTube video transcripts as clean, plain-text files organized by channel.

## Why these scripts exist

YouTube makes it difficult to export transcripts in bulk. yt-dlp can download subtitles as `.vtt` files, but they contain timestamps, HTML tags, and duplicate lines — not exactly "clean" text you'd want to read or search through.

These scripts automate the full pipeline:

1. Download subtitles using yt-dlp (with archive tracking to avoid re-downloading the same videos)
2. Convert `.vtt` files to clean `.txt` — timestamps removed, duplicates collapsed
3. Delete the downloaded video files, keeping only the transcripts

## Prerequisites

- **PowerShell** (Windows) — that's it. The scripts will download `yt-dlp.exe` automatically on first run.

## Usage

### Download transcripts for a single channel

```powershell
.\get-transcripts.ps1 -ChannelName "MicroConf"
```

This creates `output/MicroConf/` (if it doesn't exist) and saves transcripts as `video-title.en.txt`.

### Download transcripts for multiple channels

Create a text file with one channel name per line (`#` for comments, blank lines ignored):

```
# Marketing channels
MicroConf
TheBootstrappedFounder
RobWalling
```

Then run:

```powershell
.\get-transcripts-batch.ps1 -ChannelsFile "channels.txt"
```

### Clean up leftover .vtt files

If any `.vtt` files weren't converted (e.g., from a previous run), clean them up:

```powershell
# All channels
.\cleanup-vtt.ps1

# Single channel only
.\cleanup-vtt.ps1 -ChannelName "MicroConf"
```

## Output

Transcripts are saved under `output/<ChannelName>/` with one file per video:

```
output/
└── MicroConf/
    ├── archive.txt          # yt-dlp archive — tracks downloaded videos
    ├── video-ids.txt        # List of video IDs for the channel
    ├── introduction-to-statrep.en.txt
    ├── product-led-growth-explained.en.txt
    └── ...
```

The `.en.txt` files contain clean, timestamp-free transcript text — ready to read, search, or feed into another tool.

## Scripts

| Script | Purpose |
|---|---|
| `get-transcripts.ps1` | Download and convert transcripts for one channel |
| `get-transcripts-batch.ps1` | Orchestrate `get-transcripts.ps1` across multiple channels |
| `cleanup-vtt.ps1` | Convert any leftover `.vtt` files to `.txt` |
