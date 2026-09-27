# Documentation index: UsageBar (usagebar-no-tel)

UsageBar is an unofficial, no-telemetry fork of
[robinebers/openusage](https://github.com/robinebers/openusage) taken at tag `v0.7.10`. Start with
the [README](../README.md). This page indexes `docs/` and states how new docs are named.

Status: current. Last updated 27 Sep 2026.

## Conventions

- Evergreen docs (describe behavior or architecture that changes with the code): `topic.md` in
  lowercase kebab-case, for example `fork-maintenance.md`. Keep them current.
- Plans (a dated piece of work): `docs/plans/YYYY-MM-DD-HHMM_topic.md`, registered newest first in
  [plans/index.md](plans/index.md). Keep a plan updated while its work is in progress; after that,
  do not rewrite it. If the facts change, add a new plan and link it.
- Provider pages live in `docs/providers/<provider>.md`; research notes in `docs/research/`.
- Most pages were inherited from upstream and still say "OpenUsage". Pages about features the fork's
  default build lacks (updates; iCloud sync, which needs a matching provisioning profile) carry a
  fork notice at the top.
- [c4model.md](c4model.md) is the architecture source of truth. Read it before an architecture
  change and update it for every change to containers, components, external systems or data flows.
- Register every new top-level doc in the table below.

## Documents

| Path | Category | Description | Date |
|---|---|---|---|
| [c4model.md](c4model.md) | Architecture | Context, containers, components, per-provider credential sources and hosts, data flows, and the exact divergence from upstream `v0.7.10`. Evergreen. | Created 27 Sep 2026 |
| [fork-maintenance.md](fork-maintenance.md) | Runbook | Rebasing onto a newer upstream tag, what to re-check, known deviations and the known test failure. | Fork doc |
| [privacy.md](privacy.md) | Behavior | Why and how this build sends no telemetry, and how to verify it. | Fork doc |
| [README.md](README.md) | Index | Inherited hub for the behavior, integration, provider and developer pages. | Inherited |
| [architecture.md](architecture.md) | Architecture | Upstream's prose architecture guide for the same code. | Inherited |
| [plans/index.md](plans/index.md) | Plan register | All plans, newest first. | Fork doc |
| [plans/2026-09-27-0915_docs-index-and-c4model.md](plans/2026-09-27-0915_docs-index-and-c4model.md) | Plan | Adding this index and the C4 model. | 27 Sep 2026 |
