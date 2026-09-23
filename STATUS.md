# Apple Home module status

September 23, 2026 · **0.2.1 installed development preview**

## Blank-window fix

The owner reported a white native frame with no contents. The first-appearance callback hid every UIKit window in hosted mode, despite LaunchServices already launching the application hidden. Removed that duplicate hiding behavior. Explicit window requests now select a normal content scene rather than an arbitrary Catalyst helper/menu scene and request a new scene if needed. Settings now renders as a scrollable page in the main window: the old sheet path produced an inaccessible/nonvisible settings presentation during this acceptance run. Done returns to the dashboard.

The independently provisioned 0.2.1 package was installed through NeroNook's normal review. Five reading/command tests and both real Catalyst protocol fixtures pass; strict signature and HomeKit provisioning checks pass. Native dashboard and Settings were visually inspected with Home and the saved Nanoleaf favorite intact. Host Plugin Settings opens the populated settings page; Done returns to the dashboard. A plugin restart returns to the populated Home dashboard. No Home selection, favorites, authorization or allowed-control settings were changed, and no device command was sent. Nanoleaf still reports Unreachable; that is separate from the fixed window rendering.

Full close/reopen via normal Dock/Finder activation and broader macOS window restoration remain additional acceptance; the automated window inspector can reopen a closed scene, so it is not proof of that exact user path. Host code was not changed.

## Previous acceptance

| Layer | Evidence |
| --- | --- |
| Independent package | Separate Catalyst project and vendored generic SDK. HomeKit, settings, reads and allowed commands remain entirely in this package. No Home Assistant dependency. |
| Signing and packaging | Xcode account sign-in and Mac development registration are complete. The release build passes strict signature verification and exact identity, HomeKit entitlement, sandbox and unexpired provisioning-profile validation. This is a development-provisioned build for this Mac, not public distribution. |
| Reading and command logic | Five tests pass: bounded read concurrency, deadline/late-callback rejection, freshness/event handling, exact-home and allowed/reachable/fresh command requirements, and command deadline/new-run isolation. No hardware is used by these tests. |
| Compatibility protocol | Both no-HomeKit Catalyst process fixtures pass: stdio handshake, timed snapshots, Favorites/Rooms/Scenes, legacy diagrams or negotiated control cards, read-only action status and EOF exit. Fixtures are separate unentitled copies. |
| Application transport | NeroNook 0.14 launches the independently provisioned app with LaunchServices and the shared authenticated loopback SDK channel. Direct child launch caused a TCC usage-description crash despite the plugin containing its own purpose string; no host HomeKit entitlement was added. Hidden startup is eager, the timer uses common modes, and an idle-sleep-compatible activity prevents hidden-app timer suppression. |
| Live HomeKit inventory | Public HomeKit authorization and inventory work in the installed module. The owner selected **Home**, which contains Nanoleaf in Liams. It reports **Unreachable** and has no compatible light/switch/outlet power target in the current public inventory. My Home is not selected. No physical command was sent. |
| Nook acceptance | Real Rooms and Favorites cards were inspected on Odyssey Ark; the same connected favorite card was visually checked on the Built-in Retina Display, then its prior Logitech selection was restored. Favorite action moved Nanoleaf into Favorites; the native settings window shows the selected Home and no compatible power controls. Closing that window leaves the hosted connection running. Plugin restart and full host quit/relaunch restore Home, favorites and connection. Host quit leaves no Apple Home process. |
| Host regression | All 31 host tests and actual-host native acceptance pass, including zero-plugin start, existing stdio plugins, install/update/lifecycle, session/size/timeout rejection and independent process isolation. SDK application tests verify authenticated round-trip/EOF, wrong-nonce rejection before output and manifest compatibility. |

Remaining: real reachable-device characteristic agreement, notification/readback and physical on/off acceptance; scene execution; denied/revoked Home authorization, sleep/wake and long-term recovery; broader homes and hardware; independent developer install, distribution provisioning, notarization and SDK redistribution licensing. Current power support is deliberately limited to one writable/readable power characteristic on an allowed light, switch or outlet. No lock, garage, blind or scene command is implemented.
