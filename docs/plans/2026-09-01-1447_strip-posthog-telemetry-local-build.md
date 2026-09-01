# Strip PostHog telemetry from a local OpenUsage build

Date: 2026-09-01
Status: Implemented, verified
Base: upstream `robinebers/openusage` at tag `v0.7.10` (clean clone, detached HEAD)

## Objective

Run OpenUsage on a managed work machine with no telemetry leaving the device.

The shipped notarized build exposes an in-app "optional analytics" toggle, but that toggle is
partial by design. Two signals ignore it:

1. The daily `app_daily_active` ping, emitted "regardless of the analytics toggle"
   (`Sources/OpenUsage/Stores/TelemetryRecorder.swift`).
2. Crash and error autocapture. `PostHogTelemetrySink.errorAutocaptureEnabled(_:)` returns a
   hardcoded `true`, and upstream has a test asserting it stays on when the toggle is off.

Neither has an exposed setting, so a build change was the only way to reach zero egress.

## Approach

Upstream already supports this. `PostHogTelemetrySink.init` guards on the resolved project token:

```swift
guard token.hasPrefix("phc_"), token != TelemetryConfig.placeholderToken else {
    configured = false
    AppLog.info(.config, "telemetry inert: no PostHog project token configured")
    return
}
```

Every method on the sink (`capture`, `setOptionalAnalyticsEnabled`, `flush`) is
`guard configured else { return }`. With no real token, `PostHogSDK.shared.setup()` is never
called, so there is no transport at all. The upstream source comment states it directly:
"token-less builds never phone home."

Chosen option: make the build token-less rather than remove the dependency.

- Set `TelemetryConfig.bakedToken` to the `phc_REPLACE_ME` placeholder sentinel.
- Delete the `OPENUSAGE_POSTHOG_TOKEN` environment override, so nothing can re-arm telemetry at
  runtime.

Rejected: removing `posthog-ios` from `Package.swift` and replacing the sink with a no-op. It
reaches the same runtime behaviour but produces a large diff that conflicts on every upstream
upgrade. The PostHog code remains linked here but is unreachable.

## Files changed

- `Sources/OpenUsage/Services/Telemetry.swift` (14 lines removed, 8 added)
- `Tests/OpenUsageTests/TelemetrySinkTests.swift` (2 tests added)

## Testing

Written test-first, red then green.

- `testNoRealProjectTokenIsBakedIntoTheBuild` asserts the resolved token is the placeholder.
- `testEnvironmentCannotSupplyAProjectToken` sets `OPENUSAGE_POSTHOG_TOKEN` and asserts it is
  ignored.

Both failed against stock source for the intended reason (the real `phc_vGEqXEpQ...` token, and
the env override being honoured), then passed after the change.

Full suite: 1227 tests, 3 skipped, 1 failure. The failure is
`CodexProviderTests.testNoUsageDataBadgeIsDroppedWhenLocalLogsHaveSpend`, confirmed pre-existing
by stashing the change and reproducing it identically on stock `v0.7.10`. It is unrelated to
telemetry.

Binary-level verification: `strings` finds no `phc_` token of any kind in the built binary,
against the notarized build which contains `phc_vGEqXEpQ...`.

## Build and install

Built with upstream's own `script/build_and_run.sh`, which stages the bundle under `dist/`.

Properties of the resulting build, all verified:

- Bundle id `io.github.omar16100.usagebar` and app name `UsageBar`, renamed from upstream's per
  their TRADEMARK.md, so it keeps its own settings and does not disturb the installed notarized app.
  The log also moved to `~/Library/Logs/UsageBar/UsageBar.log`, which additionally stops it sharing a
  log file with the official app.
- No `SUFeedURL` in `Info.plist`, so Sparkle cannot auto-update the patched build back to the
  notarized release.
- Ad-hoc signed. This machine has no Apple Development identity (`security find-identity` reports
  0 valid identities). Consequence: macOS keys keychain grants to signature plus bundle id, so
  provider credential prompts reappear after each rebuild.
- No iCloud provisioning profile, so iCloud sync is unavailable in this build. Not a loss, since
  it was already off.
- `Info.plist` reports version `0.7.0-dev`. The script hardcodes `APP_VERSION`; the source is
  actually `v0.7.10`. Cosmetic only.

## Re-applying on a future upstream release

The diff is two hunks in one source file plus two tests. Re-clone at the new tag and re-apply.
Check that `PostHogTelemetrySink.init` still guards on the placeholder sentinel before trusting
that a token-less build stays silent.
