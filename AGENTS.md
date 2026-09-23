# Apple Home plugin
Independent Mac Catalyst product. NeroNook and Home Assistant are not build or runtime dependencies. Only the generic SDK is shared. Do not modify host implementation to accommodate HomeKit semantics.
Use public HomeKit APIs and a properly provisioned HomeKit entitlement. Never transplant the Apple Home app's container, entitlements, sessions or private APIs. Do not claim access from a successful compile. User Home authorization is a separate step.
Tabs are Favorites, Rooms and Scenes. Put permissions and diagnostics in Settings. Start with read-only live inventory; device writes require explicit feature scope, target review and real state validation. No hidden device commands or automatic command retries.
