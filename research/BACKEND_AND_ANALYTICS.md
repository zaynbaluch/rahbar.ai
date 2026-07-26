# Backend and Analytics Research

## Status

Research only. No backend client, API service, database migration, analytics event queue, or background worker is active in the app.

## Questions to resolve before implementation

- Which decisions will the collected data support?
- What is the minimum event set needed for those decisions?
- Which records are prohibited, especially names, prompts, answers, scans, and precise location?
- Who is the data controller and who may access school-level or district-level aggregates?
- What consent, notice, retention, deletion, and audit requirements apply?
- How will school and district identifiers be provisioned without exposing personal information?
- What offline queue size, retry policy, and battery/network constraints are acceptable?
- How will schema changes remain backward compatible on intermittently connected devices?
- What evidence is required before moving from local-only testing to a pilot?

## Recommended research output

A threat model, event taxonomy, retention policy, data-flow diagram, pilot success criteria, and a go/no-go decision. Do not begin service implementation until those artifacts are approved.
