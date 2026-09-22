import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Semantic status colors, taken from the active Omarchy theme.
//
// No stock theme defines ok/warning/error roles — `shell.toml` has no such
// keys — but every one of them defines `green`, `yellow` and `red` in
// `colors.toml`, so those are what a themed status color can rely on. Reading
// them here means the widget's green/amber/red are the theme's own, not three
// hardcoded hexes fighting whatever palette is loaded.
//
// `red` needs no work: Color.urgent is already loaded from the theme's `red`
// (or ANSI color1), so it is used directly and stays correct for free.
QtObject {
  id: root

  readonly property string themePath:
    Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

  // Fallbacks for a theme that somehow ships neither the named key nor its
  // ANSI equivalent. Muted mid-tones rather than pure hues, so they sit
  // acceptably on both light and dark backgrounds.
  readonly property color fallbackOk: "#89b482"
  readonly property color fallbackWarn: "#d8a657"

  property color ok: fallbackOk
  property color warn: fallbackWarn
  readonly property color error: Color.urgent
  readonly property color unknown: Color.muted

  // Pick the color for one of the severities produced by Model.severity().
  function forSeverity(severity) {
    if (severity === "ok") return ok
    if (severity === "warn") return warn
    if (severity === "down") return error
    return unknown
  }

  // Same shape as Color.loadColors: `key = "#rrggbb"`, with the ANSI names as
  // the fallback spelling that older or terminal-derived themes use.
  function loadPalette(raw) {
    var nextOk = fallbackOk
    var nextWarn = fallbackWarn
    var namedOk = false
    var namedWarn = false
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      var key = match[1]
      if (key === "green") { nextOk = match[2]; namedOk = true }
      else if (key === "yellow") { nextWarn = match[2]; namedWarn = true }
      else if (key === "color2" && !namedOk) nextOk = match[2]
      else if (key === "color3" && !namedWarn) nextWarn = match[2]
    }
    ok = nextOk
    warn = nextWarn
  }

  property FileView paletteFile: FileView {
    id: paletteFile
    path: root.themePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPalette(text())
    // `text()` is stale inside the change signal, so route every path through
    // reload → onLoaded and always parse fresh content.
    onFileChanged: reload()
    onLoadFailed: root.loadPalette("")
  }

  // `omarchy theme set` pushes the new palette into the running shell over IPC
  // (`shell applyTheme`) and swaps the current-theme symlink; it never writes
  // the file this watcher is pointed at. Watching alone would therefore go
  // stale on a theme switch, so the Color singleton's own update — which that
  // IPC call is guaranteed to produce — is the cue to re-read.
  property Connections themeConnections: Connections {
    target: Color
    function onUrgentChanged() { paletteFile.reload() }
    function onForegroundChanged() { paletteFile.reload() }
    function onBackgroundChanged() { paletteFile.reload() }
  }
}
