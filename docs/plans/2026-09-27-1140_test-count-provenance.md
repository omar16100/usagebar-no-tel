# Give the README test count a date and a run behind it

Date: 2026-09-27
Status: Merged (#5, `4d27a5b`), 27 Sep 2026
Repo: https://github.com/omar16100/usagebar-no-tel

## Goal

The README Build section said `swift test` gives "1227 tests, 3 skipped, 1 known failure" with no
date, commit or run behind it, and this fork runs no CI. Either reproduce the figure and record the
run, or drop the number.

## Scope

- Docs only: `README.md` Build section and the "Known test failure" section of
  `docs/fork-maintenance.md`. No Swift, script or workflow changes. GitHub Actions stays disabled.

## Run

- 27 Sep 2026, commit `6ba0f35` (current `no-telemetry`), macOS 26.3 (25D125), Xcode 26.5
  (17F42), Apple Swift 6.3.2.
- `swift build --build-tests` (about 28 s), then `swift test --disable-sandbox --skip-build` under
  `sandbox-exec` with a profile that denies outbound IP connections except to localhost, so no test
  could reach a provider or upstream. `--disable-sandbox` turns off SwiftPM's own subprocess
  sandboxing (manifest and plugin), which cannot nest inside `sandbox-exec`; the outer sandbox
  stays active for the whole run. No signing is involved.
- XCTest: `Executed 1227 tests, with 3 tests skipped and 1 failure (0 unexpected)` in about 7 s.
  Swift Testing: 3 tests in 1 suite passed.
- Skips: `ClaudeLogUsageScannerTests.testParityAgainstRealLocalLogs` (`OPENUSAGE_CLAUDE_PARITY`),
  `CodexLogUsageScannerTests.testParityAgainstRealLocalLogs` (`OPENUSAGE_CODEX_PARITY`),
  `ClaudeProviderTests.testLiveClaudeUsageReportsResetFields` (`OPENUSAGE_LIVE_CLAUDE`).
- Failure: `CodexProviderTests.testNoUsageDataBadgeIsDroppedWhenLocalLogsHaveSpend`, the known one.
- Side effect: as `docs/fork-maintenance.md` already warns, the run appended test log lines to the
  real `~/Library/Logs/UsageBar/UsageBar.log`.

## Decision

The figure reproduced exactly, so it stays, now with the date, commit, OS and toolchain, the exact
XCTest summary line, and a plain statement that the fork has no CI.
