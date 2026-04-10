# Clip — Full Project Recreation Prompt

Build a native macOS SwiftUI video downloader app called **Clip** that wraps yt-dlp. The app should feel minimal, calm, and native — no Electron, no web views. macOS 14.0+, Swift 5.9, SwiftUI App lifecycle.

---

## Architecture Overview

```
Clip/
  ClipApp.swift              — @main entry, NSApplicationDelegateAdaptor for menu bar + clipboard
  ClipTheme.swift            — Brand color palette + custom button style
  ClipConstants.swift        — App-wide magic numbers
  Models/
    Platform.swift           — Enum: youtube/x/instagram/tiktok/reddit/unknown
    DownloadItem.swift       — Observable download model with status state machine
    DownloadHistory.swift    — Codable history store persisted to JSON
    VideoMetadata.swift      — yt-dlp JSON model + OutputFormat/OutputResolution enums
  ViewModels/
    MainViewModel.swift      — URL input, validation, metadata fetch orchestration
    DownloadViewModel.swift  — Download queue, concurrent limit, compression, notifications
  Views/
    ContentView.swift        — Main layout with drag-drop + resizable split
    URLInputView.swift       — URL field + Paste + Analyze buttons
    VideoPreviewView.swift   — Thumbnail + title + platform badge + duration
    FormatPickerView.swift   — Format/resolution/target size/clip toggle
    ClipRangeView.swift      — Draggable timecode range bar
    DownloadSectionView.swift — Folder-tab switcher (Downloads/History)
    DownloadListView.swift   — Active downloads with progress bars
    HistoryView.swift        — Past downloads, swipe-to-delete
    SaveLocationView.swift   — Download directory picker
    MenuBarView.swift        — NSPopover menu bar interface
    StatusBarController.swift — NSStatusItem with progress overlay
    UpdateBannerView.swift   — In-app update notification banner
    SettingsView.swift       — Preferences window
  Services/
    YTDLPService.swift       — Actor wrapping yt-dlp process spawning
    FFmpegService.swift      — Two-pass compression + duration probing
    URLDetector.swift        — URL validation, platform detection, normalization
    FileSizeFormatter.swift  — Human-readable byte formatting
    ClipboardMonitor.swift   — Polls pasteboard for video URLs
    RedditResolver.swift     — Resolves Reddit posts to direct video URLs
    BinaryDiagnostics.swift  — Runtime binary availability checks
    UpdateService.swift      — Self-update via GitHub Releases
  Resources/
    bin/                     — Bundled yt-dlp, ffmpeg, ffprobe (universal arm64+x86_64)
  Assets.xcassets/           — Colors, platform icons, app icon
```

---

## Project Configuration (xcodegen)

Use `xcodegen` with a `project.yml`:

```yaml
name: Clip
options:
  bundleIdPrefix: com.clip
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
targets:
  Clip:
    type: application
    platform: macOS
    sources:
      - path: Clip
        excludes:
          - Resources/bin
    postCompileScripts:
      - script: |
          RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources"
          for bin in yt-dlp ffmpeg ffprobe; do
            cp "${PROJECT_DIR}/Clip/Resources/bin/${bin}" "${RESOURCES_DIR}/${bin}"
            chmod +x "${RESOURCES_DIR}/${bin}"
            codesign --force --sign - --timestamp=none "${RESOURCES_DIR}/${bin}"
          done
        name: Bundle and Sign Binaries
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.clip.app
        MARKETING_VERSION: "1.1.2"
        CURRENT_PROJECT_VERSION: "1"
        INFOPLIST_KEY_NSMainNibFile: ""
        INFOPLIST_KEY_NSPrincipalClass: NSApplication
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSApplicationCategoryType: "public.app-category.utilities"
        INFOPLIST_KEY_CFBundleDisplayName: Clip
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGN_ENTITLEMENTS: Clip/Clip.entitlements
```

Entitlements (`Clip.entitlements`):
- `com.apple.security.cs.allow-unsigned-executable-memory` — required for yt-dlp/ffmpeg
- `com.apple.security.cs.disable-library-validation` — required for bundled binaries
- `com.apple.security.network.client` — network access

