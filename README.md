# UsageBar (no-telemetry fork)

Tracks AI coding subscription usage from the macOS menu bar. This is an **unofficial fork**, built
so that the app sends no telemetry.

## Not the official project

This is a fork of [robinebers/openusage](https://github.com/robinebers/openusage), taken at tag
`v0.7.16`. It is **not** OpenUsage, and it is **not** affiliated with, endorsed by, or an official
part of OpenUsage or Robin Ebers.

Per upstream's [TRADEMARK.md](TRADEMARK.md), this fork uses a different name, does not ship the
OpenUsage logo or visual identity, and states plainly here that it is unofficial. If you want the
real thing, with signed and notarized releases, auto-updates, and support, get it from upstream.
Please do not report issues with this fork to them.

The code is MIT licensed. Copyright for the original work remains with Robin Ebers, see
[LICENSE](LICENSE).

## What is different from upstream

The privacy change, in `Sources/OpenUsage/Services/Telemetry.swift`: no PostHog project token is baked in,
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

Additional Claude Code profile homes can be registered alongside upstream account discovery. Each
profile keeps its own credentials and usage history; see [Claude profiles](docs/providers/claude.md).

## Build

Requires macOS 15 or later and a Swift 6.2 toolchain (Xcode 26 or later).

```sh
swift test                    # full regression suite
script/build_and_run.sh run   # stages dist/UsageBar.app and launches it
```

This fork does not run CI. Last local run: `swift test` on 1 Nov 2026 at commit `a33dcbc`
(v0.7.16 merge) printed 1,672 XCTest cases, 4 skipped, 0 failures, plus 3 Swift Testing tests
passed. The four skips are opt-in checks against real local logs or a live Claude account
(`OPENUSAGE_CLAUDE_PARITY`, `OPENUSAGE_CODEX_PARITY`, `OPENUSAGE_LIVE_CLAUDE`,
`OPENUSAGE_LIVE_CLAUDE_CLAIM_DRYRUN`).

Local test fixes keep real Pi history out of empty-history fixtures and put the OpenCode fixture on
the same local calendar day as its clock.

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
- [C4 model](docs/c4model.md), the architecture source of truth written from the Swift source,
  including the exact divergence from upstream
- [Docs index](docs/index.md), naming conventions and the fork's own docs
- [docs/](docs/README.md) is inherited from upstream. Pages describing features this build does not
  have (automatic updates) carry a notice at the top

Design notes for both changes are in [docs/plans](docs/plans/index.md).
