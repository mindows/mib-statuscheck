# omacheckstatus

An [Omarchy](https://omarchy.org/) shell plugin that watches
[status.claude.com](https://status.claude.com) from the status bar.

- Polls the Statuspage feed behind status.claude.com every 5 minutes.
- Fires one desktop notification whenever the status changes — a new incident,
  a new update on an ongoing one, a component degrading or recovering, or a
  return to normal. The toast times out on its own (15s for an outage, 6s for
  a recovery) and carries no click action, so a click just dismisses it.
- Left-click the bar icon for a popup with the **latest ongoing incident**:
  its title, lifecycle status, impact, how long it has been running, and the
  body of the most recent update. When nothing is wrong it says so.

The icon is a check when Claude is operational and a warning glyph in the
theme's urgent color when it is not.

## Interactions

| Input | Effect |
|---|---|
| left click | toggle the popup |
| right click | check now |
| middle click | open status.claude.com |
| `r` (popup) | check now |
| `o` (popup) | open status.claude.com |
| `j`/`k`, arrows, `Enter` | move and activate the popup cursor |
| `Esc` | close |

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

## Notifications

The toast announces; the bar icon is the state. So the toast always expires on
its own and the icon stays lit until the service actually recovers — you never
have to clear anything to get back to a truthful bar.

Dismissing early, all built into Omarchy:

| Input | Effect |
|---|---|
| left or right click the toast | dismiss it |
| `Super` + `,` | dismiss the last notification |
| `Super` + `Shift` + `,` | dismiss all notifications |
| `Super` + `Shift` + `Alt` + `,` | notification history |

The toast deliberately has no click action. Omarchy runs a toast's action and
*then* dismisses it, so attaching one would turn an ordinary click-to-dismiss
into "open a browser tab". To read more, click the bar icon — or middle-click
it to go straight to status.claude.com.

Urgency is capped at `normal` for the same reason: Omarchy gives a `critical`
toast a duration of `0`, meaning it never leaves the screen until dismissed by
hand. An outage doesn't warrant that when the bar icon is already carrying the
signal.

Set `"notify": false` on the widget's entry to turn the toasts off entirely
and rely on the icon alone.

## Settings

Set these inline on the widget's entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "omacheckstatus", "refreshIntervalSec": 300, "notify": true, "hideWhenOperational": false }
```

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `300` | Seconds between checks, clamped to 60–3600. |
| `notify` | `true` | Send a notification when the status changes. |
| `hideWhenOperational` | `false` | Keep the icon off the bar unless something is wrong. |

## Layout

| File | Role |
|---|---|
| `manifest.json` | plugin declaration and settings schema |
| `Service.qml` | polling, change detection, notifications |
| `Panel.qml` | bar button and popup |
| `Model.js` | feed parsing, labels, glyphs, relative times |

## Developing

The shell hot-reloads plugin code on save, but its file watcher does not
follow symlinks — so with the symlink install above, an edit in `~/dev` needs
a nudge:

```bash
omarchy restart shell
```

`omarchy-shell shell rescanPlugins` re-reads manifests but will not pick up
changed QML through the symlink.

The plugin registers an IPC target, which is handy while working on it:

```bash
omarchy-shell omacheckstatus state     # current description
omarchy-shell omacheckstatus refresh   # check now
omarchy-shell omacheckstatus toggle    # open/close the popup
```

To exercise the notification and incident paths without waiting for a real
outage, point `endpoint` in `Service.qml` at a `file://` path and edit that
JSON between refreshes.

## Notes

The first successful check after the shell starts establishes the baseline
silently — logging in to an already-broken service should not produce a
"status changed" toast. Only subsequent changes notify.

A failed check keeps the last good reading on screen and adds a line saying
the latest check failed, rather than blanking out what is known.

Requires `curl`, and `jq` (already an Omarchy dependency) for the notification
sender's click action.
