# Apple Home for NeroNook

Independent Mac Catalyst plugin, 0.1.0 development work. This first slice reads your Apple Home inventory through public HomeKit APIs. It does not depend on Home Assistant, the Apple Home desktop app, a private framework, a transplanted credential or a host implementation change.

**Current gate:** the unsigned app builds and the real Catalyst process passes the plugin protocol harness. A provisioned release cannot yet be made: Xcode reports **No Accounts** and no matching Mac Catalyst App Development profile for `cafe.nero.plugin.applehome`. The existing local signing identity is not enough. The user must sign in to the appropriate developer account in Xcode. No actual HomeKit access, live accessory reading or real Home authorization is claimed.

## Interface

Favorites / Rooms / Scenes use the common 16:9 Nook stage and compact status. A separate native window offers search, room filtering and local favorites. Settings owns the home selection, system authorization and pause control. There is no Connection tab.

The first slice is read only. Supported readable characteristics include power, brightness, temperature, humidity, battery, contact, motion, door and lock state. Scenes show their names and action counts; they cannot be executed. Future writes require separately verified target semantics and explicit review.

## Build

The Xcode project is committed and also reproducible using `python3 scripts/create-project.py`. The Swift SDK is vendored from NeroNook commit `eaa9196b828309e01aaa798bfce820c83012181a`; there is no dependency on that checkout. Python is only a development tool and is not packaged.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
xcodebuild -project AppleHome.xcodeproj -scheme AppleHome -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/test-protocol.py
# After Xcode developer-account sign-in:
bash scripts/package.sh
```

Packaging asks Xcode to provision the app, verifies the signature, matching profile identity, HomeKit entitlement, sandbox and profile expiration, and only then produces the installable app/archive. Set `NERONOOK_APPLE_TEAM` to an explicitly chosen team if needed. Do not manually strip entitlements or ad-hoc-sign a release to get around provisioning.

The protocol test makes an **unentitled test copy**, starts it with `--protocol-test`, and never initializes HMHomeManager. That test proves Catalyst process/stdio lifecycle and display transport only. It is not the app to install and does not establish HomeKit access. All installable artifacts must pass the provisioning gate above.

## Data and lifecycle

- Home access begins only after the user enables it in plugin Settings, or resumes a previously enabled plugin whose system authorization remains granted. HomeKit manages the OS permission.
- Home identifiers and favorite accessory identifiers are local plugin preferences. Household readings are not persisted. The Catalyst app uses its own sandbox.
- Reads are limited to 300 accessories, 16 selected characteristics each, with eight concurrent requests and 12-second read deadlines. Unique read tickets reject late callbacks after timeout/reset. Confirmed values expire after two minutes; unreachable/no-reading states remain explicit.
- Home selection clears old read state. Characteristic notifications and periodic bounded refresh maintain status. Scene and device-changing APIs are never called.
- SDK exports only read-only status and an expiring status channel. There is no cross-provider identity inference or shared Home Assistant authority.

See [STATUS.md](STATUS.md) for verification boundaries. This is not notarized or published. SDK redistribution licensing and Developer ID distribution remain open.

Sources: [Apple DTS: HomeKit on Mac Catalyst](https://developer.apple.com/forums/thread/822517), [HomeKit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.homekit).