---

## Color Palette

All colors defined as named color sets in the asset catalog with light/dark variants:

| Name | Role | Light | Dark |
|------|------|-------|------|
| ClipAccent (AccentColor) | Buttons, selection, active states | Dusk Blue `#355070` | `#6181A7` |
| ClipLavender | Secondary highlights, Instagram | Dusty Lavender `#6D597A` | `#907C9E` |
| ClipRosewood | Compression, warnings, clip end handle | Rosewood `#B56576` | `#C77D8D` |
| ClipCoral | Errors, failed states, YouTube | Light Coral `#CC565B` | `#E56B6F` |
| ClipBronze | Warm accents, retry | Light Bronze `#D0996F` | `#EAAC8B` |
| ClipSuccess | Complete states | Muted Teal `#4C947A` | `#66B598` |

**ClipTheme.swift** — Exposes these as static `Color` properties. Also defines `ClipProminentButtonStyle` (custom button style with white text on accent background, opacity-based pressed/disabled states). Do NOT use `.borderedProminent` — it has a macOS SwiftUI rendering bug where buttons vanish when occluded.

**ClipConstants.swift** — Named constants:
- `clipboardPollInterval: 1.0` (seconds)
- `historyMaxEntries: 200`
- `menuBarMaxItems: 8`
- `fileRecencySeconds: 30`
- `defaultMaxConcurrentDownloads: 3`
- `defaultAudioBitrateKbps: 128`

---

## Models

### Platform.swift
Enum with cases: `.youtube`, `.x`, `.instagram`, `.tiktok`, `.reddit`, `.unknown`. Each case provides:
- `displayName: String`
- `iconName: String` (SF Symbol fallback)
- `assetIconName: String?` (custom asset catalog image, e.g. "PlatformYouTube", "PlatformReddit")
- `color: Color` (mapped from ClipTheme: YouTube=coral, X=accent, Instagram=lavender, TikTok=accent, Reddit=rosewood, unknown=accent)

Include a `PlatformIcon` SwiftUI view that renders the asset image (template rendering: original) or falls back to the SF Symbol with color.

### VideoMetadata.swift
Codable struct decoded from `yt-dlp --dump-json`:
- `var title: String` — mutable for Reddit override
- `var thumbnail: String?` — mutable for Reddit override
- `var duration: Double?` — mutable for Reddit override
- `uploadDate: String?` (CodingKey: "upload_date")
- `formats: [VideoFormat]`
- Computed: `formattedDuration` (HH:MM:SS), `formattedUploadDate` (e.g. "Mar 15, 2024")

**VideoFormat** (Codable): `formatId`, `ext`, `resolution`, `filesize: Int64?`, `filesizeApprox: Int64?`, `tbr: Double?`, `vcodec`, `acodec`, `height: Int?`, `width: Int?`, `formatNote`. Computed: `hasVideo` (vcodec != "none" and not nil), `hasAudio`, `estimatedSize` (filesize ?? filesizeApprox).

**OutputFormat** enum (CaseIterable): `.mp4`, `.mov`, `.webm`, `.mp3`. Properties: `isAudioOnly`, `fileExtension`, `subtitle` (codec description).

**OutputResolution** enum (Int rawValue, CaseIterable): `.p2160(2160)`, `.p1080(1080)`, `.p720(720)`, `.p480(480)`, `.p360(360)`. Property: `displayName` ("4K", "1080p", etc.).

### DownloadItem.swift
`@MainActor class DownloadItem: ObservableObject, Identifiable`

Key properties:
- `let id: UUID`, `let url: String`, `let platform: Platform`
- `var resolvedURL: String?` — for Reddit (resolved direct video URL)
- `var downloadURL: String` — computed: `resolvedURL ?? url`
- `@Published var status: DownloadStatus`
- `@Published var metadata: VideoMetadata?`
- `@Published var selectedFormat: OutputFormat`
- `@Published var selectedResolution: OutputResolution`
- `@Published var targetSize: TargetFileSize`
- `@Published var estimatedFileSize: Int64?`
- `@Published var thumbnailData: Data?`
- `@Published var clipEnabled: Bool`
- `@Published var clipRange: ClipRange`
- `var isCancelled: Bool`, `var process: Process?`

