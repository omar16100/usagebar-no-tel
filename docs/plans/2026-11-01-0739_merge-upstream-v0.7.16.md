# Merge upstream v0.7.16 into the UsageBar fork: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the `no-telemetry` branch from upstream `v0.7.12` to upstream `v0.7.16` and keep all fork behavior.

**Architecture:** Merge `origin/no-telemetry` (4 docs commits), then merge tag `v0.7.16`. Port the explicit Claude profile homes into the new background discovery readout (`ProviderAccountDiscoveryReadout`). Remove the upstream notice about the next version. Re-apply the UsageBar brand to new upstream text.

**Tech Stack:** Swift 6.3 SwiftPM package, XCTest, `script/build_and_run.sh`.

**Spec:** The user request "do the v0.7.16 merge", and [fork-maintenance.md](../fork-maintenance.md).

## Global Constraints

- Do not merge upstream `main`. Commit `7129ab2` on `main` removes local logs, spend history, iCloud sync, the CLI and the local HTTP API.
- Keep the telemetry guard: `PostHogTelemetrySink.init` must refuse the placeholder token. `TelemetryConfig.bakedToken` must stay the placeholder.
- Keep the profile preference key `openusage.claude.configDirectories.v1` and its two values on the laptop.
- Keep iCloud Drive sync in `UsageBar/History/v1`, account-aware aggregation, peer polling and downloads.
- Keep the brand: user-visible text says `UsageBar`. Keep `Application Support/OpenUsage/*` cache paths unchanged.
- Do not push to GitHub. Do not install on the Studio in this task.
- Write new prose in ASD-STE100. Do not use em dashes.

## Review Focus

1. Laptop with two profiles (`~/.claude-work` as `CLAUDE_CONFIG_DIR`, `~/.claude-personal` explicit): two Claude cards, each with its own credentials. Covered by `testPersonalProfileReattachesExistingDesktopCardWithoutChangingWorkAccount`.
2. Profile set but no default or Desktop login: one card from the profile. Covered by `testAdditionalProfileWorksWithoutDefaultOrDesktopLoginAndRejectsUnknownIdentities`.
3. Profile that is also a Claude Swap account: the card keeps the profile credentials. Covered by `testSwapDiscoveryKeepsMatchingExplicitProfileCredentials`.
4. Default login with no organization and one explicit profile: the early return must not skip the profile. Covered by test 2 (no default login) and by the new guard in both `readClaude` and `assemble`.
5. Upstream notice "A New OpenUsage Is Coming": must not show in the fork. Verified by `grep` of `Sources/` and `strings` of the built binary.

---

### Task 0: Safety copies

- [ ] **Step 1:** Create branch `backup/pre-upstream-v0.7.16-20261101` at `f05e370`.
- [ ] **Step 2:** Copy `dist/UsageBar.app` and `defaults export io.github.omar16100.usagebar` output to `/private/tmp/usagebar-v0716-backup-<HHMM>`. Verify that both exist.

### Task 1: Merge `origin/no-telemetry`

**Files:** `README.md`, `docs/fork-maintenance.md` (conflicts).

- [ ] **Step 1:** `git merge origin/no-telemetry`. Keep both sides of the text. Keep the local "v0.7.12 with iCloud Drive sync" facts and the GitHub test-count provenance text.
- [ ] **Step 2:** Commit the merge.

### Task 2: Merge `v0.7.16` and port the profile homes

**Files:**
- Modify: `Sources/OpenUsage/Services/ProviderAccountDiscoveryReadout.swift`
- Modify: `Sources/OpenUsage/Services/ProviderAccountAssembly.swift`
- Test: `Tests/OpenUsageTests/ProviderAccountAssemblyTests.swift`

**Interfaces:**
- Produces: `struct ClaudeProfileObservation: Sendable { let directory: String; let outcome: DefaultAccountObserver.Outcome }`
- Produces: `ProviderAccountDiscoveryReadout.Claude.profiles: [ClaudeProfileObservation]` (default `[]`)
- Produces: parameter `claudeConfigDirectories: [String] = []` on `make(observer:accountsStore:families:...)` (after `families`), on `discover(...)` and on `readClaude(...)` (as `configDirectories`).
- Consumes: `DefaultAccountObserver.observeClaude(configDirectory:)` (fork, auto-merged).

