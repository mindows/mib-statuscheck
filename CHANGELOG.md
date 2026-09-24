# Changelog

Notable changes to MIB Status Check. Versions follow `version` in
`manifest.json`.

## Unreleased

## 1.0.0 — 2026-09-23

The first public release.

- Watches up to 10 Atlassian Statuspage services on one timer, in one
  batched check. 39 presets, or paste any status page URL: it is verified
  before it is added, and a page that is unreachable is told apart from one
  that has no feed.
- The bar icon shows the worst status across everything watched. A page that
  can't be reached is never counted as down, but it does hold back the
  all-clear.
- One notification per service when its status changes. Toasts dismiss
  themselves, and the first reading of a newly added service is a silent
  baseline.
- A keyboard-driven popup with one line per service; click one to unfold its
  ongoing incident. A settings view manages the list, the interval, and the
  toggles, and shows the version.
- Status colors come from the current Omarchy theme and follow theme
  switches.
- An IPC target for scripting: add, remove, expand, refresh, and more.
- Every response is capped at 1 MiB before it is parsed.
- Nothing is watched until you pick a service.
- The plugin ID is `io.github.mindows.mib-statuscheck`. A copy installed
  under the earlier `mib-statuscheck` ID should be removed and installed
  again.
