
# TimezoneBar

A small macOS menu bar app for glancing at times across cities and scrubbing a shared meeting time.
<img width="2677" height="1557" alt="Timezone Bar" src="https://github.com/user-attachments/assets/1da65952-573f-44ab-955c-3b1c6ab70c32" />

## Run from SwiftPM

```sh
swift run
```

## Build a dockless app bundle

```sh
./Scripts/make-app.sh
open .build/TimezoneBar.app
```

Bundle metadata can be overridden without editing the script:

```sh
BUNDLE_IDENTIFIER=com.example.TimezoneBar MARKETING_VERSION=1.0.0 BUILD_VERSION=42 ./Scripts/make-app.sh
```

## Build a downloadable ZIP

```sh
./Scripts/make-zip.sh
```

The ZIP is written to `.build/dist/TimezoneBar-0.1.0.zip` by default. For a public release, sign and notarize it:

```sh
SIGNING_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
NOTARY_PROFILE=timezonebar-notary \
NOTARIZE=1 \
MARKETING_VERSION=1.0.0 \
BUILD_VERSION=42 \
BUNDLE_IDENTIFIER=com.example.TimezoneBar \
./Scripts/make-zip.sh
```

The app stores cities and display settings in `UserDefaults`. It ships with a small bundled city catalog and does all timezone math with Foundation `TimeZone` and `Calendar`.