**DownloadStatus** enum:
- `.analyzing`, `.ready`, `.queued`
- `.downloading(progress: Double, speed: String, eta: String)`
- `.compressing(progress: Double)`
- `.complete(filePath: String)`
- `.failed(error: String)`
- Computed: `isActive` (true for analyzing/downloading/queued/compressing), `statusText` (human-readable)
- Conformance to `Equatable` (for `.queued` comparison in queue logic)

**TargetFileSize** enum: `.none`, `.custom(mb: Int)`. Computed: `bytes: Int64?`.

**ClipRange** struct: `start: Double`, `end: Double` (seconds). Computed: `duration`. Methods: `formatTime()` (MM:SS or H:MM:SS for display), `formatTimePrecise()` (HH:MM:SS.ss for yt-dlp args).

Key methods:
- `availableResolutions` — filters metadata formats by height, returns sorted unique resolutions
- `bestFormatId(for:resolution:)` — selects best format ID, prioritizing codecs: AV1 > VP9 > AVC
- `estimateFileSize()` — calculates from tbr: `(tbr * 1000 * duration) / 8`
- `updateEstimatedSize()` — recalculates when format/resolution/clip changes
- `cloneForRedownload()` — creates new DownloadItem with same settings but fresh ID and `.ready` status; copies `resolvedURL`

### DownloadHistory.swift
**DownloadHistoryEntry** (Codable, Identifiable): `id`, `url`, `title`, `platform` (String), `filePath`, `fileSize: Int64?`, `resolution: Int?`, `format: String?`, `completedAt: Date`, `version: Int`. Custom decoder with `decodeIfPresent` fallbacks for migration safety. Initializer from DownloadItem + filePath.

**DownloadHistoryStore** (`@MainActor, ObservableObject`): Persists to `~/Library/Application Support/Clip/history.json`. Max `ClipConstants.historyMaxEntries` entries. Methods: `add()`, `clear()`, `remove(atOffsets:)`, `load()`, `save()`.

---

## Services

### YTDLPService.swift
Declared as `actor`. Core service for all yt-dlp interactions.

**Binary Resolution** (critical — this was the hardest bug to solve):
- `static let bundledResourceDir: String` — Uses `Bundle.main.bundlePath + "/Contents/Resources"` (NOT `Bundle.main.path(forResource:ofType:)` which returns nil for extensionless binaries). Falls back to `Bundle.main.resourceURL?.path`.
- `static func resolveBinary(_ name: String) -> String` — Checks bundled dir first, then runs `/usr/bin/which` to find system installation.
- `static let enrichedEnvironment: [String: String]` — Copies `ProcessInfo.processInfo.environment`, prepends bundled resource dir + homebrew paths (`/opt/homebrew/bin`, `/usr/local/bin`) to PATH.
- `func ensureExecutable() throws` — chmod +x and ad-hoc codesign each binary before use.

**Metadata Fetch**: `func fetchMetadata(url:) async throws -> VideoMetadata`
- Runs: `yt-dlp --dump-json --no-download --no-warnings --flat-playlist <url>`
- Sets `--ffmpeg-location` to bundled resource dir
- Uses `enrichedEnvironment`
- For Instagram URLs: tries with browser cookies first (`--cookies-from-browser <browser>`), falls back to no cookies
- Cookie browser detection: checks Arc, Chrome, Safari, Firefox, Brave, Edge, Opera cookie DBs

**Download**: `nonisolated func startDownload(url:, formatId:, outputFormat:, resolution:, clipRange:, titleOverride:, outputDirectory:, onProgress:, onComplete:) throws -> Process`
- Format selection:
  - MP3: `-x --audio-format mp3 --audio-quality 0`
  - Video with formatId: `-f {formatId}+bestaudio/best`
  - Video without formatId: `-f bestvideo[height<={res}]+bestaudio/best[height<={res}]/best`
  - Adds `--merge-output-format {ext}` for non-MP3
