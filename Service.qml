import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Polls the Statuspage summary feed behind status.claude.com on a timer, keeps
// the last good reading, and fires one desktop notification whenever the
// reading changes in a way a user would care about.
//
// One `curl` per tick is the whole network surface: summary.json carries the
// overall indicator, every component, the unresolved incidents with their
// update trail, and active maintenance, so nothing needs a second request.
Item {
  id: root

  property var settings: ({})

  readonly property string endpoint: "https://status.claude.com/api/v2/summary.json"
  readonly property string statusPageUrl: "https://status.claude.com"

  // Last good reading. These survive a failed poll on purpose — a dropped
  // network shouldn't blank out what we know, it should just say so.
  property string indicator: ""
  property string description: ""
  property var incident: null
  property int incidentCount: 0
  property int maintenanceCount: 0
  property var degraded: []

  property bool loading: false
  property string lastError: ""
  property double lastSuccessMs: 0
  property double lastAttemptMs: 0

  property string _body: ""
  property string _stderr: ""

  // The signature of the reading we last told the user about. Empty until the
  // first successful poll, which establishes the baseline silently: logging in
  // to an already-broken service should not fire a "status changed" toast.
  property string notifiedSignature: ""

  readonly property bool healthy: Model.isHealthy(indicator)
  readonly property bool known: indicator !== ""
  readonly property bool degradedKnown: known && !healthy
  readonly property string glyph: known ? Model.indicatorGlyph(indicator) : Model.indicatorGlyph("")
  readonly property string headline: known ? description : (lastError !== "" ? "Status unavailable" : "Checking…")

  readonly property int refreshIntervalSec: {
    var raw = Number(settings ? settings.refreshIntervalSec : undefined)
    if (!isFinite(raw)) return 300
    return Math.max(60, Math.min(3600, Math.round(raw)))
  }
  readonly property bool notifyEnabled: !settings || settings.notify !== false

  signal readingChanged(string signature)

  function refresh() {
    if (fetchProcess.running) return
    lastAttemptMs = Date.now()
    loading = true
    fetchProcess.running = true
  }

  function openStatusPage() {
    Quickshell.execDetached(["xdg-open", root.statusPageUrl])
  }

  function openIncident() {
    var url = incident && incident.url !== "" ? incident.url : root.statusPageUrl
    Quickshell.execDetached(["xdg-open", url])
  }

  function apply(reading) {
    indicator = reading.indicator
    description = reading.description
    incident = reading.incident
    incidentCount = reading.incidentCount
    maintenanceCount = reading.maintenanceCount
    degraded = reading.degraded
    lastError = ""
    lastSuccessMs = Date.now()

    var signature = Model.signatureOf(reading)
    if (signature === notifiedSignature) return

    var firstReading = notifiedSignature === ""
    notifiedSignature = signature
    readingChanged(signature)
    if (!firstReading && notifyEnabled) notify(reading)
  }

  // argv, not a shell string: an incident title or update body is arbitrary
  // remote text, and the notification sender takes each value as one typed
  // D-Bus parameter, so nothing in it can become a flag or a command.
  function notify(reading) {
    notifyProcess.running = false
    notifyProcess.command = [
      "omarchy-notification-send",
      "-g", Model.indicatorGlyph(reading.indicator),
      "-u", Model.notificationUrgency(reading.indicator),
      "--app-name", "omacheckstatus",
      Model.notificationHeadline(reading),
      Model.notificationBody(reading),
      "--exec", "xdg-open", root.statusPageUrl
    ]
    notifyProcess.running = true
  }

  Process {
    id: fetchProcess
    // -f so an HTTP error is a non-zero exit rather than an error page we'd
    // try to parse; -sS keeps the progress meter off but the message on.
    command: [
      "curl", "-fsS",
      "--max-time", "20",
      "-H", "Accept: application/json",
      root.endpoint
    ]

    // Exit and stream-finished have no guaranteed order, so each collector
    // also parks its text on the service and onExited reads whichever of the
    // two landed.
    stdout: StdioCollector { id: fetchOut; waitForEnd: true; onStreamFinished: root._body = text }
    stderr: StdioCollector { id: fetchErr; waitForEnd: true; onStreamFinished: root._stderr = text }

    onExited: function(exitCode) {
      root.loading = false
      var body = String(fetchOut.text || root._body || "")
      var errorText = String(fetchErr.text || root._stderr || "").trim()
      root._body = ""
      root._stderr = ""
      if (exitCode !== 0) {
        root.lastError = errorText || ("curl exited " + exitCode)
        return
      }
      try {
        var reading = Model.parseSummary(body)
        if (reading.error) root.lastError = reading.error
        else root.apply(reading)
      } catch (e) {
        root.lastError = "Could not read the status feed"
      }
    }
  }

  Process {
    id: notifyProcess
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A laptop that slept through several intervals wakes up with a stale
  // reading and a timer that won't fire for another five minutes. Nudge it
  // whenever more than one interval has elapsed since the last attempt.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: {
      if (root.lastAttemptMs === 0) return
      if (Date.now() - root.lastAttemptMs > root.refreshIntervalSec * 2000) root.refresh()
    }
  }
}
