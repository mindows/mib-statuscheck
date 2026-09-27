# Changelog

Notable changes to MIB Status Check. Versions follow `version` in
`manifest.json`.

## Unreleased

## 1.0.2 — 2026-09-26

- Fix: the Zoom and Bitbucket presets always showed *Unreachable*, because
  both status pages have moved. The presets point at the new pages, and a
  service saved under an old address is read as the new one, so it recovers
  on its own and keeps its name (#1).
- Redirects are never followed, so a page can't point the widget's
  requests at another host. A page that has moved now says *Status page has
  moved*, and adding one says so too, instead of passing the add-time check
  and then failing every poll.
- Pages are always fetched over https: a pasted or saved `http://` address
  is read as `https://`, so it works and matches its preset.
- The addresses you watch no longer appear in any process's command line,
  which other local users can read. They reach `curl` through the
  environment and a config file descriptor.
- A status page can no longer add links or formatting to a notification:
  the toast body is markup-escaped, since Omarchy renders it as styled text.
- Text from a feed (incident titles, components, the page's own name) is
  cleaned: invisible formatting characters such as bidi overrides,
  zero-width characters and tag characters are removed, control characters
  become spaces, and long text is cut with an ellipsis. That includes names
  already saved in `shell.json`.
- A `~/.curlrc` no longer changes how feeds are fetched. A line such as
  `include` there used to put headers in front of every feed, so all of them
  read as unreachable.

## 1.0.1 — 2026-09-24

- Fix: a watched status page could forge the batch's delimiter lines in its
  own response and report a false status, and send false notifications, for
  another watched service. Every delimiter now carries a random tag drawn
  fresh for each check, and anything without it is read as response text.
  Found in the marketplace security review.

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
