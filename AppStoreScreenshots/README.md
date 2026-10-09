# App Store assets

Captured from the running app on 9 October 2026. Workout data is fictional; the showcase profile uses hortlund's chosen name, supplied avatar, and Leg Day Survivor badge. The screenshots show the actual interface; they contain no generated UI, device frames, or promotional overlays.

## Upload files

Product page header and search-result artwork are in [AppStoreCreative](../AppStoreCreative/README.md). Upload those to their dedicated creative slots, separately from the screenshots and previews below.

| Device slot | Screenshots | App previews |
| --- | --- | --- |
| iPhone 6.1 / 6.3 inch | [10 portrait PNGs](iPhone), 1206 × 2622 | [3 MP4s](../AppStorePreviews/iPhone), 886 × 1920 |
| iPad 12.9 / 13 inch | [10 portrait PNGs](iPad), 2064 × 2752 | [3 MP4s](../AppStorePreviews/iPad), 1200 × 1600 |

Review the sets together: [iPhone contact sheet](iPhone-overview.jpg) · [iPad contact sheet](iPad-overview.jpg). These two overview JPEGs are for review only; upload the individual PNGs from the device folders.

An **app preview** is a short video demonstrating the app in use. Apple allows up to three per device size and language; three is a maximum, not a requirement. These previews use actual simulator recordings, cut between actions at their original speed, with a silent stereo AAC track. They demonstrate set logging, the training Journey, and exercise progress.

| Preview | iPhone duration | iPad duration |
| --- | --- | --- |
| 01 — Log workout | 19 seconds | 26 seconds |
| 02 — Training Journey | 24 seconds | 25 seconds |
| 03 — Exercise progress | 24 seconds | 25 seconds |

Videos use H.264 High profile, level 4.0, 30 fps, a 10 Mbps target / 12 Mbps maximum video bitrate, and 48 kHz stereo AAC. All are under 500 MB. They contain no music or voiceover and work with autoplay muted. You can select the poster frame in App Store Connect; five seconds is a useful starting point. Upload the MP4s to the **app preview** slots and the PNGs to the **screenshot** slots. Assets have been prepared locally, not uploaded to App Store Connect.

Apple references: [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), [app preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/), and [manage App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets).

## Screenshot content

Both sets contain Start Workout, a template preview, completed set logging with a rest timer, profile highlights, weekly goals and muscle coverage, workout history, the training Journey, the exercise library, and an exercise progress chart. The tenth view is the year recap on iPhone and the September workout breakdown on iPad. The iPad uses its own native layout.

For a marketing-first order, lead with **05-muscle-heatmap**, **03-log-workout**, and **02-template-preview**, followed by Journey and progress. The repository README uses those three feature views.

## Recreate the capture data

Use dedicated simulators with no personal data. The capture devices were an iPhone 18 Pro and an iPad Pro 13-inch (M5), both running iOS/iPadOS 27.0. Capture the native framebuffer with `xcrun simctl io <UDID> screenshot <path>.png`; the MCP screenshot preview is downscaled and should not be uploaded.

Build the **WGJ Dev** scheme in **Debug**, overriding `WGJ_APP_DISPLAY_NAME=We Go Jim` so the iPad status bar uses the public app name. Install the resulting app and launch `se.highball.WeGoJim.dev` with:

```text
UITEST_IN_MEMORY_STORE
UITEST_SKIP_SPLASH
UITEST_FORCE_AUTO_ENTER_AFTER_SPLASH
UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT
MARKETING_SHOWCASE
```

Before launching, copy [`Source/hortlund-avatar.png`](Source/hortlund-avatar.png) to `Documents/marketing-avatar.png` inside the installed simulator app's data container (locate it with `xcrun simctl get_app_container <UDID> se.highball.WeGoJim.dev data`). This capture source is not bundled with the shipping app or included in the upload folders.

`MarketingShowcaseSeed` adds 24 weeks of strength and cardio history, templates with prescribed loads and reps, and the hortlund profile with the Leg Day Survivor badge. Including the bundled demo sessions, there are **102 completed workouts**, **120 km of walking/running**, and **248 catalog exercises**. Every fresh launch rebuilds the in-memory store. The seed is compiled only for Debug simulators, is reached only through the explicit in-memory launch mode, and uses a CloudKit-disabled model configuration. iCloud sign-in is unnecessary for capture and should be tested separately with an ordinary app launch.

Set dark appearance and a consistent status bar before capture:

```sh
xcrun simctl ui <UDID> appearance dark
xcrun simctl status_bar <UDID> override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
```

Keep screenshots at their original dimensions. Remove an entirely opaque alpha channel if present; do not stretch or crop the interface. Record each preview with the simulator video recorder. The export recipe is [`Scripts/export_app_store_previews.py`](../Scripts/export_app_store_previews.py); it accepts a directory of source recordings and an optional `--ffmpeg` path. Its edit points correspond to this capture session, so update them for new recordings. Raw takes and QA contact sheets are deliberately excluded from the upload directories.
