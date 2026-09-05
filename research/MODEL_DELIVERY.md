# Offline Model Delivery Research

## Current MVP

The app uses a bundled JSON manifest. Each downloadable model must have a direct HTTPS provider URL, exact byte size, and SHA-256 checksum. The app performs a direct download and local verification.

## Deferred questions

- Which exact model revisions and quantizations are approved for target phones?
- What memory, storage, speed, quality, and license evidence is required?
- Will direct provider URLs remain stable enough for pilots?
- When is a remotely updateable catalogue justified?
- If a remote catalogue is introduced, who signs it, stores keys, rotates keys, and approves rollback?
- How are interrupted downloads tested on low-storage and unreliable-network devices?

A signed catalogue, anti-rollback sequence, provider mirroring, or model proxy service should be implemented only after the simple direct-download flow is validated on real devices.
