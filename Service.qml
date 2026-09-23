import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Watches every configured Statuspage feed, keeps the last good reading for
// each, and fires one desktop notification per service whose status changes in
// a way a user would care about.
//
// All feeds are fetched by a single `curl` loop rather than one Process each:
// ten QML processes racing to finish is a lot of moving parts for a background
// poll, and one delimited stream means the whole readings set updates at once.
// The URLs go in as `"$@"` argv, so a hand-edited config can never become a
// command.
Item {
  id: root

  property var settings: ({})
  signal servicesDiscovered(var services)
  // ok=false with reachable=true means the page answered but published no
  // readable Statuspage feed; reachable=false means we never got an answer
  // (offline, DNS, timeout), which says nothing about the page itself.
  signal probeFinished(string url, bool ok, bool reachable, string name)

  readonly property var services: Model.normalizeServices(
    settings && settings.services !== undefined ? settings.services : Model.DEFAULT_SERVICES)
  readonly property int refreshIntervalSec: Model.clampInterval(settings ? settings.refreshIntervalSec : undefined)
  readonly property bool notifyEnabled: !settings || settings.notify !== false

  // url -> reading. Readings survive a failed poll on purpose: a dropped
  // network shouldn't blank out what we know, it should just say so.
  property var readings: ({})
  // url -> signature we last notified about. Empty for a service means its
  // next successful reading is the silent baseline, so adding a service that
  // is already broken does not fire a "status changed" toast.
  property var notified: ({})

  property bool loading: false
  property double lastSuccessMs: 0
  property double lastAttemptMs: 0

  property string _body: ""

  // Readings in configured order, each carrying its service identity, so the
  // panel can bind a Repeater straight to this.
  readonly property var rows: {
    var list = []
    for (var i = 0; i < services.length; i++) {
      var service = services[i]
      var reading = readings[service.url] || ({})
      list.push({
        name: service.name,
        url: service.url,
        indicator: reading.indicator || "",
        description: reading.description || "",
        incident: reading.incident || null,
        incidentCount: reading.incidentCount || 0,
        degraded: reading.degraded || [],
        error: reading.error || ""
      })
    }
    return list
  }

  readonly property string worst: Model.worstIndicator(rows)
  readonly property bool known: worst !== ""
  readonly property bool healthy: known && Model.isHealthy(worst)
  readonly property bool alarming: known && !healthy
  readonly property string glyph: Model.indicatorGlyph(known ? worst : "")
  readonly property string overall: Model.overallText(rows)
  readonly property int affectedCount: Model.affectedCount(rows)

  property bool _pendingRefresh: false

  function refresh() {
    if (fetchProcess.running) {
      // A service was added mid-flight; the in-flight batch has no entry for
      // it, so queue one more round rather than leaving the new row blank
      // until the next tick.
      _pendingRefresh = true
      return
    }
    if (services.length === 0) return
    lastAttemptMs = Date.now()
    loading = true
    var argv = ["bash", "-c", fetchScript, "mib-statuscheck"]
    for (var i = 0; i < services.length; i++) argv.push(Model.endpointFor(services[i].url))
    fetchProcess.command = argv
    fetchProcess.running = true
  }

  // Check a candidate page before it joins the list. Most status pages are not
  // Statuspage — Google, X, Slack and AWS all run their own — and adding one of
  // those would leave a row that can only ever say "unreachable". One request
  // at the moment of adding turns that into an answer.
  property bool probing: false
  property string probeUrl: ""

  function probe(pageUrl) {
    var page = Model.normalizePageUrl(pageUrl)
    if (page === "" || probeProcess.running) return false
    probeUrl = page
    probing = true
    _probeBody = ""
    probeProcess.command = [
      "curl", "-fsSL", "--max-time", "15",
      "-H", "Accept: application/json",
      "--", Model.endpointFor(page)
    ]
    probeProcess.running = true
    return true
  }

  property string _probeBody: ""

  function openPage(url) {
    var page = Model.normalizePageUrl(url)
    if (page !== "") Quickshell.execDetached(["xdg-open", page])
  }

  // -f so an HTTP error is a non-zero exit rather than an error page we would
  // try to parse. Each feed's exit code rides in its own END line, so one
  // unreachable service cannot spoil the rest of the batch.
  readonly property string fetchScript:
    'for url in "$@"; do' +
    '  printf "===FEED %s===\\n" "$url";' +
    '  curl -fsS --max-time 20 -H "Accept: application/json" -- "$url" 2>/dev/null;' +
    '  printf "\\n===END %s===\\n" "$?";' +
    'done'

  function apply(batch) {
    var nextReadings = ({})
    var nextNotified = ({})
    var toNotify = []
    var anyRead = false

    for (var i = 0; i < services.length; i++) {
      var service = services[i]
      var endpoint = Model.endpointFor(service.url)
      var incoming = batch[endpoint]

      // No entry at all (the batch predates a just-added service): keep what
      // we had rather than flashing the row to unknown.
      if (!incoming) {
        if (readings[service.url]) nextReadings[service.url] = readings[service.url]
        if (notified[service.url]) nextNotified[service.url] = notified[service.url]
        continue
      }

      if (incoming.error) {
        // Hold the last good reading and hang the error off it, so the row can
        // show both what we last knew and that it is stale.
        var previous = readings[service.url]
        var merged = ({})
        for (var key in previous) merged[key] = previous[key]
        merged.error = incoming.error
        nextReadings[service.url] = merged
        if (notified[service.url]) nextNotified[service.url] = notified[service.url]
        continue
      }

      nextReadings[service.url] = incoming
      anyRead = true
      var signature = Model.signatureOf(incoming)
      nextNotified[service.url] = signature

      var previousSignature = notified[service.url]
      if (previousSignature === undefined || previousSignature === signature) continue
      toNotify.push({ name: service.name, reading: incoming })
    }

    readings = nextReadings
    notified = nextNotified
    // Only a feed that actually answered counts: a batch where every page was
    // unreachable must not make the footer claim a fresh check.
    if (anyRead) lastSuccessMs = Date.now()

    // Names are what the provider calls itself; adopt them so a pasted URL
    // ends up labelled "GitHub" rather than "Githubstatus".
    adoptDiscoveredNames(nextReadings)

    if (notifyEnabled) for (var n = 0; n < toNotify.length; n++) notify(toNotify[n].name, toNotify[n].reading)
  }

  // Only ever renames, never adds or removes, and only a name we made up from
  // the URL — so a label the user chose, in the panel or by hand, is never
  // replaced by the provider's.
  function adoptDiscoveredNames(currentReadings) {
    var next = []
    var changed = false
    for (var i = 0; i < services.length; i++) {
      var service = services[i]
      var reading = currentReadings[service.url]
      var discovered = reading && !reading.error ? String(reading.pageName || "").trim() : ""
      var preset = Model.presetFor(service.url)
      // A preset's name is ours to keep: "Claude" reads better than the page's
      // own "Claude" / "Anthropic Status" drift, and the user picked the label.
      var derived = service.name === Model.nameFromUrl(service.url)
      if (discovered !== "" && !preset && derived && discovered !== service.name) {
        next.push({ name: discovered, url: service.url })
        changed = true
      } else {
        next.push(service)
      }
    }
    if (changed) servicesDiscovered(next)
  }

  // argv, not a shell string: an incident title or update body is arbitrary
  // remote text, and the notification sender takes each value as one typed
  // D-Bus parameter, so nothing in it can become a flag or a command.
  //
  // Deliberately no `--exec`: Omarchy runs a toast's click action and then
  // dismisses it, so attaching one turns the ordinary click-to-dismiss gesture
  // into "open a browser tab". The toast only announces; the bar icon next to
  // it is how you get to the detail.
  function notify(serviceName, reading) {
    notifyQueue.push([
      "omarchy-notification-send",
      "-g", Model.indicatorGlyph(reading.indicator),
      "-u", Model.notificationUrgency(reading.indicator),
      "-t", String(Model.notificationTimeoutMs(reading.indicator)),
      "--app-name", "mib-statuscheck",
      Model.notificationHeadline(serviceName, reading),
      Model.notificationBody(reading)
    ])
    drainNotifyQueue()
  }

  // Several services can change in one tick. Each toast is its own short-lived
  // process, so send them one at a time instead of overwriting a single
  // Process's command mid-flight.
  property var notifyQueue: []

  function drainNotifyQueue() {
    if (notifyProcess.running || notifyQueue.length === 0) return
    var next = notifyQueue.shift()
    notifyProcess.command = next
    notifyProcess.running = true
  }

  Process {
    id: fetchProcess
    // Exit and stream-finished have no guaranteed order, so the collector also
    // parks its text on the service and onExited reads whichever landed.
    stdout: StdioCollector { id: fetchOut; waitForEnd: true; onStreamFinished: root._body = text }

    onExited: function(exitCode) {
      root.loading = false
      var body = String(fetchOut.text || root._body || "")
      root._body = ""
      root.apply(Model.parseBatch(body))
      if (root._pendingRefresh) {
        root._pendingRefresh = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: notifyProcess
    onExited: root.drainNotifyQueue()
  }

  Process {
    id: probeProcess
    stdout: StdioCollector { id: probeOut; waitForEnd: true; onStreamFinished: root._probeBody = text }

    onExited: function(exitCode) {
      root.probing = false
      var url = root.probeUrl
      var body = String(probeOut.text || root._probeBody || "")
      root._probeBody = ""
      root.probeUrl = ""
      // curl -f exits 22 for an HTTP error status: the server answered, there
      // is just no feed at that path. Every other failure is the network.
      if (exitCode !== 0) {
        root.probeFinished(url, false, exitCode === 22, "")
        return
      }
      try {
        var reading = Model.parseSummary(body)
        if (reading.error) root.probeFinished(url, false, true, "")
        else root.probeFinished(url, true, true, String(reading.pageName || ""))
      } catch (e) {
        root.probeFinished(url, false, true, "")
      }
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.services.length > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A newly added service should show a reading immediately rather than at the
  // next tick. Settings arrive as a whole new object on every change, so
  // `services` is rebuilt even when only a toggle moved; compare the watched
  // URLs so flipping "notify" or renaming a row does not refetch every feed.
  property string _watchedUrls: ""
  onServicesChanged: {
    var urls = services.map(function(service) { return service.url }).join("\n")
    if (urls === _watchedUrls) return
    _watchedUrls = urls
    Qt.callLater(root.refresh)
  }

  // A laptop that slept through several intervals wakes up with a stale set
  // and a timer that won't fire for a while yet.

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
