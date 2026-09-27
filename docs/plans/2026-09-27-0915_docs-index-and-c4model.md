# Add a docs index and a C4 model

Date: 2026-09-27
Status: In review
Repo: https://github.com/omar16100/usagebar-no-tel (branch `docs/index-and-c4model` into `no-telemetry`)

## Goal

Give the fork two owner-convention docs: `docs/index.md` (what lives in `docs/` and how it is named)
and `docs/c4model.md` (architecture source of truth, written from the Swift source rather than from
the inherited upstream prose).

## Scope

- Docs only. No Swift, script or workflow changes.
- `docs/README.md` stays as the inherited hub for behavior pages; `docs/index.md` sits beside it.
- The root `README.md` Documentation list links both new docs; `docs/plans/index.md` registers this plan.
- No CI is added. GitHub Actions is disabled on this repo and the seven inherited upstream workflows
  under `.github/workflows/` are left untouched.

## Decisions

- Plan naming follows this repo's existing `docs/plans/YYYY-MM-DD-HHMM_topic.md` pattern, not a new
  one, so `docs/plans/index.md` stays the single plan register.
- The C4 model states the divergence from upstream as measured by `git diff v0.7.10 no-telemetry`
  (44 files), because it is wider than `Telemetry.swift`: the rebrand, deleted assets, the removed
  Dependabot config and the fork docs are all part of it.
- The C4 model also lists upstream identifiers the fork did not rename (paths, the pricing feed URL,
  the CLI's fallback defaults suite, the Info.plist iCloud container key), so they are not mistaken
  for fork work.

## Status

- 27 Sep 2026: drafted from source at `6fd60f9`; under codex review.