- [ ] **Step 1:** `git merge --no-commit v0.7.16`.
- [ ] **Step 2 (red):** Resolve the test file conflict. Keep all upstream tests and the 3 fork tests. Add `async throws` or `async` and `await` to each fork test call of `ProviderAccountAssembly.make`.
- [ ] **Step 3:** Run `swift build --build-tests`. Expected: FAIL, "extra argument 'claudeConfigDirectories' in call".
- [ ] **Step 4 (green):** Resolve `ProviderAccountAssembly.swift` to the upstream side. Then:
  - `make(defaults:waitsForLoginShell:)` passes `defaults.stringArray(forKey: claudeConfigDirectoriesKey) ?? []`.
  - `readClaude` observes each non-blank directory before its early return, and the early return also needs `profiles.isEmpty`.
  - `assemble` early return also needs `claudeReadout.profiles.isEmpty`. The profile loop (from `6308c9b`) reads `claudeReadout.profiles` instead of calling the observer.
  - Keep the card loop that sets `configDirectory`, and keep `configDirectory: existing.configDirectory` in the swap merge.
- [ ] **Step 5:** Run `swift test --filter 'ProviderAccountAssemblyTests|ClaudeSwap|ClaudeDesktopAuthStoreTests'`. Expected: PASS.

### Task 3: Fork text, notice and other conflicts

**Files:** `Sources/OpenUsage/Views/SettingsScreen.swift`, `Sources/OpenUsage/Views/DashboardContentView.swift`, `Sources/OpenUsage/Stores/OnboardingStore.swift`, `Sources/OpenUsage/Views/NewVersionNoticeCard.swift` (delete), `Tests/OpenUsageTests/NewVersionNoticeTests.swift` (delete), `Sources/OpenUsage/Views/HeaderView.swift`, `Sources/OpenUsage/App/FirstLaunchWindowController.swift`, `Sources/OpenUsage/Views/FirstLaunchWelcomeView.swift`, `script/build_and_run.sh`, `README.md`, `docs/privacy.md`, `docs/settings.md`, `docs/dashboard.md`.

- [ ] **Step 1:** `SettingsScreen.swift`: use the upstream `row(...)` layout with the label `Help Make UsageBar Better`.
- [ ] **Step 2:** Remove the notice: delete the card, its test, the dashboard branch and its animation line, the `OnboardingStore` key, property and method, and the `docs/dashboard.md` paragraph. Reason: the fork keeps spend and token history, so the notice is false here.
- [ ] **Step 3:** Change `Welcome to OpenUsage` to `Welcome to UsageBar` (2 places).
- [ ] **Step 4:** Change the `Report an Issue…` link to `https://github.com/omar16100/usagebar-no-tel/issues/new`.
- [ ] **Step 5:** Set `APP_VERSION="0.7.16"` in `script/build_and_run.sh`.
- [ ] **Step 6:** Docs: keep the fork text in `README.md` and `docs/privacy.md`. Merge the upstream settings facts into `docs/settings.md` with the fork labels.
- [ ] **Step 7:** Verify: `git grep -n -E '"[^"]*OpenUsage[^"]*"' -- Sources/` shows only cache paths, bundle and module names. `git grep -n 'A New OpenUsage' -- Sources/` shows nothing.

### Task 4: Verify the full merge and commit

- [ ] **Step 1:** Re-read `Sources/OpenUsage/Services/Telemetry.swift`. Confirm the placeholder guard and the placeholder `bakedToken`.
- [ ] **Step 2:** Run `swift test`. Expected: 0 failures. Record the counts.
- [ ] **Step 3:** Commit the merge: `Merge upstream v0.7.16 while preserving UsageBar profiles and privacy`.

### Task 5: Install on the laptop and verify

- [ ] **Step 1:** Run `script/build_and_run.sh run`.
- [ ] **Step 2:** Verify in the log after the last `UsageBar v0.7.16-dev starting` line: `telemetry inert`, the two Claude cards, and `iCloud history loaded 2 devices (1 peers)`.
- [ ] **Step 3:** Verify `strings -a` of the binary has no `phc_` and no `A New OpenUsage`.
- [ ] **Step 4:** Verify `curl 127.0.0.1:6736/v1/usage/claude` returns `claude` and `claude@961ab622` with history.
- [ ] **Step 5:** Update `docs/fork-maintenance.md` (base version, test counts) and this plan's status in `docs/plans/index.md`. Commit.

### Not in this plan

- Push to GitHub, and the Studio install. The Studio needs a logged-in desktop session for code signing.
