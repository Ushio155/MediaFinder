# MediaFinder

A local media asset management tool powered by the Everything search engine. Double-click to run: auto-launches the embedded Everything, builds the index, and opens a web console — millisecond search with real-time updates.

## Features

- Millisecond full-text search (Everything real-time index, new files visible within seconds)
- Live updates: search results auto-refresh every 5 seconds in Everything mode — copied, moved or deleted files appear without manual action; Everything is auto-repaired and restarted on abnormal exit so the index stays truly real-time
- Type filters (video / image / audio) + time filters
- Auto-categorization for game & software assets (Genshin, Wuthering Waves, Steam, CapCut, and 30+ more); category names are translated in English UI (e.g. 明日方舟终末地 → "Arknights EndField")
- Auto-generated video thumbnails
- Dark / light theme
- Multilingual UI: auto-detects system language (Chinese UI on zh systems, English otherwise), one-click toggle in the top bar with the choice remembered
- Activity log: records file add / move / delete events in real time, with per-date viewing, export and deletion (phantom-event guard prevents false reports from Everything fluctuation)
- Falls back to traditional disk scanning if Everything is unavailable
- Privacy: when WeChat/QQ receive folders are detected, a prominent notice shows the full path and lets you decide whether to monitor them; opting in automatically excludes chat caches (images/videos/stickers/thumbnails/decorations etc.) and keeps only received files; "don't ask again" is remembered permanently
- Category quota: each category shows up to 100 items so no category can be crowded out by bulk results; category headers and totals show real counts

## Quick Start

Just double-click `MediaFinder.exe` — no installation required:

1. Auto-extracts runtime files to `%LOCALAPPDATA%\MediaFinder`
2. Auto-starts the embedded Everything (reuses an existing instance if present)
3. Auto-starts the web console (port 8765) and opens your browser
4. Creates a desktop shortcut automatically

The first run builds the full-disk index (about 1–3 minutes); after that it's ready in seconds. Everything needs administrator rights to read the NTFS change journal — allow the UAC prompt on first launch for real-time file tracking.

## Build from Source

Requires Windows with .NET Framework 4.x (bundled with Windows):

```powershell
powershell -ExecutionPolicy Bypass -File source\MediaFinder-build.ps1
```

The output `MediaFinder.exe` is a single file embedding all scripts, the web frontend, and the Everything binaries — directly distributable.

## How It Works

```
MediaFinder (web UI)  ←HTTP→  local server (port 8765)  ←IPC→  Everything (real-time index)
```

Search uses the Everything high-speed index via in-process IPC (Everything64.dll); falls back to traditional disk scanning when Everything is not available.

## Repository Layout

```
├── MediaFinder.exe          # distributable single-file build (git-ignored artifact)
├── source/
│   ├── MediaFinder-build.ps1      # build script
│   ├── MediaFinder-launcher.cs    # launcher (self-extract + start server)
│   ├── MediaFinder.ps1            # entry point
│   ├── MediaFinderServer.ps1      # HTTP server (port 8765)
│   ├── MediaFinder.Core.ps1       # core logic + Everything provider
│   ├── MediaFinder-thumb.ps1      # video thumbnail worker
│   ├── web/                       # web console frontend (incl. i18n.js language pack)
│   └── Everything.exe / Everything64.dll  # embedded components (see below)
```

## Third-Party Components

This project embeds and redistributes the following third-party components (see `THIRD-PARTY.txt` for full license texts):

| Component | License | Notes |
|---|---|---|
| Everything (Everything.exe / Everything64.dll) | [MIT](https://www.voidtools.com/License.txt) | Copyright (C) 2018 David Carpenter (voidtools); redistribution permitted with license notice retained |
| PCRE (regular expression engine embedded in Everything) | BSD-3-Clause | Copyright (c) 1997-2012 University of Cambridge |

Official site: <https://www.voidtools.com/>

## License

MediaFinder itself: MIT License (see LICENSE). Everything is Copyright voidtools.
