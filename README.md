# omacheckstatus

An [Omarchy](https://omarchy.org/) shell plugin that watches service status
pages from the status bar.

- Watches up to **10 status pages** on one timer, in one batched request.
- The bar icon carries the **worst** status across everything you watch: a
  check when all is well, a warning glyph in the theme's urgent color when it
  isn't.
- Fires one desktop notification **per service** whenever that service's status
  changes — a new incident, a new update on an ongoing one, a component
  degrading or recovering, or a return to normal.
- Click the icon for a popup with **one compact line per service**. Click a
  line to unfold its ongoing incident. When nothing is wrong it says so.
- A built-in **settings view** (the gear) manages the service list and the
  check interval. Everything is written to `shell.json` as you change it, so
  the list survives restarts.

## What can be watched

Anything that publishes an [Atlassian
Statuspage](https://www.atlassian.com/software/statuspage) feed — that is, a
page with a working `/api/v2/summary.json`. A great many services do, which is
why one widget can watch them all from one contract.

**Google (including YouTube and Gmail), X/Twitter, Slack, AWS, Azure, Notion,
Linear and Heroku cannot be watched here.** They each run their own status
format. A pasted URL is checked before it is added, so one of those fails with
an explanation instead of becoming a row that can only ever say "unreachable".

The preset list below was verified against the live endpoint, and is offered
in this order — sorted by name, so nothing is promoted and you can predict
where anything sits. Pick from it, or paste any other Statuspage URL.

| | | | |
|---|---|---|---|
| 1Password | DigitalOcean | MongoDB | Squarespace |
| Airtable | Discord | Netlify | Stripe |
| Atlassian | Docker | npm | Supabase |
| Bitbucket | Dropbox | OpenAI | Tailscale |
| CircleCI | Elastic | Plaid | Twilio |
| Claude | Epic Games | Proton | Vercel |
| Cloudflare | Figma | Reddit | Wikipedia |
| Cloudinary | GitHub | Sentry | Zapier |
| Coinbase | HashiCorp | Shopify | Zoom |
| Datadog | Jira | Snowflake |  |

## Status colors

The icon and each row are colored by severity, using the **active theme's own**
`green`, `yellow` and `red` from its `colors.toml`. No stock theme defines
ok/warning/error roles, but all 22 define those three, so the colors are the
theme's rather than three hardcoded hexes fighting whatever palette is loaded —
and they follow a `omarchy theme set` live.

The aggregate icon (bar and popup header):

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

## Interactions

| Input | Effect |
|---|---|
| left click the icon | toggle the popup |
| right click the icon | check now |
| middle click the icon | open settings |
| click a row | unfold / fold its detail |
| middle click a row | open that service's status page |
| `j` / `k`, arrows | move the row cursor |
| `Enter` / `Space` | unfold the row under the cursor |
| `o` | open the cursored service's status page |
| `r` | check now |
| `s` | toggle the settings view |
| `Esc` | leave settings, or close the popup |

The settings view is mouse-driven: its dropdowns, text field and toggles own
the keyboard while they are active, so typing a URL does not drive the panel.

## Notifications

The toast announces; the bar icon is the state. So the toast always expires on
its own (15s for an outage, 6s for a recovery) and the icon stays lit until the
service actually recovers — you never have to clear anything to get back to a
truthful bar.

Dismissing early, all built into Omarchy:

| Input | Effect |
|---|---|
| left or right click the toast | dismiss it |
| `Super` + `,` | dismiss the last notification |
| `Super` + `Shift` + `,` | dismiss all notifications |
| `Super` + `Shift` + `Alt` + `,` | notification history |

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

## Install

```bash
git clone <this repo> ~/dev/omacheckstatus
ln -s ~/dev/omacheckstatus ~/.config/omarchy/plugins/omacheckstatus
omarchy-shell shell rescanPlugins
omarchy plugin enable omacheckstatus
```

Or, once it is pushed somewhere:

```bash
omarchy plugin add <repo-url> --enable --yes
```

## Settings

Managed in the popup's settings view, and stored inline on the widget's entry
in `~/.config/omarchy/shell.json`:

```json
{
  "id": "omacheckstatus",
  "refreshIntervalSec": 300,
  "notify": true,
  "hideWhenOperational": false,
  "services": [
    { "name": "Claude", "url": "https://status.claude.com" },
    { "name": "GitHub", "url": "https://www.githubstatus.com" }
  ]
}
```

| Key | Default | Meaning |
|---|---|---|
| `services` | Claude | Pages to watch, up to 10. Omit the key entirely to get the Claude default. |
| `refreshIntervalSec` | `300` | Seconds between checks. The settings view offers 5m / 15m / 30m / 1h / 3h; a hand-edited value is clamped to 60–21600. |
| `notify` | `true` | Send a notification when a service's status changes. |
| `hideWhenOperational` | `false` | Keep the icon off the bar unless something is wrong. |

Hand-editing is safe: the list is re-validated on load, so bad URLs are
dropped, duplicates collapse and the list is capped at 10. A service's `name`
is only a label — if you leave it out, the provider's own page name is adopted
on the first successful check.

## Scripting

The widget registers an IPC target, so a dotfiles bootstrap can set the list up
without hand-editing `shell.json`:

```bash
omarchy-shell omacheckstatus state            # one line per service
omarchy-shell omacheckstatus presets          # every preset name
omarchy-shell omacheckstatus addPreset GitHub # add by preset name
omarchy-shell omacheckstatus add status.figma.com  # add by URL (verified first)
omarchy-shell omacheckstatus remove GitHub    # by name or URL fragment
omarchy-shell omacheckstatus interval 900     # seconds
omarchy-shell omacheckstatus refresh          # check now
omarchy-shell omacheckstatus toggle           # open/close the popup
omarchy-shell omacheckstatus openSettings     # open on the settings view
omarchy-shell omacheckstatus expand Cloudflare # open with one detail unfolded
```

`expand` makes a useful keybind: "show me what's wrong with X".

## Developing

The shell hot-reloads plugin code on save, but its file watcher does not follow
symlinks — so with the symlink install above, an edit in `~/dev` needs a nudge:

```bash
omarchy restart shell
```

`omarchy-shell shell rescanPlugins` re-reads manifests but will not pick up
changed QML through the symlink.

`Model.js` is plain JavaScript with no QML dependencies, so it can be unit
tested directly:

```bash
node -e "const m=new Function(require('fs').readFileSync('Model.js','utf8')
  +'; return {normalizePageUrl,normalizeServices};')();
  console.log(m.normalizePageUrl('githubstatus.com'))"
```

## Layout

| File | Role |
|---|---|
| `manifest.json` | plugin declaration and settings schema |
| `Service.qml` | the batched poll, change detection, notifications, URL probing |
| `Panel.qml` | bar button, status popup, settings view |
| `Model.js` | presets, URL handling, feed parsing, labels, aggregation, severity |
| `StatusPalette.qml` | the theme's green/amber/red, re-read on a theme switch |

## Notes

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

Requires `curl`, and `jq` (already an Omarchy dependency) for the notification
sender.
