# APK Distribution Research

## Status

Research only. This repository does not include a public website or release-download service.

## Questions to resolve

- Which Android versions and device-management policies will be supported?
- What teacher instructions are needed for installing from outside an app store?
- How will the organization communicate security warnings without normalizing unsafe installation behavior?
- How will APK signatures, checksums, release notes, and rollback guidance be published?
- Who owns the domain, hosting, certificate renewal, incident response, and release approval?
- Should QR codes point to a stable release page rather than directly to an APK?
- How will updates be delivered after the initial installation?

## Before implementation

Test the complete installation and update flow on representative school devices. Approve a release-signing custody process first. Never place private signing keys or passwords in Git or a general delivery ZIP.
