# Contributing

Thanks for helping out. Bug reports, new presets, fixes and features are all
welcome.

## Before you start

- **Bugs:** open an issue with the bug template. Include the plugin version
  and commit; the template shows how to find them.
- **Small fixes** (typos, an obvious bug, a verified preset): open a pull
  request directly.
- **Anything larger** (a new feed format, a new setting, a change to the
  popup): open an issue first, so we can agree on the approach before you
  write it. Check [ROADMAP.md](ROADMAP.md) too, because it may already be
  planned or deliberately ruled out.
- **Security problems:** don't open a public issue. See
  [SECURITY.md](SECURITY.md).

## Development setup

You need Omarchy with its shell, plus `curl`, `jq` and, for the `Model.js`
checks, `node`.

1. Fork the repo on GitHub and clone your fork to `~/dev/mib-statuscheck`.
2. If you installed the plugin with `omarchy plugin add`, remove that copy
   first, because the dev link goes in the same place:

   ```bash
   omarchy plugin remove mib-statuscheck --yes
   ```

3. Link your clone in and enable it:

   ```bash
   ln -s ~/dev/mib-statuscheck ~/.config/omarchy/plugins/mib-statuscheck
   omarchy-shell shell rescanPlugins
   omarchy plugin enable mib-statuscheck
   ```

4. After every edit, restart the shell. Its file watcher does not follow
   symlinks, so changes will not hot-reload:

   ```bash
   omarchy restart shell
   ```

## Where things live

| File | Role |
|---|---|
| `manifest.json` | plugin declaration and settings schema |
| `Service.qml` | the batched poll, change detection, notifications, URL probing |
| `Panel.qml` | bar button, status popup, settings view, IPC target |
| `Model.js` | presets, URL handling, feed parsing, labels, aggregation, severity |
| `fetch.sh` | every network request: curl with a deadline and a 1 MiB ceiling on the answer |
| `StatusPalette.qml` | the theme's green/amber/red, re-read on a theme switch |
| `docs/design.md` | why things behave the way they do; read it before changing behavior |
| `docs/feeds.md` | verified payload details for each provider format |

## Checking your change

There is no automated test suite yet. Before opening a PR:

```bash
omarchy plugin validate .
```

`Model.js` has no QML dependencies, so its functions can be run directly
with node:

```bash
node -e "const m=new Function(require('fs').readFileSync('Model.js','utf8')
  +'; return {normalizePageUrl,normalizeServices};')();
  console.log(m.normalizePageUrl('githubstatus.com'))"
```

Then restart the shell and try the change for real: open the popup, add and
remove a service, and check that notifications still fire.

## Adding a preset

A preset must serve a working Statuspage-compatible feed. Check it first:

```bash
curl -fsS https://status.example.com/api/v2/summary.json | jq '.page.name, .status.indicator'
```

If that prints a name and an indicator, add the service to `PRESETS` in
`Model.js`. Keep the list sorted by name, case-insensitively. Then add it to
the preset table in `README.md` and paste the command's output into your PR.

## Code conventions

- **Run external tools with argv arrays**, never as a shell string built from
  settings or feed content. When a script can't be avoided, pass data in as
  `"$@"`, the way the batched fetch in `Service.qml` does.
- **Write only this plugin's own settings**: its entry in
  `~/.config/omarchy/shell.json`. Never touch other config.
- Send notifications through `omarchy-notification-send --app-name
  mib-statuscheck`.
- Keep `Model.js` free of QML types, so it stays testable with node.
- Don't add runtime dependencies beyond what Omarchy ships without
  discussing it in an issue first.
- Match the surrounding style. Comments explain *why*, not *what*.

## Pull requests

- Branch off `main`, and keep each PR to one topic.
- **`main` must always be installable.** Users install and update from the
  current `main`, so a broken merge reaches everyone straight away.
- Write commit subjects in the imperative, as in the existing history
  ("Sort the preset list by name").
- Update the README if you change anything a user sees: settings, keys,
  IPC commands or presets.
- Don't bump the version in `manifest.json`. That happens at release time.
- PRs are squash-merged, so the PR title becomes the commit subject.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE) that covers this project.
