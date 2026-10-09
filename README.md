# SoundMarks

**Pin the music you listened to onto the places where you heard it — on a map and on an interactive 3D planet.**

SoundMarks is a native iOS app that turns your listening history into a personal map of memories.
It matches songs to places and photos, reminds you of them when you come back, and lets you
exchange maps with friends — all on the device, without an own server.

<!-- Screenshots: put PNGs into docs/screenshots/ and uncomment this block.
<p align="center">
  <img src="docs/screenshots/planet.png" width="200" alt="3D planet">
  <img src="docs/screenshots/map.png" width="200" alt="Map with record pins">
  <img src="docs/screenshots/place.png" width="200" alt="Place detail">
  <img src="docs/screenshots/roulette.png" width="200" alt="Record roulette">
</p>
-->

## Features

- **3D planet & map** — every place is a vinyl record on a MapKit map and a dot on a SceneKit globe;
  light by day, dark by night.
- **Listening history import** — Spotify *Extended Streaming History* (ZIP/JSON, parsed on the
  device) and Last.fm; track metadata, artwork and 30-second previews via the iTunes Search API.
- **Memory candidates** — finds moments in your photo library and matches them with what was
  playing at that time and place; confirm or skip each card.
- **Year timeline** — drag through the years and watch your planet grow.
- **Trips** — travel mode records the route locally and reconstructs the soundtrack of the trip.
- **Reminders** — geofences for the 20 nearest places and "on this day" notifications.
- **Friends** — add friends via QR code, sync maps peer-to-peer with MultipeerConnectivity or
  exchange a `.soundmap` file; shared "paired" planets that both people add places to.
- **Profile & analysis** — statistics per period (top artists, busiest month, listening time),
  ranks that unlock record skins.
- **Sharing** — 9:16 story cards (1080×1920) rendered with `ImageRenderer`.
- **Localization** — English, German and Ukrainian.

## Tech stack

| Area | Technologies |
| --- | --- |
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI, Observation, UIKit where needed |
| Maps & 3D | MapKit, SceneKit, simd |
| Data | Core Data with migrations, Keychain for tokens |
| Location | Core Location (geofencing, significant location changes) |
| Media | PhotoKit, AVFoundation, Core Image, ImageIO |
| Networking | URLSession, Last.fm and iTunes Search REST APIs |
| Peer-to-peer | MultipeerConnectivity, CryptoKit, custom ZIP reader/writer |
| Notifications | UserNotifications |
| Testing | Swift Testing — 192 tests |

## Architecture

```
SoundMarks/
  App/            entry point, dependency container (AppEnvironment), settings, root navigation
  Features/       one folder per screen: Planet, Map, AddPlace, Candidates, Timeline, Trip,
                  Roulette, Friends, Profile, Share, Onboarding, Settings, Splash
  Models/         value types (Sendable snapshots) shared between layers
  Services/       location, photos, music sources, matching, notifications, geofences, trips
    Stubs/        "unavailable" implementations used when a permission or source is missing
  Persistence/    Core Data stack, background reads, queries, change tracking
  Sync/           snapshot format, merge logic, MultipeerConnectivity transport
  Support/        Keychain, ZIP, logging, errors
  DesignSystem/   colors, typography, shared styles
SoundMarksTests/  unit tests and fixtures
```

Design decisions:

- **Protocol-based services** injected through `AppEnvironment`, so every service can be replaced
  by a stub in tests and previews.
- **Pure logic separated from frameworks** — matching (`MemoryMatcher`, `TripMatcher`),
  scheduling (`OnThisDayScheduler`), geofence selection and map merging have no dependency on
  PhotoKit, Core Location or the network and are covered by unit tests.
- **Privacy by design** — history, photos and analysis never leave the device; sync between friends
  goes directly from phone to phone.
- **Heavy work off the main actor** — scanning and imports run in the background and can be
  cancelled; the UI stays responsive.

## Author

**Ivan Movchan** — [LinkedIn](https://www.linkedin.com/in/ivan-movchan-088854427) ·
[GitHub](https://github.com/morty1338)
