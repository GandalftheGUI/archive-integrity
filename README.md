# Archive Integrity

A macOS tool for detecting silent data loss on cold storage archives — bit rot, accidental deletions, and undetected corruption.

<img width="936" height="957" alt="image" src="https://github.com/user-attachments/assets/66e50d50-8ed3-40f7-be01-b3ca0a86c75e" />

## Install

Download the latest `.dmg` from the [Releases page](https://github.com/GandalftheGUI/archive-integrity/releases/latest), open it, and drag **Archive Integrity** into your Applications folder.

## Why I built this

I keep my archive on an external SSD: ~80,000 files, ~3.75 TB, accumulated over years. I plug it in regularly and assume everything is fine. But drives fail quietly. A sector goes bad, a file gets silently corrupted, a folder gets accidentally deleted. You don't find out until years later when you actually need the file.

Most backup tools tell you when a file was added or removed. Almost none tell you when a file's content has changed without you asking it to. That's the gap this fills.

Archive Integrity hashes every file in your archive using BLAKE3 and records the results in a manifest. On future checks it re-hashes and compares. If anything changed, even a single flipped bit, it tells you.

## Who this is for

Anyone who manages a data archive that is static or append-only and needs confidence that nothing has silently drifted or corrupted over time. For example:

- Photographers and videographers with large media archives
- Musicians and audio engineers archiving project files and masters
- Researchers who need to know a dataset hasn't changed since it was collected
- Developers archiving source code, builds, or release artifacts
- Anyone keeping records that must remain unaltered over time

## Who this is not for

- **Anyone whose files change frequently** — every modification will look like a problem
- **Anyone already on ZFS or Btrfs** — checksumming filesystems handle integrity natively at the filesystem level, you probably don't need this tool on top
- **Anyone without a backup strategy** — this tool tells you when something is wrong, but you need backups to recover from it

## How it works

Archive Integrity builds a **manifest** — a plain-text file mapping each file's relative path to its BLAKE3 hash:

```
3a7bd3e2360a3d29eea436fcfb7e44c735d117c42d1c1835420b6b9942dd4f1b  ./2019/Iceland/DSC_0042.NEF
b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c  ./2019/Iceland/DSC_0043.NEF
...
```

The format is b3sum-compatible, so you can verify manifests independently with the `b3sum` tool.

**Quick check** — runs on every mount, completes instantly. Walks the directory tree and compares paths against the manifest to detect missing or new files. No hashing.

**Deep check** — hashes every file and compares against the stored hash. Detects bit rot and silent corruption. Takes minutes to hours depending on archive size and drive speed. Runs automatically on a configurable schedule.

On the first deep check, all files are treated as new and added to the manifest. No separate setup step needed.

## Project structure

```
Sources/
  Engine/          — Core library: hashing, manifest, verification logic
  sentinel/        — CLI tool built on Engine
Archive Integrity/ — macOS menu-bar app built on Engine
Tests/
  EngineTests/     — Unit tests for the Engine library
```

## Components

### Menu-bar app (Archive Integrity)

A native macOS menu-bar app (macOS 14+) that monitors your drives automatically.

- Detects when a monitored volume is mounted and runs a quick check automatically
- Runs deep checks on a configurable schedule
- Shows check history, file counts, and any issues per volume
- Identifies volumes by UUID so it recognises an external drive regardless of mount point
- Sends macOS notifications on failure
- Per-volume concurrency setting for tuning deep check speed (1 for HDDs, 4–8 for SSDs)

### CLI (`sentinel`)

A command-line tool for scripting and manual use.

```bash
# Create a baseline manifest
sentinel baseline /Volumes/MyArchive

# Verify against the manifest
sentinel verify /Volumes/MyArchive

# Quick check (path diff only, no hashing)
sentinel verify --quick /Volumes/MyArchive

# Verify and append any new files found
sentinel verify --append /Volumes/MyArchive

# Throttle I/O (useful on HDDs or to avoid spinning up drives)
sentinel verify --throttle-ms 5 /Volumes/MyArchive
```

## Performance

Verification is I/O-bound. BLAKE3 processes data at ~10 GB/s on Apple Silicon, faster than any drive can supply it. Throughput is limited entirely by the drive:

| Drive type | Typical throughput | Rough time for 3.75 TB |
|---|---|---|
| External HDD | ~150 MB/s | ~7 hours |
| USB 3.0 SSD | ~450 MB/s | ~2.5 hours |
| Internal NVMe (Apple Silicon) | ~5 GB/s | ~12 minutes |

Concurrency (parallel file reads) helps on SSDs and NVMe by keeping the drive's I/O queue saturated. It can hurt on HDDs by forcing unnecessary seeks, so leave it at 1 for spinning drives.

## Requirements

- macOS 26.5+ (menu-bar app)
- macOS 13+ (CLI)
- Swift 6

## Dependencies

- [SwiftBlake3](https://github.com/thecoolwinter/SwiftBlake3) — BLAKE3 hashing
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing

## Building

```bash
# CLI
swift build -c release
.build/release/sentinel --help

# App
open "Archive Integrity/Archive Integrity.xcodeproj"
```

## Manifest format

Manifests are plain text, one entry per line:

```
<64-char blake3 hex>  ./relative/path/to/file
```

Two spaces separate the hash from the path (b3sum convention). Paths are relative to the archive root, NFC-normalized, and always start with `./`. The file is UTF-8 with Unix line endings.

Manifests are stored in `~/Library/Application Support/Archive Integrity/manifests/` by the app, or next to the archive directory when created by the CLI.
