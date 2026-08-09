# TimezoneBar

<img width="2677" height="1557" alt="Timezone Bar" src="https://github.com/user-attachments/assets/1da65952-573f-44ab-955c-3b1c6ab70c32" />

TimezoneBar is a small macOS menu bar app for glancing at times across cities and finding reasonable meeting windows.

It shows each city's local time, day offset, and availability band:

- Green: working or available hours
- Yellow: near hours, usually early morning or evening
- Gray: outside normal hours

The app stores cities and display settings locally in `UserDefaults`. It ships with a bundled city catalog and uses Foundation `TimeZone` and `Calendar` for timezone math.

## Download the latest release

Download the latest Apple Silicon macOS ZIP from [GitHub Releases](https://github.com/crypblizz8/timezone-bar/releases/latest).
Public release ZIPs should be signed with Apple Developer ID and notarized for macOS.

After downloading:

1. Unzip `TimezoneBar-*.zip`
2. Move `TimezoneBar.app` to `/Applications`
3. Open `TimezoneBar.app`

## Run it locally

```sh
swift run
```

To build a local app bundle:

```sh
./Scripts/make-app.sh
open .build/TimezoneBar.app
```

To create a local unsigned ZIP for testing:

```sh
MARKETING_VERSION=0.2.0 ALLOW_UNSIGNED=1 ./Scripts/make-zip.sh
```
