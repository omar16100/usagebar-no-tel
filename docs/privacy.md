# Privacy & Usage Data

**This fork sends nothing.** No analytics, no daily ping, no crash reports. There is no setting to
change, because there is no transport to enable.

That is the entire reason this fork exists. If you want the official app's behaviour, described at
the bottom of this page for contrast, use [upstream](https://github.com/robinebers/openusage).

## Why a build change was needed

The official app has a Privacy toggle for "extra" analytics, but two signals deliberately ignore it:

1. A daily `app_daily_active` ping. `TelemetryRecorder.tick()` emits it "regardless of the analytics
   toggle".
2. Crash and error autocapture. `PostHogTelemetrySink.errorAutocaptureEnabled(_:)` returns a
   hardcoded `true`, and upstream has a test asserting it stays on when the toggle is off.

Neither has an exposed setting, so no combination of preferences produces a build that stays off the
network. The only lever is the build itself.

## How it is switched off

`Sources/OpenUsage/Services/Telemetry.swift` bakes no PostHog project token, and the
`OPENUSAGE_POSTHOG_TOKEN` environment override is removed, so the resolved token is always the
`phc_REPLACE_ME` placeholder.

`PostHogTelemetrySink.init` guards on exactly that:

```swift
guard token.hasPrefix("phc_"), token != TelemetryConfig.placeholderToken else {
    configured = false
    AppLog.info(.config, "telemetry inert: no PostHog project token configured")
    return
}
```

`PostHogSDK.shared.setup()` is therefore never called, and every method on the sink (`capture`,
`setOptionalAnalyticsEnabled`, `flush`) early-returns on `configured`. No transport is ever
constructed, which is why this also covers the two mandatory signals above.

This is upstream's own documented path, not a hack around it. Their source comment reads:
"token-less builds never phone home."

The PostHog SDK is still linked, just unreachable. Removing the dependency outright would reach the
same runtime behaviour with a much larger diff that conflicts on every upstream upgrade.

## Verifying it yourself

Do not take this page's word for it. Three independent checks:

```sh
# 1. No project token of any kind in the binary.
strings -a dist/UsageBar.app/Contents/MacOS/OpenUsage | grep phc_        # expect no output

# 2. The sink reports itself inert at launch.
grep "telemetry inert" ~/Library/Logs/UsageBar/UsageBar.log

# 3. No connection to PostHog while running.
nettop -x -l 120 -p "$(pgrep -f dist/UsageBar.app)" | grep -E "3\.41\.202\.|posthog"
```

Check 3 needs care. Polling `lsof` once a second is **not** sensitive enough: provider calls are
sub-second, so a poll can report zero endpoints across a refresh that definitely happened, which
looks like proof and is not. `nettop` tracks flows and does catch them, so a run that shows the
seven provider API flows and no PostHog flow is meaningful.

## The Privacy toggle in Settings

The toggle still appears, and still stores a preference in the
`<bundle id>.telemetry` defaults suite, because the plumbing is untouched. In this build it controls
nothing: the sink it would talk to was never configured. Its label is also inherited and overstates
things.

## What is still on the network

Stripping telemetry does not make the app offline. It still talks to provider APIs to do its job:
Anthropic, OpenAI/Codex, GitHub Copilot, Z.ai, Antigravity, OpenCode and so on, using whatever
credentials you have locally. It also fetches model pricing. Those are the flows you should expect
to see in check 3.

## One historical note

Upstream's PostHog project token remains in this repository's inherited git history, at commit
`c344732`. That is not a leaked secret: it is a client-side, write-only key that upstream publishes
in its own public repository. Removing it would mean rewriting 550 commits.

## For contrast, what the official app sends

Documented so you can see exactly what is being declined: an anonymous daily active ping (app and
macOS version, enabled providers and metrics, a random install ID), anonymous crash reports with
stack traces, and, when the Privacy toggle is on, per-provider daily refresh counts and error
categories. Upstream states it sends no account details, credentials or usage values. This fork
sends none of it regardless.
