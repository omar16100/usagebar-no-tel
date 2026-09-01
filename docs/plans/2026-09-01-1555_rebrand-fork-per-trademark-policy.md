# Rebrand the fork to comply with upstream's trademark policy

Date: 2026-09-01
Status: Implemented, verified, published
Repo: https://github.com/omar16100/usagebar-no-tel (public, branch `no-telemetry`)

Follows on from
[the telemetry strip](2026-09-01-1447_strip-posthog-telemetry-local-build.md), which produced a
local build but did not address publishing it.

## Why

The fork was first published as `openusage-no-tel`. Upstream's `TRADEMARK.md` forbids exactly that:

> **What You Cannot Do** — Use "OpenUsage" as the name of a fork or derivative work

and sets three requirements for a fork: choose a different name, remove the OpenUsage logo and
branding, and clearly state that it is a fork and not the official OpenUsage. The MIT licence covers
the code but explicitly "covers the source code, not the brand".

## What changed

| Requirement | Action |
|---|---|
| Different name | Repo renamed to `usagebar-no-tel`. App is `UsageBar.app`, bundle id `io.github.omar16100.usagebar`, off upstream's reverse-DNS |
| Remove logo and branding | Deleted `assets/AppIcon.icon`, `assets/AppIcon.prebuilt` and the marketing screenshot. Renamed 30 user-facing strings and the outbound `User-Agent` |
| State it is unofficial | README rewritten as a fork notice, repeated in the repo description |

The rename went app-deep rather than repo-only, because the built app was itself a derivative
literally named OpenUsage. Renaming only the repository would have left a product called OpenUsage.

The log path also moved to `~/Library/Logs/UsageBar/UsageBar.log`. That was not purely cosmetic: the
fork and an installed official app had been writing into the same file, observed interleaving during
verification.

### Deliberately left alone

Renaming these would break behaviour, so they keep the upstream name:

- `Application Support/OpenUsage/*` cache paths (log-scan cache, pricing, Antigravity auth cache).
- The legacy LaunchAgent cleanup path, which must match the old filename to find and delete it.
- `OpenUsage_OpenUsage.bundle`, which SwiftPM derives from the module name. Changing it means
  renaming the target, touching every file's imports, for no user-visible gain.

Inherited developer docs still refer to OpenUsage as the upstream project. The policy explicitly
permits that: "Use OpenUsage to refer to this project in articles, blog posts, and discussions."

## Also done

**Dependabot removed.** It inherited upstream's `.github/dependabot.yml` and opened weekly PRs,
including posthog-ios bumps, which are pointless here since inertness comes from the absent token
rather than the SDK version. Note that Dependabot **ignores the repository Actions toggle**, so
disabling Actions was not sufficient and the config file had to be deleted. Two open PRs closed,
their branches deleted. Repo-level alerts and automated security fixes were already off.

**Documentation pass.** Inherited docs made false claims about this build. `docs/privacy.md`
rewritten (it had said the app "always sends" a daily ping and crash reports, "not optional", the
exact opposite of this fork). Fork notices added to `docs/updates.md` and `docs/icloud-sync.md`. Log
paths corrected in `docs/logging.md`, `docs/settings.md` and `docs/debugging.md`. New
[fork-maintenance.md](../fork-maintenance.md) covers rebasing and what to re-verify.

## Testing

`swift test`: 1227 tests, 3 skipped, 1 failure, the pre-existing
`CodexProviderTests.testNoUsageDataBadgeIsDroppedWhenLocalLogsHaveSpend`.

Two tests asserted the old brand and were updated, since the change in behaviour is intended: the
Grok `User-Agent` and the default `LogFile` path.

Rebuilt and launched. The app starts as `UsageBar v0.7.0-dev`, logs to the new path, reports
`telemetry inert` and `updates] disabled: no SUFeedURL`, and refreshes all providers except Cursor,
which is genuinely not signed in. The `User-Agent` change broke no provider.

## Residuals that cannot be closed

- GitHub keeps a permanent 301 redirect from the old `openusage-no-tel` URL. Rename redirects cannot
  be deleted; they only clear if someone else claims the old name.
- Upstream's PostHog token stays in inherited git history at `c344732`. It is a public write-only
  client key, not a secret.
- No automated dependency alerts, now that Dependabot is gone. Security fixes arrive by rebasing.
