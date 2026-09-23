# Design notes

Why the widget behaves the way it does. The [README](../README.md) covers how
to use it. This page is the reasoning behind it, for contributors and the
curious.

## Status colors

The icon and each row are colored by severity, using the **active theme's own**
`green`, `yellow` and `red` from its `colors.toml`. No stock theme defines
ok/warning/error roles, but all 22 define those three, so the colors are the
theme's rather than three hardcoded hexes fighting whatever palette is loaded —
and they follow a `omarchy theme set` live.

The **bar icon is deliberately monochrome** — it stays in the theme's bar
foreground like every widget beside it, and the glyph alone carries the state:
a check, a warning triangle, an exclamation, a times-circle. The colors below
apply to the popup.

The aggregate severity (popup header):

| Colour | When |
|---|---|
| green | every watched service is operational |
| amber | exactly one is not operational |
| red | two or more are not operational |
| grey | nothing read yet, or nothing is known-bad but a feed is unreachable |

A page we cannot reach is **not** counted as down — a failed request is not
evidence of an outage — but it does prevent an all-clear green, because with a
feed unread "all operational" is a claim the widget has not earned. The header
says so explicitly: *"2 of 5 affected · 1 unreachable"*.

Each row grades by that one service's own status instead, since the count rule
cannot apply to a single service: green operational, amber maintenance or a
minor issue, red a major or critical outage, grey unreachable. The status word
beside it stays dim when the service is fine, so an all-clear list reads calm
rather than shouting in green.

## The popup

One line per service — glyph, name, and a uniform status word. Providers each
write their own prose ("Partially Degraded Service", "Minor Service Outage"),
and ten phrasings stacked in one popup is noise, so the row states the status
in one consistent set of words: *Operational, Maintenance, Minor issue, Major
outage, Critical outage, Unreachable*.

A service with an open incident also shows its title on one elided line.
Clicking the row unfolds the provider's own description, the incident's status,
impact and age, the latest update (trimmed — the status page has the rest), and
the affected components. Only one row is unfolded at a time, so the popup stays
scannable whether you watch one service or ten. With a single service watched,
its detail is unfolded on open.

The settings view is mouse-driven: its dropdowns, text field and toggles own
the keyboard while they are active, so typing a URL does not drive the panel.

## Notifications

The toast announces; the bar icon is the state. So the toast always expires on
its own (15s for an outage, 6s for a recovery) and the icon stays lit until the
service actually recovers — you never have to clear anything to get back to a
truthful bar.

The toast deliberately has no click action. Omarchy runs a toast's action and
*then* dismisses it, so attaching one would turn an ordinary click-to-dismiss
into "open a browser tab". To read more, click the bar icon.

Urgency is capped at `normal` for the same reason: Omarchy gives a `critical`
toast a duration of `0`, meaning it never leaves the screen until dismissed by
hand. An outage doesn't warrant that when the bar icon already carries the
signal.

The first successful check of a service is its silent baseline, so adding a
service that is *already* broken does not fire a "status changed" toast. Only
subsequent changes notify.

## Implementation notes

**One request per tick, not one per service.** A single `curl` loop walks every
endpoint and emits a delimited stream, so ten feeds cost one process instead of
ten racing ones, and the whole readings set updates at once. URLs go in as
`"$@"` argv, so a hand-edited config can never become a command.

**A failed check keeps the last good reading** and marks the row, rather than
blanking out what is known. One unreachable feed cannot spoil the others in the
batch.

**A theme switch does not touch `colors.toml`.** `omarchy theme set` pushes the
new palette into the running shell over IPC (`shell applyTheme`) and swaps the
current-theme symlink, so a `FileView` watching that path alone goes stale.
`StatusPalette` therefore re-reads when the `Color` singleton changes, which
that IPC call is guaranteed to produce.

**Do not name anything `palette`.** Every QML `Item` already has an inherited
`palette` property (`QQuickPalette`), and it shadows an `id` of that name —
which is why the type is `StatusPalette` and the instance is `statusColors`.

**A host with a port is rejected**, so a self-hosted Statuspage on, say,
`:8899` cannot currently be added; `normalizeServices` also drops such an entry
on load, so hand-editing will not get around it.

**Arrays out of `shell.json` are not JS arrays.** They arrive as a list proxy
that indexes and reports `length` correctly but fails `Array.isArray`, which
silently read a perfectly good service list as empty. `Model.toArray` coerces
anything array-shaped crossing that boundary — worth knowing before adding
another list-valued setting.