- Clipping: `--download-sections "*{start}-{end}" --force-keyframes-at-cuts`
- Output template: If `titleOverride` provided (Reddit), sanitize title (replace `/`, `:`, `"`) and use directly; otherwise use yt-dlp's `%(title).100s` template. Always appends `_{resolution}p` and clip suffix.
- Always passes: `--no-overwrites`, `--newline`, `--ffmpeg-location`, `--no-mtime`
- Progress parsing via stdout Pipe readabilityHandler:
  - Regex extracts percentage from `[download] XX.X%`, speed from `at XXX/s`, ETA from `ETA HH:MM`
  - Destination from `Destination:` or `Merging formats into "path"` lines
- Stderr monitoring: reads ERROR lines for failure reporting
- Termination handler: calls `onComplete` with file path or error, cleans up `.part`/`.ytdl` temp files on failure
- **OutputPathHolder**: `@unchecked Sendable` class with `NSLock` wrapping the `path: String?` property (written from multiple readabilityHandlers)

**Error Mapping**: `static func friendlyError(_ message: String) -> String` — Maps common yt-dlp errors to user-friendly messages (private video, geo-blocked, age-restricted, not found, network error, etc.)

### FFmpegService.swift
Static methods for video compression.

**Binary Discovery**: `findBinary() -> String?` — Checks bundled resources, homebrew paths, then `/usr/bin/which`.

**Compression**: `compress(inputPath:, targetBytes:, audioBitrateKbps:, onProgress:, onComplete:) -> Process?`
- Probes duration via ffprobe (`-v quiet -print_format json -show_format`)
- Guards `duration > 0.1` to prevent division by zero
- Calculates video bitrate: `((targetBytes * 8) / 1000 - audioBitrate * duration) / duration` kbps, minimum 100
- Two-pass H.264 encoding: pass 1 with `-an` (no audio), pass 2 with AAC audio
- Progress parsed from ffmpeg's `-progress pipe:1` output (`out_time_us=` lines)
- Atomic file replacement via `FileManager.replaceItemAt(_:withItemAt:)`
- Pass log files in temp directory, cleaned up after

**Error Handling**: Falls back gracefully — if compression fails, the original file is kept.

### RedditResolver.swift
Enum with static methods. Resolves Reddit URLs because yt-dlp's Reddit extractor is broken (Reddit killed public .json API).

**URL Detection**: `isRedditURL(_ urlString: String) -> Bool` — Checks for reddit.com or redd.it domains.

**Post ID Extraction**: `extractPostID(from:) -> String?` — Regex: `/comments/([a-zA-Z0-9]+)/`; for redd.it short links, follows redirect.

**Resolution**: `resolve(_ urlString: String) async throws -> ResolvedRedditVideo`
- Fetches `https://api.reddit.com/comments/{postID}` with User-Agent `macos:com.clip.app:v1.0 (by /u/clip-app)`
- Parses JSON response to extract post data
- For Reddit-hosted videos: extracts `media.reddit_video.hls_url` (preferred) or `fallback_url`
- For external videos (YouTube, Streamable): extracts `url_overridden_by_dest`
- Returns `ResolvedRedditVideo` with: `videoURL`, `title`, `duration: Double?`, `thumbnailURL: String?`, `isRedditHosted: Bool`

**Error Types**: `invalidURL`, `apiFailed(statusCode)`, `parseFailed`, `noVideo`

### URLDetector.swift
**Platform Detection**: `detectPlatform(from:) -> Platform` — Substring matching on lowercased URL. TikTok uses regex to require `/video/`, `/@user/`, `/t/`, or `vm.tiktok.com` (avoids matching explore/hashtag pages). Reddit checks for `reddit.com/` or `redd.it/`.

**Validation**: `isValidURL(_:) -> Bool` — Checks URL has http/https scheme and a host.

**Normalization**: `normalizeURL(_:) -> String` — Strips tracking params (`utm_*`, `si`, `feature`, `ref`, `fbclid`, `igshid`, `t`, `s`), expands `youtu.be/X` to `youtube.com/watch?v=X`, lowercases host, removes `www.` prefix and trailing slashes. Used for duplicate detection.

