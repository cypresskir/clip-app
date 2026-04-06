# Clip — Project Prompt

Build a native macOS SwiftUI video downloader app called **Clip** that uses yt-dlp as its download engine. The app should feel minimal, calm, and native — no Electron, no web views.

## Core Requirements

### Tech Stack
- **SwiftUI** App lifecycle with `@NSApplicationDelegateAdaptor` for AppKit integration
- **macOS 14.0+**, Swift 5.9
- **xcodegen** (`project.yml`) for project generation — no manual Xcode project editing
- **yt-dlp** for video metadata fetching and downloading
- **ffmpeg/ffprobe** for compression and duration probing

### Architecture
```
Clip/
  ClipApp.swift              — @main entry, AppDelegate for menu bar + clipboard monitor
  ClipTheme.swift            — Brand color palette + custom button style
  ClipConstants.swift        — App-wide magic numbers (poll intervals, limits, defaults)
  Models/
    Platform.swift           — Enum: youtube/x/instagram/tiktok/unknown with icons + colors
    DownloadItem.swift       — Observable download model: status, format, resolution, clip range
    DownloadHistory.swift    — Codable history store persisted to JSON file
    VideoMetadata.swift      — yt-dlp JSON response model + OutputFormat/OutputResolution enums
  ViewModels/
    MainViewModel.swift      — URL input, validation, analysis orchestration
    DownloadViewModel.swift  — Download queue, concurrent limit, compression, history
  Views/
    ContentView.swift        — Main layout: URL input -> preview -> format picker -> downloads
    URLInputView.swift       — URL text field + Paste button + Analyze button
    VideoPreviewView.swift   — Thumbnail + title + platform badge + duration + date
    FormatPickerView.swift   — Format (MP4/MOV/WebM/MP3), resolution, target size, clip toggle
    ClipRangeView.swift      — Draggable timecode range bar with start/end handles + time inputs
    DownloadSectionView.swift — Folder-tab switcher (Downloads/History) with context actions
    DownloadListView.swift   — Active downloads with progress, cancel, retry
    HistoryView.swift        — Past downloads with metadata, swipe-to-delete
    SaveLocationView.swift   — Download directory picker
    MenuBarView.swift        — NSPopover menu bar interface for quick downloads
    StatusBarController.swift — NSStatusItem with app icon + circular progress overlay
    SettingsView.swift       — Preferences: concurrent downloads, menu bar, dock visibility
  Services/
    YTDLPService.swift       — Actor wrapping yt-dlp: metadata fetch + download with progress parsing
    FFmpegService.swift      — Static methods: compress to target size, probe duration
    URLDetector.swift        — URL validation, platform detection, normalization (dedup)
    FileSizeFormatter.swift  — Human-readable file size strings
    ClipboardMonitor.swift   — Polls pasteboard for video URLs, suggests in menu bar
```

### Features to Implement

**1. URL Analysis**
- Paste or type a video URL; auto-detect platform (YouTube, X, Instagram, TikTok)
- Show platform brand icon (real logos from asset catalog for YouTube/X/TikTok/Instagram, SF Symbol fallback for unknown)
- Fetch metadata via `yt-dlp --dump-json --no-download`
- Display thumbnail, title, duration, upload date

**2. Format & Quality Selection**
- Format: MP4 (H.264+AAC), MOV, WebM (VP9+Opus), MP3 (audio only)
- Resolution: 4K / 1080p / 720p / 480p / 360p — disable unavailable ones with tooltip
- Target Size: Original or Custom (MB) — shows compression warning with estimated bitrate
- Radio-button style selection with accent-colored highlight on selected items

**3. Clip Range (Partial Download)**
- Checkbox: "Download clip" with scissors icon, appears below Target Size
- Visual timecode bar with two draggable handles (accent color for start, rosewood for end)
- Highlighted region between handles showing selected portion
- Manual time inputs (Start/End) supporting `MM:SS` or `H:MM:SS` format
- Duration display between the inputs
- Uses yt-dlp's `--download-sections "*START-END"` with `--force-keyframes-at-cuts`
- Each clip gets a unique filename: `title_720p_clip_1.30-2.45.mp4`
- Estimated file size scales proportionally to clip duration
- Multiple clips from the same video: clicking Download on an already-downloading item clones it with current settings as a new independent download

