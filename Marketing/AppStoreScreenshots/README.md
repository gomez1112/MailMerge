# Mergeform marketing media

The listing uses five 2880×1800 opaque PNGs and a 20-second 1920×1080 MP4 with silent audio. The window footage uses fictional customer data. The SDK's generic demo feedback board is exercised by the capture walkthrough but excluded from the listing because its sample requests describe a different app.

`MarketingCaptureTests` is an opt-in Debug fixture. It uses an in-memory SwiftData store, an isolated defaults suite, local StoreKit test purchases, and a temporary output folder. Ordinary tests skip it. Release builds exclude the capture presentation state and demo board switch.

From the project directory, compile the standalone tools:

```sh
xcrun swiftc -swift-version 6 Marketing/AppStoreScreenshots/window-list.swift -o /tmp/mergeform-window-list
xcrun swiftc -swift-version 6 Marketing/AppStoreScreenshots/compose.swift -o /tmp/mergeform-compose
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos26.2 Marketing/AppStoreScreenshots/encode-frames.swift -o /tmp/mergeform-encode-frames
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos26.2 Marketing/AppStoreScreenshots/export-preview.swift -o /tmp/mergeform-export-preview
```

Start the screenshot helper, then run the opt-in walkthrough alongside it:

```sh
python3 Marketing/AppStoreScreenshots/capture-windows.py /tmp/mergeform-window-list Marketing/AppStoreScreenshots/Captures
```

```sh
TEST_RUNNER_MERGEFORM_MARKETING_CAPTURES=1 bitrig test -only-testing:MergeformTests/MarketingCaptureTests
```

The helper captures only the harness's named windows, never the whole desktop. macOS Screen Recording permission is needed. The fixture's window titles identify each stage after its layout has settled.

Compose the five listing images:

```sh
/tmp/mergeform-compose Marketing/AppStoreScreenshots/slides.json Marketing/AppStoreScreenshots/Captures appStoreConnect/appStoreVersion/macOS/localizations/en-US/placements/app-screenshot/mac-profile/assets
```

For the video, run `record-frames.py` alongside another walkthrough. It records full-window snapshots for 25 seconds starting at Field Mapping, with real capture timestamps. This avoids macOS window video recording clipping windows that are wider than the display. No microphone or system audio is recorded.

```sh
python3 Marketing/AppStoreScreenshots/record-frames.py /tmp/mergeform-window-list /tmp/mergeform-preview-frames
/tmp/mergeform-encode-frames /tmp/mergeform-preview-frames /tmp/mergeform-workflow.mov
/tmp/mergeform-export-preview /tmp/mergeform-workflow.mov appStoreConnect/appStoreVersion/macOS/localizations/en-US/placements/app-preview/mac-profile/assets/01-workflow.mp4 20
```

The encoder fits the entire window into 1920×1080 without cropping and produces a 30 fps H.264 video, holding each captured frame until the next snapshot. The exporter trims it to the 20-second mapping → data → preview walkthrough and adds the required silent audio track. Both tools use released macOS 26 APIs and reject incomplete or overly short footage.

Listing assets and raw captures follow the repository's existing gitignore policy. Keep the files with this local checkout until upload. No App Store Connect changes are applied by these tools.