### ClipboardMonitor.swift
`@MainActor class ClipboardMonitor: ObservableObject`. Polls `NSPasteboard.general` every `ClipConstants.clipboardPollInterval` seconds. Publishes `detectedURL: String?` when a valid video URL is found. Tracks `lastChangeCount` to avoid re-detecting the same content. Methods: `start()`, `stop()`, `dismiss()`.

### UpdateService.swift
`@MainActor class UpdateService: ObservableObject`. Self-update via GitHub Releases.

- `githubRepo = "cypresskir/clip-app"` (change to your repo)
- `static var currentVersion: String` from `CFBundleShortVersionString`
- `checkForUpdate() async` — Fetches latest release from GitHub API, compares semver
- `downloadAndInstall() async` — Downloads .zip asset via `URLSessionDownloadTask` with progress delegate, extracts with `ditto`, fixes binary permissions (chmod +x + ad-hoc codesign for yt-dlp/ffmpeg/ffprobe), removes quarantine with `xattr -cr`, backs up current app, replaces, relaunches via `open -n`
- `skipVersion()` — Saves skipped version to UserDefaults
- `isNewer(_ remote:, than local:) -> Bool` — Component-by-component semver comparison

**Release** model (Codable): `tagName`, `name`, `body`, `assets: [Asset]`, `htmlUrl`. Asset: `name`, `browserDownloadUrl`, `size`.

### BinaryDiagnostics.swift
**DiagEntry** struct: `id`, `label`, `value`, `ok: Bool`.

**BinaryDiagnostics** enum with `static func run() -> [DiagEntry]` — Checks each binary (yt-dlp, ffmpeg, ffprobe): existence at bundled path, executable permission, runs with `--version`/`-version`, tests yt-dlp's ffmpeg discovery via `--verbose`. Returns diagnostic entries for display.

**BinaryDiagnosticsModel** (`@MainActor, ObservableObject`): `@Published entries`, `@Published isRunning`. Calls `run()` on `Task.detached` to avoid blocking main thread.

### FileSizeFormatter.swift
Single method: `format(_ bytes: Int64) -> String` using `ByteCountFormatter`.

---

## Views

### ContentView.swift
Main window layout. VStack containing:
1. `UpdateBannerView` (conditional)
2. `URLInputView` (with `MainViewModel`)
3. Divider
4. ScrollView: `VideoPreviewView` + `FormatPickerView` (conditional on metadata)
5. Draggable resize handle (changes cursor to `.resizeUpDown`)
6. `DownloadSectionView` (fills remaining space, `minHeight: 180, maxHeight: .infinity`)

Supports drag-and-drop of URLs (`.onDrop` for `.url` and `.plainText` UTTypes). Visual overlay on drag-over. Content scroll uses `.fixedSize(horizontal: false, vertical: true)` to prevent expanding into empty space.

Download button below the format picker, disabled until metadata is loaded.

### URLInputView.swift
HStack: `PlatformIcon` | `TextField` (placeholder "Paste video URL...") | Paste button (Cmd+Shift+V, reads from NSPasteboard) | Analyze button (Cmd+Return). Error message row below with exclamation icon. The TextField `.onSubmit` triggers analysis.

### VideoPreviewView.swift
HStack: Thumbnail (180pt wide, 16:9 aspect, rounded corners) | VStack metadata (title bold, platform capsule badge with icon+name, duration, upload date). Thumbnail rendered from `NSImage(data:)` or placeholder with spinner.

### FormatPickerView.swift
Organized in sections:
- **Format**: Row of 4 `FormatButton` views (checkmark circle + title + subtitle)
- **Resolution**: Row of 5 buttons, disabled if resolution not available in metadata
- **Target Size**: "Original" vs "Custom" toggle, custom shows MB text field with compression info
- **Estimated size** display with "Compression required" warning when target < estimated
- **Clip range**: Checkbox toggle with scissors icon, expanding to `ClipRangeView`

Radio-button-style selection: selected items get accent-colored background.