**4. Download Queue**
- Concurrent download limit (default 3, configurable in Settings)
- Queue system: excess downloads go to `.queued` status, auto-start when slot opens
- Progress parsing from yt-dlp stdout: percentage, speed, ETA
- Cancel button sets `isCancelled` flag before terminating process — prevents race condition where termination handler overwrites "Cancelled" with "exit code 15"
- Retry clones the item for a fresh attempt
- Duplicate URL detection via normalized URL comparison

**5. Compression**
- When Target Size is set and downloaded file exceeds it, auto-compress via ffmpeg two-pass encoding
- Compression progress shown with rosewood-colored progress bar
- Falls back to original file if compression fails

**6. Downloads/History Section**
- Custom folder-tab UI (not system TabView) using `UnevenRoundedRectangle` for top-only rounded corners
- Downloads tab: active/completed downloads with thumbnails, progress, cancel/retry
- History tab: past downloads persisted to JSON, swipe-to-delete, "Clear All" with confirmation dialog
- Clicking any row loads that video's URL back into the analyzer for re-downloading with different settings
- Selected row gets subtle accent-colored background highlight

**7. Menu Bar**
- `NSStatusItem` with app icon (22x22) + circular progress overlay during downloads
- `NSPopover` with clipboard URL suggestion, quick download, active download status
- Clipboard monitor polls pasteboard every 1s for video URLs

**8. Settings**
- Download directory (with folder picker)
- Max concurrent downloads
- Show/hide menu bar icon
- Show/hide dock icon

### Color Palette
Calm, muted tones with light/dark mode variants in asset catalog color sets:

| Name | Role | Light | Dark |
|------|------|-------|------|
| ClipAccent (AccentColor) | Buttons, selection, active states | Dusk Blue #355070 | #6181A7 |
| ClipLavender | Secondary highlights, Instagram | Dusty Lavender #6D597A | #907C9E |
| ClipRosewood | Compression, warnings | Rosewood #B56576 | #C77D8D |
| ClipCoral | Errors, failed states, YouTube | Light Coral #CC565B | #E56B6F |
| ClipBronze | Warm accents, retry | Light Bronze #D0996F | #EA AC8B |
| ClipSuccess | Complete states | Muted Teal #4C947A | #66B598 |

Use a custom `ClipProminentButtonStyle` instead of `.borderedProminent` — the system style has a macOS SwiftUI rendering bug where buttons disappear when the window is occluded by other windows.

### Key Technical Details
- `yt-dlp`, `ffmpeg`, `ffprobe` binaries should be bundled in `Resources/bin/` and copied+signed via `postCompileScripts` in project.yml
- Binary lookup: check `Bundle.main.path(forResource:ofType:)` first, fall back to PATH
- Entitlements needed: `allow-unsigned-executable-memory`, `disable-library-validation`, `network.client`
- URL normalization: strip tracking params (`utm_*`, `si`, `fbclid`), expand `youtu.be` to `youtube.com/watch?v=`, lowercase host, remove `www.`
- History migration safety: use `decodeIfPresent` with version field
- Use `os.Logger` for structured logging throughout services
- Window: `minWidth: 500, minHeight: 500`, content section uses `.fixedSize(horizontal: false, vertical: true)` on ScrollView so it doesn't expand into empty space; downloads section fills remaining space with `.frame(minHeight: 180, maxHeight: .infinity)`
- Instagram downloads: auto-detect browser cookies (Arc, Chrome, Safari, Firefox, etc.) for authentication

### Platform Brand Icons
Add real brand logos as image assets (template rendering: original):
- `PlatformYouTube` — red play button
- `PlatformX` — X/Twitter logo
- `PlatformTikTok` — TikTok logo
- `PlatformInstagram` — Instagram gradient camera

### Build & Run
```bash
# Prerequisites
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project Clip.xcodeproj -scheme Clip -configuration Debug build

# Deploy
rm -rf /Applications/Clip.app
cp -R build/Build/Products/Debug/Clip.app /Applications/Clip.app
open /Applications/Clip.app
```
