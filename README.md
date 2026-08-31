# Caffeine Toggle

A native macOS Control Center toggle that keeps a Mac awake and optionally prevents lid-close sleep.

**Website:** [kimiyashar.github.io/caffeine-toggle](https://kimiyashar.github.io/caffeine-toggle/)

- Empty mug: normal sleep behavior
- Filled mug: prevents idle sleep and disables clamshell sleep
- Native WidgetKit Control Center control
- Background AppKit helper owns the `caffeinate` process

> [!WARNING]
> Caffeinated mode keeps the Mac running with its lid closed. Never use it inside a bag, sleeve, bed, or other poorly ventilated space. CPU/GPU-heavy work can generate substantial heat.

## Requirements

- macOS 26 or later
- Apple Silicon Mac
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An Apple Development signing team

## Build

```sh
xcodegen generate
xcodebuild \
  -project CaffeineToggle.xcodeproj \
  -scheme CaffeineToggle \
  -configuration Release \
  -derivedDataPath .derived \
  build
```

Before building, replace the development team and bundle identifiers in `project.yml` with values for your Apple Developer account.

The built app is located at:

```text
.derived/Build/Products/Release/Caffeine Toggle.app
```

Copy it to `/Applications` or `~/Applications`, launch it, then open **Control Center → Edit Controls**, search for **Caffeine**, and add it to Control Center.

For automatic startup, add Caffeine Toggle under **System Settings → General → Login Items**.

## Command interface

The app executable also supports:

```sh
CaffeineToggle --on
CaffeineToggle --off
CaffeineToggle --toggle
CaffeineToggle --status
```

## How it works

The helper launches:

```text
/usr/bin/caffeinate -d -i -m -s
```

It also calls the private IOKit root-domain selector used to change clamshell sleep behavior. Turning the control off restores normal clamshell sleep before terminating `caffeinate`.

## Important limitations

- The clamshell API is private and unsupported by Apple. A macOS update may change or break it.
- The app must remain running for the Control Center toggle to control the helper.
- Physical lid-close behavior should be tested on each target Mac before relying on it.
- This is not intended for Mac App Store distribution.

## Tests

```sh
xcodebuild test \
  -project CaffeineToggle.xcodeproj \
  -scheme CaffeineToggleTests \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-tests
```

## License

MIT