### ClipRangeView.swift
GeometryReader-based timeline:
- Gray background track
- Accent-colored highlighted region between handles
- Two draggable handles (12px wide): start (accent color), end (rosewood color)
- Time labels at start and end of track
- Below: Start time input | duration display | End time input

**TimeInput** subview parses "1:23" (MM:SS), "1:23:45" (H:MM:SS), or raw seconds. DragGesture clamped to valid range.

### DownloadSectionView.swift
Custom folder-tab UI (NOT system TabView). Two `FolderTab` buttons with `UnevenRoundedRectangle` (top corners only). Active tab gets filled background. Context buttons on the right: "Clear completed" for downloads tab, "Clear All" with `confirmationDialog` for history tab.

### DownloadListView.swift
LazyVStack of `DownloadRowView`. Each row: 48x27 thumbnail | title (truncated) | platform icon | status indicator | action button. Status varies:
- Downloading: accent-colored progress bar + speed + ETA
- Compressing: rosewood-colored progress bar
- Complete: green checkmark + file size + reveal-in-Finder button
- Failed: red error text + retry button
- Queued: "Queued" text

Clicking a completed/failed row loads its URL back into the analyzer. Cancel button on active downloads.

### HistoryView.swift
List (plain style) with `HistoryRowView` items. Each row: title | metadata caption (platform, resolution, format, file size) | date/time | Reveal button. Swipe-to-delete. Selected row (matching current URL) gets subtle highlight.

### MenuBarView.swift
NSPopover content (width: 340pt):
1. Clipboard suggestion banner (if URL detected and input empty) — tap to fill
2. URL text field + quick download button (arrow.down.circle.fill)
3. Processing spinner or error message
4. Active download list (max `ClipConstants.menuBarMaxItems` items) with compact rows
5. Footer: "Open Clip" button + "Quit" button

`MenuBarViewModel` (nested): `url`, `detectedPlatform`, `isProcessing`, `errorMessage`. Quick download calls `DownloadViewModel.prepareAndStartDownload()` which handles metadata fetch + default settings + queue in one call.

### StatusBarController.swift
`NSStatusItem` with `squareLength`. Button image: app icon resized to 22x22 (from `NSApp.applicationIconImage`). During active downloads, overlays a circular progress indicator (gray background circle + accent-colored arc based on `overallProgress`). Uses Combine (`objectWillChange` sink) to observe DownloadViewModel.

On deinit: removes status item from `NSStatusBar.system`.

Popover: `.transient` behavior, content is `MenuBarView` in `NSHostingController`.

### UpdateBannerView.swift
Conditional banner at top of window:
- **Update available**: Download icon + "Version X.X.X available" + release notes preview + Skip/Update buttons. During download: progress bar replaces buttons.
- **Error**: Warning icon + error message + Dismiss button.
- Accent-colored background with rounded corners.

### SettingsView.swift
Settings window (450x420). Sections:
- **Appearance**: Toggle menu bar icon, toggle dock icon (`NSApp.setActivationPolicy`), toggle open at login (`SMAppService.mainApp`)
- **Downloads**: Save location picker (`SaveLocationView`), preferred format picker, preferred resolution picker, max concurrent downloads (Stepper 1-10)
- **About**: App version display, check for updates button, GitHub link
- **Advanced**: Collapsible diagnostics section with chevron toggle. Lists `BinaryDiagnosticsModel` entries with green/red status indicators.

### SaveLocationView.swift
HStack: folder icon | path (abbreviated with `~` replacing home dir, truncated middle) | "Change..." button that opens `NSOpenPanel` for directory selection.

---

## App Lifecycle (ClipApp.swift)

```swift
@main
struct ClipApp: App {
    @NSApplicationDelegateAdaptor(ClipAppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ClipAppDelegate.downloadVM)
                .frame(minWidth: 500, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 600, height: 700)

        Settings {
            SettingsView(updateService: ClipAppDelegate.updateService)
        }
    }
}
```

