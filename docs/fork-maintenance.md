# Maintaining this fork

This is a hand-maintained fork pinned to an upstream tag. There is no CI, no Dependabot and no
update feed, so keeping it current is a manual job. This page is the runbook.

## What the fork actually changes

Two separate things, worth keeping straight because only the first is load-bearing:

1. **The telemetry strip.** Two hunks in `Sources/OpenUsage/Services/Telemetry.swift` plus two tests
   in `Tests/OpenUsageTests/TelemetrySinkTests.swift`. See [privacy.md](privacy.md).
2. **The de-brand**, required by upstream's [TRADEMARK.md](../TRADEMARK.md). Display strings, the
   outbound `User-Agent`, the app name and bundle id, the log path, deleted icon assets, and the
   README.

## Remotes

```sh
git remote -v
# origin    https://github.com/omar16100/usagebar-no-tel.git
# upstream  https://github.com/robinebers/openusage.git
```

## Rebasing onto a newer upstream release

```sh
git fetch upstream --tags
git log --oneline v0.7.10..v<new>  -- Sources/OpenUsage/Services/Telemetry.swift
git rebase v<new>
swift test
script/build_and_run.sh run
```

### The one thing you must re-check

The strip works only because `PostHogTelemetrySink.init` refuses to configure itself when the
resolved token equals `TelemetryConfig.placeholderToken`. **If upstream ever changes that guard, a
token-less build stops being silent, and the rebase will not conflict to warn you.** Re-read
`Telemetry.swift` after every rebase and confirm the guard is intact, then re-run the three
verification checks in [privacy.md](privacy.md). The tests in `TelemetrySinkTests` assert the token
is the placeholder; they do not assert that a placeholder token still means "inert", because that
lives in upstream's code.

### Expect these conflicts

- `README.md` conflicts every time, since ours is a full replacement. Keep ours.
- `assets/` reappears if upstream touches the icon. Delete it again.
- Display strings conflict wherever upstream edits a line we renamed. Re-apply `UsageBar`.
- `script/build_and_run.sh` conflicts on the three identity variables near the top.

## Known deviations from upstream, by design

| Area | State here | Why |
|---|---|---|
| Telemetry | None | The point of the fork |
| App icon | None | Upstream's logo removed per their trademark policy |
| Auto-update | None | No `SUFeedURL`, so Sparkle is inert. See [updates.md](updates.md) |
| iCloud sync | Unavailable | Needs a provisioning profile this build has no identity for |
| Code signing | Ad-hoc | No Apple Development identity present. Set `CODESIGN_IDENTITY` to change |
| CI | Actions disabled | Upstream's release automation does not apply to a personal fork |
| Dependency updates | Manual | Dependabot config removed, so rebase to pick up security fixes |

## Known test failure

`swift test` reports **1227 tests, 3 skipped, 1 failure**. The failure is
`CodexProviderTests.testNoUsageDataBadgeIsDroppedWhenLocalLogsHaveSpend`, and it is **pre-existing
upstream at v0.7.10**, not caused by anything here. Verify that claim after a rebase by stashing
local changes and re-running that one test:

```sh
git stash push -m check
swift test --filter "CodexProviderTests/testNoUsageDataBadgeIsDroppedWhenLocalLogsHaveSpend"
git stash pop
```

If the count moves above one failure, the rebase broke something. Two tests here assert the fork's
identity rather than upstream's and are expected to differ: the Grok `User-Agent` and the default
`LogFile` path.

## A trap when reading logs

`swift test` writes into the real log file, because `LogFile.shared` uses the production default
path. A test run therefore leaves genuine-looking `[ERROR]` lines about expired keychain
credentials and HTTP 503s in `~/Library/Logs/UsageBar/UsageBar.log`. They are tests exercising
failure paths, not the app failing. Find the `UsageBar v… starting` line and only read forward from
there.

## Build environment notes

- `actool` fails on `assets/AppIcon.icon` under Xcode 26.5 with an `NSPlaceholderArray` exception.
  Irrelevant here since the icon is deleted, and the script continues without one.
- A cold `swift build` takes roughly eight minutes. Incremental rebuilds are about 25 seconds.
- Only one build can run at a time: the app binds the local API on `127.0.0.1:6736`, and
  `build_and_run.sh` opens with `pkill -x OpenUsage`, which also stops an installed official app.
