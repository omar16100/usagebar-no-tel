# UsageBar (no-telemetry fork)

Tracks AI coding subscription usage from the macOS menu bar. This is an **unofficial fork**, built
so that the app sends no telemetry.

## Not the official project

This is a fork of [robinebers/openusage](https://github.com/robinebers/openusage), taken at tag
`v0.7.10`. It is **not** OpenUsage, and it is **not** affiliated with, endorsed by, or an official
part of OpenUsage or Robin Ebers.

Per upstream's [TRADEMARK.md](TRADEMARK.md), this fork uses a different name, does not ship the
OpenUsage logo or visual identity, and states plainly here that it is unofficial. If you want the
real thing, with signed and notarized releases, auto-updates, and support, get it from upstream.
Please do not report issues with this fork to them.

The code is MIT licensed. Copyright for the original work remains with Robin Ebers, see
[LICENSE](LICENSE).

## What is different from upstream

One change, in `Sources/OpenUsage/Services/Telemetry.swift`: no PostHog project token is baked in,
and the `OPENUSAGE_POSTHOG_TOKEN` environment override is removed.

That is enough to silence everything, because `PostHogTelemetrySink.init` guards on the placeholder
token and every method on the sink early-returns when unconfigured, so `PostHogSDK.setup()` is
never called. Upstream documents this path itself: token-less builds never phone home.

The reason for doing it at build level rather than using the in-app setting is that the in-app
"optional analytics" toggle is partial by design. Two signals ignore it:

1. The daily `app_daily_active` ping, which `TelemetryRecorder` emits regardless of the toggle.
2. Crash and error autocapture, which `errorAutocaptureEnabled(_:)` returns hardcoded `true` for.

Neither has an exposed setting, so no combination of preferences produces a build that stays off
the network. Design notes are in
[docs/plans](docs/plans/2026-09-01-1447_strip-posthog-telemetry-local-build.md).

Also, in this fork the outbound `User-Agent` and the in-app display strings say `UsageBar` rather
than `OpenUsage`, so provider APIs and the UI do not present this build as upstream's client.

## Build

Requires macOS 15 or later and a Swift 6.2 toolchain (Xcode 26 or later).

```sh
swift test                    # 1227 tests, 3 skipped, 1 known failure (see below)
script/build_and_run.sh run   # stages dist/UsageBar.app and launches it
```

`swift test` reports one failure,
`CodexProviderTests.testNoUsageDataBadgeIsDroppedWhenLocalLogsHaveSpend`. It is pre-existing upstream
at `v0.7.10`, not caused by anything in this fork. Anything above one failure means something here is
broken.

There are no prebuilt binaries and no update feed. The build has no app icon, since upstream's was
removed, and it is ad-hoc signed unless you set `CODESIGN_IDENTITY`, so macOS will ask permission
the first time it reads each provider credential from your keychain.

## Verifying it is actually silent

```sh
strings -a dist/UsageBar.app/Contents/MacOS/OpenUsage | grep phc_   # expect no output
grep "telemetry inert" ~/Library/Logs/UsageBar/UsageBar.log         # expect a match at launch
nettop -x -l 120 -p $(pgrep -f dist/UsageBar.app)                   # expect provider APIs only
```

Polling `lsof` once a second is not sensitive enough for the third check, since provider calls are
sub-second. `nettop` tracks flows and does catch them.

Note that upstream's PostHog project token still exists in the inherited git history. It is a
client-side write-only key that upstream publishes in its own public repository, so this is not a
leaked secret.

## Documentation

- [Privacy & usage data](docs/privacy.md), what is not sent and how to verify it
- [Maintaining this fork](docs/fork-maintenance.md), rebasing onto a newer upstream tag and what to
  re-check afterwards
- [docs/](docs/README.md) is inherited from upstream. Pages describing features this build does not
  have (updates, iCloud sync) carry a notice at the top

Design notes for both changes are in [docs/plans](docs/plans/index.md).
