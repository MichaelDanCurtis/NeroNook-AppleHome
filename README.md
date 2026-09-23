# Apple Home for NeroNook

Independent Mac Catalyst plugin, **0.2.1**. Public HomeKit supplies homes, rooms, accessories, scenes and current readings. Favorite accessories and supported on/off controls live directly in the Nook. Home Assistant and the Apple Home desktop app are not dependencies.

## Interface

Favorites / Rooms / Scenes use the shared 16:9 stage and one status line. Add or remove favorites directly on a Nook card. Settings owns Home selection, system authorization, pause and individually allowed controls; there is no Connection tab. The optional native window adds search and room filtering.

Readable characteristics include power, brightness, temperature, humidity, battery, contact, motion, door and lock state. On/off is supported for individually allowed lights, switches and outlets with exactly one readable/writable power target. Every command requires current reachable state, exact home/accessory/characteristic identity and in-card review, then reads back the result. Unknown results are never retried automatically. Multi-target accessories, scene execution, locks, doors and blinds remain read only.

## Build and install

The Xcode project is committed and reproducible with `python3 scripts/create-project.py`. A vendored generic SDK copy includes interactive cards and the application-launch transport; neither the host source checkout nor executable is needed to build. Python is a development tool, not a runtime dependency.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
bash scripts/package.sh
python3 scripts/test-protocol.py
python3 scripts/test-protocol.py --cards
```

Packaging requires a signed-in Xcode developer account and matching HomeKit provisioning for this bundle identity. It checks signature, profile identity, HomeKit entitlement, sandbox and expiry before producing `build/Apple Home Module.app` and `build/NeroNook-AppleHome-0.2.1.zip`. Set `NERONOOK_APPLE_TEAM` for an explicitly chosen development team. Register the development Mac through Xcode if requested. Never strip entitlements or ad-hoc-sign an installable release to bypass provisioning.

Install using **NeroNook 0.14 or newer → Settings → Modules → Install or Update Plugin**. The manifest opts into the SDK's generic application launch mode. LaunchServices starts a separate application with its own privacy identity; a one-session authenticated loopback connection carries only the usual SDK protocol. No HomeKit permission or entitlement is added to NeroNook. Older hosts receive an update-required state and cannot initialize HomeKit from their child-process path.

The model starts before a window is shown. While hosted, an activity assertion keeps the user-enabled integration responsive but allows normal system sleep; the timer runs in common main-run-loop modes. Host shutdown/disable ends the connection and process. Settings opens as a scrollable page in the plugin window, with Done returning to the dashboard. LaunchServices owns hidden startup; the plugin never hides the UIKit content window on first appearance. Window requests select a content scene and request a new scene if none remains.

## Data and validation

- Home access starts after enabling it in Settings, or resumes previously enabled access with OS authorization. HomeKit manages permission.
- Selected home, favorites and allowed-control identifiers stay in the plugin's own sandbox preferences. Readings are not persisted.
- Reads are limited to 300 accessories and 16 selected characteristics each, with eight concurrent requests and 12-second deadlines. Unique tickets reject late callbacks. Confirmed readings expire after two minutes.
- Home changes, disconnect/authorization loss and stale readings invalidate command targets. Commands have unique run IDs and a 20-second deadline, followed by explicit state readback.
- The shared action bus exports only read-only status. No cross-provider identity inference or Home Assistant authority is shared.
- The protocol harness creates a separate unentitled fixture with HomeKit disabled. It proves stdio compatibility and presentation, not live HomeKit behavior.

See [STATUS.md](STATUS.md) for live verification and remaining limits. The current package uses **development provisioning for this Mac**. It is not a notarized or public release; distribution signing and SDK redistribution licensing remain open.

Sources: [Apple DTS: HomeKit on Mac Catalyst](https://developer.apple.com/forums/thread/822517), [HomeKit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.homekit).
