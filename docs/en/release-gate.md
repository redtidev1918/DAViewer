---
title: Release gate
description: Conditions a DAViewer release candidate must meet before shipping — automated checks, device-verified core paths, and the acceptance record format.
---

# Release gate

**Language / 语言:** [中文](/release-gate.md) · English

Every release candidate needs its own verification record. A candidate is releasable only when: no known P0/P1 issues remain, core paths have device evidence, historical critical defects have regression tests, and remaining risks state their impact and verification scope.

## Automated verification

- DAViewer: format check, `flutter analyze`, `flutter test`.
- When DAKit changes alongside: run the affected packages' tests and record the SDK version used.
- Android, macOS, and Windows builds plus release-asset checks.
- Chinese release notes for the current manifest version; rules in [Build notes](build.md).

Passing automated tests does not replace device verification. For tests, evidence, and gaps see the [Regression catalog](../regressions/README.md).

## Device verification

| Path | What to accept |
| --- | --- |
| Sign-in and recovery | First sign-in, reopen after cancel, cold start, sign-out; an expired callback must not restore an old identity |
| Recommendations | Scroll at least two pages continuously, load more at the bottom, pull-to-refresh; repeated requests stay bounded |
| Web session | Signed-in, explicitly anonymous, challenge, and network-unavailable states verified separately; a failure must not clear valid OAuth |
| WebView | Page rebuilds and challenge prompts cause no controller rebuild or auto-reload loop |
| Notices | Dismissible; never covers the last row, bottom navigation, or the refresh gesture |
| Favourites and notifications | Web-session changes trigger no storm of official API requests |
| Proxy | Direct, working proxy, stopped proxy, cleared manual proxy; record platform and the actual network path |
| Content and download | Adult-content parameters, restricted previews, image download, literature body; restricted-content samples recorded separately |

An HTTP 200 from `rfy/deviations` does not prove the web session is healthy: anonymous cookies also receive generic content. Only the verification layer may submit session conclusions; when a bare HTTP result conflicts with a confirmed browser identity, a real WebView arbitrates. Rules in [Authentication and session recovery](authentication.md).

## macOS Keychain

Current builds do not require a paid Developer ID signature or notarization. Ad-hoc / missing TeamIdentifier and system authorization prompts are environment limitations; do not promise signing continuity across updates on that basis.

App behavior still needs acceptance: use the `DAViewer Account` service, never read historical ad-hoc items, and never loop deleting or rebuilding Keychain items at startup. Repeated authorization prompts or read/write loops caused by the app itself are defects; log them and triage by impact.

## Candidate record

For every release, record:

- Version, commit, DAKit dependency versions.
- Automated check commands, results, and build artifacts.
- Device platform, OS version, steps performed, and log locations.
- Known issues with severity, impact, and workarounds.
- Unverified items and why; state explicitly whether they block the release.

This page defines acceptance conditions; it does not declare that any candidate has passed. Historical records live in the [Regression catalog](../regressions/README.md); architecture audits and migration notes live under `architecture/` — read their conclusions against the version current when they were recorded.