**ClipAppDelegate** (`NSObject, NSApplicationDelegate`):
- Static properties (to prevent SwiftUI re-instantiation duplicates): `downloadVM`, `clipboardMonitor`, `updateService`, `statusBarController`, `didFinishLaunching`
- `applicationDidFinishLaunching`: Guard against duplicate calls. Read UserDefaults for `showInMenuBar` (default true) and `showInDock` (default true). Start clipboard monitor. Check for updates after 3-second delay.
- `applicationWillTerminate`: Stop clipboard monitor, terminate all active downloads.
- `enableMenuBar()`/`disableMenuBar()`: Create/destroy `StatusBarController`.

---

## Key Implementation Patterns

1. **Binary bundling**: yt-dlp, ffmpeg, ffprobe are universal (arm64+x86_64) binaries in `Resources/bin/`. The `postCompileScripts` copies them to the built product and ad-hoc codesigns them. At runtime, `ensureExecutable()` re-applies chmod+codesign before each use.

2. **Binary path resolution**: NEVER use `Bundle.main.path(forResource:ofType:)` for extensionless binaries — it returns nil on macOS. Always use `Bundle.main.bundlePath + "/Contents/Resources"` directly.

3. **Process environment**: Prepend bundled resource dir to PATH so yt-dlp can find ffmpeg. Also add `/opt/homebrew/bin` and `/usr/local/bin`.

4. **Reddit workaround**: yt-dlp's Reddit extractor is broken. RedditResolver fetches post data from `api.reddit.com` (still works with proper User-Agent), extracts HLS video URL, and overrides yt-dlp metadata with Reddit post title/thumbnail/duration.

5. **Instagram cookies**: Auto-detect browser cookie databases for Instagram authentication. Try Arc (Chromium variant), Chrome, Safari, Firefox, Brave, Edge, Opera in order.

6. **Cancel safety**: Set `isCancelled` flag on the DownloadItem BEFORE terminating the Process. The termination handler checks this flag to avoid overwriting "Cancelled" status with "exit code 15".

7. **Queue management**: When a download completes, fails, or is cancelled, call `startNextQueued()` to dequeue the next waiting item. Guard against exceeding `maxConcurrent`.

8. **Shared download logic**: `DownloadViewModel.prepareAndStartDownload(url:platform:)` is used by both the menu bar quick-download and could be used by any entry point. It handles metadata fetch, Reddit resolution, default settings, and queue insertion in one method.

9. **Thread safety**: `DownloadItem`, `DownloadViewModel`, `ClipboardMonitor`, `UpdateService` are `@MainActor`. `YTDLPService` is an `actor`. `OutputPathHolder` uses `NSLock` for thread-safe path updates from Process pipe handlers.

10. **Duplicate detection**: Before starting a download, normalize the URL (strip tracking params, expand short links, lowercase) and check against active downloads.

11. **History migration**: `DownloadHistoryEntry` uses a `version` field and `decodeIfPresent` in its decoder so adding new fields doesn't break old persisted data.

12. **Compression pipeline**: Download completes -> check if `targetSize` is set and file exceeds it -> if ffmpeg available, two-pass H.264 compression -> atomic file replacement -> if compression fails, keep original.

13. **Partial download cleanup**: On download failure, scan output directory for `.part` and `.ytdl` temp files matching the download and remove them.

---

## Platform Brand Icons

Add as image assets (template rendering: Original):
- `PlatformYouTube` — red play button logo
- `PlatformX` — X/Twitter logo
- `PlatformTikTok` — TikTok logo
- `PlatformInstagram` — Instagram gradient camera logo
- `PlatformReddit` — Reddit Snoo logo

SF Symbol fallbacks: YouTube = `play.rectangle.fill`, X = `bubble.left.and.text.bubble.right`, Instagram = `camera.fill`, TikTok = `music.note`, Reddit = `bubble.left.and.text.bubble.right.fill`, Unknown = `globe`.

---

## Build & Deploy

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Clip.xcodeproj -scheme Clip -configuration Debug build
rm -rf /Applications/Clip.app
cp -R build/Build/Products/Debug/Clip.app /Applications/Clip.app
xattr -cr /Applications/Clip.app
open /Applications/Clip.app
```

**Important**: Always `rm -rf` before `cp -R` — otherwise cp nests the .app bundle inside the existing one.
