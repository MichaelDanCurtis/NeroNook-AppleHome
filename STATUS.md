# Apple Home module status

September 22, 2026 · 0.1.0 source milestone, not an installed release

| Layer | Evidence |
| --- | --- |
| Independent source | Separate Xcode project, public HomeKit/Catalyst implementation and pinned generic SDK. No host or Home Assistant implementation changes. |
| Compilation | Xcode 27 Release-maccatalyst unsigned app builds. A stale optional Metal toolchain search path emits a linker warning; the app links and the test process runs. |
| Reading behavior | Three native tests pass: a 192-characteristic queue is fully read with eight concurrent tickets, timeout/reset rejects late callbacks, values expire and events refresh them. Uses no household data. |
| Generic plugin transport | The actual Catalyst process, in a separately ad-hoc-signed unentitled test copy with HomeKit disabled, passes stdin/stdout handshake, timed snapshots, 16:9 bounded diagrams, Favorites/Rooms/Scenes panels, read-only status and EOF exit. This is not a provisioned HomeKit app. |
| Developer signing | Attempted proper automatic provisioning. Xcode returns No Accounts and no Mac Catalyst App Development profile for cafe.nero.plugin.applehome. Apple Accounts settings is open for the owner to sign in. |
| Release packaging | Script and provisioning validator prepared; no installable release artifact is emitted before a matching unexpired HomeKit profile is verified. |
| Actual Apple Home | Not accessed. Requires developer-account sign-in, valid provisioning, installed native UI and user system Home permission, then real inventory/read-state validation. |

Remaining: signed Catalyst installation and window lifecycle inside NeroNook, system authorization/granted/denied/revoked behavior, live home selection and device reachability, read/notification agreement, sleep/wake, longer-term recovery, content UI inspection, reviewed device controls, Developer ID/notarization and public SDK licensing.
