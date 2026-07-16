# 08 — Deferred Features: Backend, Sync, Analytics

These are core to the full Rahbar AI vision but **out of scope for the 3-week MVP**.
Documented here so the MVP's data model and UX don't paint us into a corner.

> **Note:** OMR grading is **no longer deferred** — it's an MVP demo feature. Its full
> design lives in [ADR-007](decisions/ADR-007-assessment-and-omr.md).

## Backend + analytics

**Goal:** account/school management, content & model-version distribution, storage of synced
records, and aggregate analytics (weak-SLO detection across schools for headmasters/boards).

- **Stack:** **FastAPI + PostgreSQL**, Dockerized, hosted on Render initially (Python matches
  the ML/data-prep tooling). Kubernetes only if scale later demands.
- **Model/corpus distribution:** serve versioned `curriculum.db` + model bundles so devices
  can update offline assets when connectivity allows.
- **Analytics:** aggregate MCQ/grading results → identify weak learning nodes (per SLO, per
  class, per school) → simple dashboards for headmasters/regional boards.

## Offline-first sync layer

**Goal:** never lose data across intermittent connectivity; push local content and pull
updates when a stable connection appears.

- **Local store:** SQLite (`drift`) already used by the MVP.
- **Queue:** a `sync_queue` table of pending writes (lesson plans, MCQ sets, grading results)
  with status/attempts; a background worker flushes it when online.
- **Conflict handling:** last-write-wins per record with server timestamps for the simple
  cases; teacher-owned content is rarely concurrently edited, so conflicts are minimal.
- **Design now, build later:** the MVP's local schema already anticipates a `sync_queue`
  ([`01-architecture.md`](01-architecture.md)) so adding sync is additive, not a rewrite.

*(OMR references moved to [ADR-007](decisions/ADR-007-assessment-and-omr.md).)*
