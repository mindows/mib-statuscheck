// Pure helpers for the status widget: the preset catalogue, URL normalization,
// parsing the Statuspage summary payload, aggregating several feeds into one
// bar glyph, and the labels, glyphs, and relative times the panel renders.
// Kept free of QML types so the same functions serve the service and the panel.

// ------------------------------------------------------------------- presets

// Every entry below is an Atlassian Statuspage, which exposes the same
// /api/v2/summary.json contract — that is the whole reason a single widget can
// watch them all, and the reason this list is not simply "popular services".
// Each one was checked against that endpoint before being added here.
//
// Notably absent, because they publish no Statuspage feed: Google and its
// properties (YouTube, Gmail, Google Cloud), X/Twitter, Slack, AWS, Azure,
// Notion, Linear and Heroku all run their own status formats. Their pages
// cannot be watched here, which is why a pasted URL is verified before it is
// added rather than silently becoming a row that can only ever error.
//
// Sorted by name, case-insensitively, because that is the order the picker
// shows them in: it groups nothing and promotes nothing, so a reader can
// predict where any given service sits. Nothing may depend on this order —
// see DEFAULT_SERVICES.
var PRESETS = [
  { name: "1Password",    url: "https://status.1password.com" },
  { name: "Airtable",     url: "https://status.airtable.com" },
  { name: "Atlassian",    url: "https://status.atlassian.com" },
  { name: "Bitbucket",    url: "https://status.bitbucket.org" },
  { name: "CircleCI",     url: "https://status.circleci.com" },
  { name: "Claude",       url: "https://status.claude.com" },
  { name: "Cloudflare",   url: "https://www.cloudflarestatus.com" },
  { name: "Cloudinary",   url: "https://status.cloudinary.com" },
  { name: "Coinbase",     url: "https://status.coinbase.com" },
  { name: "Datadog",      url: "https://status.datadoghq.com" },
  { name: "DigitalOcean", url: "https://status.digitalocean.com" },
  { name: "Discord",      url: "https://discordstatus.com" },
  { name: "Docker",       url: "https://www.dockerstatus.com" },
  { name: "Dropbox",      url: "https://status.dropbox.com" },
  { name: "Elastic",      url: "https://status.elastic.co" },
  { name: "Epic Games",   url: "https://status.epicgames.com" },
  { name: "Figma",        url: "https://status.figma.com" },
  { name: "GitHub",       url: "https://www.githubstatus.com" },
  { name: "HashiCorp",    url: "https://status.hashicorp.com" },
  { name: "Jira",         url: "https://jira-software.status.atlassian.com" },
  { name: "MongoDB",      url: "https://status.mongodb.com" },
  { name: "Netlify",      url: "https://www.netlifystatus.com" },
  { name: "npm",          url: "https://status.npmjs.org" },
  { name: "OpenAI",       url: "https://status.openai.com" },
  { name: "Plaid",        url: "https://status.plaid.com" },
  { name: "Proton",       url: "https://status.proton.me" },
  { name: "Reddit",       url: "https://www.redditstatus.com" },
  { name: "Sentry",       url: "https://status.sentry.io" },
  { name: "Shopify",      url: "https://www.shopifystatus.com" },
  { name: "Snowflake",    url: "https://status.snowflake.com" },
  { name: "Squarespace",  url: "https://status.squarespace.com" },
  { name: "Stripe",       url: "https://www.stripestatus.com" },
  { name: "Supabase",     url: "https://status.supabase.com" },
  { name: "Tailscale",    url: "https://status.tailscale.com" },
  { name: "Twilio",       url: "https://status.twilio.com" },
  { name: "Vercel",       url: "https://www.vercel-status.com" },
  { name: "Wikipedia",    url: "https://www.wikimediastatus.net" },
  { name: "Zapier",       url: "https://status.zapier.com" },
  { name: "Zoom",         url: "https://status.zoom.us" }
]

// Ten feeds is already a busy popup, and it is 10 sequential curls per tick.
var MAX_SERVICES = 10

// What a config with no `services` key means. Deliberately not written to
// shell.json on startup: injecting a default before the host has finished
// handing us the real settings would overwrite a list the user already has.
// The default stays implicit until the user changes something.
// Named, not positional: PRESETS is sorted for display, so indexing into it
// would make the default whatever happens to sort first.
var DEFAULT_SERVICES = [{ name: "Claude", url: "https://status.claude.com" }]

var INTERVAL_CHOICES = [
  { value: "300",   label: "Every 5 minutes" },
  { value: "900",   label: "Every 15 minutes" },
  { value: "1800",  label: "Every 30 minutes" },
  { value: "3600",  label: "Every hour" },
  { value: "10800", label: "Every 3 hours" }
]

var MIN_INTERVAL_SEC = 60
var MAX_INTERVAL_SEC = 21600

// An array that came through a QML property is not necessarily a JS Array:
// values read back out of shell.json arrive as a list proxy, which indexes and
// reports `length` correctly but fails `Array.isArray`. Anything array-shaped
// crossing that boundary has to be coerced before it is treated as an array,
// or a perfectly good config silently reads as empty.
function toArray(raw) {
  if (!raw) return []
  if (Array.isArray(raw)) return raw
  if (typeof raw !== "object") return []
  var length = Number(raw.length)
  if (!isFinite(length) || length <= 0) return []
  var out = []
  for (var i = 0; i < length; i++) out.push(raw[i])
  return out
}

function clampInterval(raw) {
  var seconds = Number(raw)
  if (!isFinite(seconds)) return 300
  return Math.max(MIN_INTERVAL_SEC, Math.min(MAX_INTERVAL_SEC, Math.round(seconds)))
}

function intervalLabel(seconds) {
  var value = String(clampInterval(seconds))
  for (var i = 0; i < INTERVAL_CHOICES.length; i++) {
    if (INTERVAL_CHOICES[i].value === value) return INTERVAL_CHOICES[i].label
  }
  // Only reached by a hand-edited interval that matches no choice.
  var minutes = Math.round(clampInterval(seconds) / 60)
  if (minutes < 60) return minutes === 1 ? "Every minute" : "Every " + minutes + " minutes"
  var hours = Math.round(minutes / 60)
  return hours === 1 ? "Every hour" : "Every " + hours + " hours"
}

// ------------------------------------------------------------------ the URLs

// Accepts what a user would actually paste: the page they were looking at, a
// bare host, or the API URL itself. Returns the canonical page URL, or "" when
// it could not be read as one.
function normalizePageUrl(raw) {
  var text = String(raw || "").trim()
  if (text === "") return ""
  text = text.replace(/\s+/g, "")
  text = text.replace(/[#?].*$/, "")
  if (!/^https?:\/\//i.test(text)) text = "https://" + text
  text = text.replace(/\/+$/, "")
  // Paste the feed and we'll take the page it belongs to.
  text = text.replace(/\/api\/v2\/[a-z_\-]+\.json$/i, "")
  text = text.replace(/\/+$/, "")

  var match = text.match(/^https?:\/\/([^\/]+)(\/.*)?$/i)
  if (!match) return ""
  var host = match[1]
  // A host with no dot is a typo, not a status page; so is one with a space,
  // credentials, or a port we'd rather not guess at.
  if (host.indexOf(".") === -1) return ""
  if (!/^[A-Za-z0-9.\-]+$/.test(host)) return ""
  // The URL only ever reaches curl as one argv element, never a shell string,
  // so this is not what stops injection — it is what makes a bad paste fail
  // loudly at the point of entry instead of becoming a feed that can only
  // ever error.
  var path = match[2] || ""
  if (path !== "" && !/^[A-Za-z0-9._~\-\/%]+$/.test(path)) return ""
  return text
}

function endpointFor(pageUrl) {
  var page = normalizePageUrl(pageUrl)
  return page === "" ? "" : page + "/api/v2/summary.json"
}

// A readable fallback name for a URL we have not fetched yet: the host with
// the noise words stripped, so "https://www.githubstatus.com" reads "Github".
function nameFromUrl(pageUrl) {
  var page = normalizePageUrl(pageUrl)
  if (page === "") return ""
  var host = page.replace(/^https?:\/\//i, "").split("/")[0]
  var parts = host.split(".")
  if (parts[0] === "www") parts.shift()
  if (parts[0] === "status" && parts.length > 1) parts.shift()
  var word = String(parts[0] || host).replace(/status$/i, "")
  if (word === "") word = parts.join(".")
  return word.charAt(0).toUpperCase() + word.slice(1)
}

function presetFor(pageUrl) {
  var page = normalizePageUrl(pageUrl)
  for (var i = 0; i < PRESETS.length; i++) {
    if (normalizePageUrl(PRESETS[i].url) === page) return PRESETS[i]
  }
  return null
}

// Sanitize the `services` array coming out of shell.json. Hand-edited config
// is the normal case here, so every field is treated as untrusted: bad URLs
// are dropped, duplicates collapse, and the list is capped.
function normalizeServices(raw) {
  var list = toArray(raw)
  var out = []
  var seen = {}
  for (var i = 0; i < list.length && out.length < MAX_SERVICES; i++) {
    var entry = list[i]
    var url = normalizePageUrl(entry && typeof entry === "object" ? entry.url : entry)
    if (url === "" || seen[url]) continue
    seen[url] = true
    var name = String((entry && entry.name) || "").trim()
    if (name === "") {
      var preset = presetFor(url)
      name = preset ? preset.name : nameFromUrl(url)
    }
    out.push({ name: name, url: url })
  }
  return out
}

function servicesEqual(a, b) {
  var left = normalizeServices(a)
  var right = normalizeServices(b)
  if (left.length !== right.length) return false
  for (var i = 0; i < left.length; i++) {
    if (left[i].url !== right[i].url || left[i].name !== right[i].name) return false
  }
  return true
}

// --------------------------------------------------------------- indicators

// Statuspage's overall indicator vocabulary, worst last. `none` means every
// component reports operational. `unknown` is ours, for a feed we could not
// read — it ranks above healthy but below a confirmed outage, because "we
// don't know" should never outshout "it is down".
var INDICATOR_RANK = {
  none: 0,
  maintenance: 1,
  unknown: 2,
  minor: 3,
  major: 4,
  critical: 5
}

function indicatorGlyph(indicator) {
  switch (indicator) {
  case "none": return ""        // check-circle
  case "maintenance": return "" // wrench
  case "minor": return ""       // warning triangle
  case "major": return ""       // exclamation-circle
  case "critical": return ""    // times-circle
  default: return ""            // question-circle — unread or unreachable
  }
}

function isHealthy(indicator) {
  return indicator === "none"
}

function isUnknown(indicator) {
  return !indicator || INDICATOR_RANK[indicator] === undefined || indicator === "unknown"
}

function indicatorLabel(indicator) {
  switch (indicator) {
  case "none": return "All systems operational"
  case "maintenance": return "Under maintenance"
  case "minor": return "Minor service issue"
  case "major": return "Major service outage"
  case "critical": return "Critical service outage"
  default: return "Status unknown"
  }
}

// One uniform word per state, used for the per-service rows. Providers write
// their own prose ("Partially Degraded Service", "Minor Service Outage"), and
// ten different phrasings stacked in one popup is noise — the row says the
// state in our words, and the expanded detail keeps the provider's own.
function shortStatusLabel(indicator) {
  switch (indicator) {
  case "none": return "Operational"
  case "maintenance": return "Maintenance"
  case "minor": return "Minor issue"
  case "major": return "Major outage"
  case "critical": return "Critical outage"
  default: return "Unreachable"
  }
}

function titleize(raw) {
  var text = String(raw || "").replace(/_/g, " ").trim()
  if (text === "") return ""
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function componentStatusLabel(status) {
  switch (status) {
  case "operational": return "Operational"
  case "degraded_performance": return "Degraded"
  case "partial_outage": return "Partial outage"
  case "major_outage": return "Major outage"
  case "under_maintenance": return "Maintenance"
  default: return titleize(status)
  }
}

// ------------------------------------------------------------- time helpers

function parseTime(iso) {
  if (!iso) return NaN
  var ms = Date.parse(String(iso))
  return isFinite(ms) ? ms : NaN
}

// "just now" / "4m ago" / "3h ago" / "2d ago". `nowMs` is passed in so the
// panel can re-render every tick without the helper reading the clock itself.
function relativeTime(iso, nowMs) {
  var ms = parseTime(iso)
  if (!isFinite(ms)) return ""
  var seconds = Math.round((nowMs - ms) / 1000)
  if (seconds < 0) seconds = 0
  if (seconds < 45) return "just now"
  var minutes = Math.round(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  return Math.floor(hours / 24) + "d ago"
}

function relativeFuture(iso, nowMs) {
  var ms = parseTime(iso)
  if (!isFinite(ms)) return ""
  var seconds = Math.round((ms - nowMs) / 1000)
  if (seconds <= 0) return "now"
  var minutes = Math.round(seconds / 60)
  if (minutes < 60) return "in " + minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return "in " + hours + "h"
  return "in " + Math.floor(hours / 24) + "d"
}

// A popup row has one line for this, so trim at a word boundary rather than
// letting the label elide mid-word.
function truncate(raw, limit) {
  var text = String(raw || "").replace(/\s+/g, " ").trim()
  if (text.length <= limit) return text
  var cut = text.slice(0, limit)
  var space = cut.lastIndexOf(" ")
  if (space > limit * 0.6) cut = cut.slice(0, space)
  return cut.replace(/[.,;:\-]$/, "") + "…"
}

// ------------------------------------------------------------------ parsing

function latestUpdate(updates) {
  if (!Array.isArray(updates) || updates.length === 0) return null
  // The API returns updates newest-first, but sort by display time anyway so a
  // reordered payload still yields the newest note.
  var best = updates[0]
  var bestMs = parseTime(best.display_at || best.created_at)
  for (var i = 1; i < updates.length; i++) {
    var ms = parseTime(updates[i].display_at || updates[i].created_at)
    if (isFinite(ms) && (!isFinite(bestMs) || ms > bestMs)) {
      best = updates[i]
      bestMs = ms
    }
  }
  return best
}

function normalizeIncident(raw, kind) {
  if (!raw) return null
  var update = latestUpdate(raw.incident_updates)
  var affected = []
  var components = Array.isArray(raw.components) ? raw.components : []
  for (var i = 0; i < components.length; i++) {
    var name = String(components[i].name || "").trim()
    if (name !== "") affected.push(name)
  }
  return {
    kind: kind || "incident",
    id: String(raw.id || ""),
    name: String(raw.name || "Unnamed incident"),
    status: String(raw.status || ""),
    impact: String(raw.impact || ""),
    url: String(raw.shortlink || ""),
    startedAt: String(raw.started_at || raw.scheduled_for || raw.created_at || ""),
    updatedAt: String(raw.updated_at || ""),
    scheduledUntil: String(raw.scheduled_until || ""),
    updateId: update ? String(update.id || "") : "",
    updateBody: update ? String(update.body || "").trim() : "",
    updateAt: update ? String(update.display_at || update.created_at || "") : "",
    affected: affected
  }
}

function isOngoingIncident(raw) {
  if (!raw) return false
  if (raw.resolved_at) return false
  return String(raw.status || "") !== "resolved"
}

function isActiveMaintenance(raw) {
  return raw && String(raw.status || "") === "in_progress"
}

// Pick the incident to headline: the most recently updated ongoing one, so a
// pile-up of stale incidents can't bury the live problem.
function pickNewest(list) {
  var best = null
  var bestMs = NaN
  for (var i = 0; i < list.length; i++) {
    var ms = parseTime(list[i].updated_at || list[i].started_at || list[i].created_at)
    if (!best || (isFinite(ms) && (!isFinite(bestMs) || ms > bestMs))) {
      best = list[i]
      bestMs = ms
    }
  }
  return best
}

// Turn one summary.json body into the flat reading a row binds to.
function parseSummary(text) {
  var json = JSON.parse(String(text || ""))
  if (!json || typeof json !== "object") return { error: "Unexpected status payload" }

  var status = json.status || {}
  var indicator = String(status.indicator || "")
  if (isUnknown(indicator)) indicator = "none"

  var ongoing = []
  var incidents = Array.isArray(json.incidents) ? json.incidents : []
  for (var i = 0; i < incidents.length; i++) {
    if (isOngoingIncident(incidents[i])) ongoing.push(incidents[i])
  }

  var maintenances = []
  var scheduled = Array.isArray(json.scheduled_maintenances) ? json.scheduled_maintenances : []
  for (var m = 0; m < scheduled.length; m++) {
    if (isActiveMaintenance(scheduled[m])) maintenances.push(scheduled[m])
  }

  // An incident outranks maintenance: a real outage is what the user opened
  // the popup for.
  var headline = ongoing.length > 0
    ? normalizeIncident(pickNewest(ongoing), "incident")
    : normalizeIncident(pickNewest(maintenances), "maintenance")

  var degraded = []
  var components = Array.isArray(json.components) ? json.components : []
  for (var c = 0; c < components.length; c++) {
    var component = components[c]
    if (component.group === true) continue
    if (String(component.status || "operational") === "operational") continue
    degraded.push({
      name: String(component.name || ""),
      status: String(component.status || ""),
      label: componentStatusLabel(component.status)
    })
  }

  return {
    indicator: indicator,
    description: String(status.description || indicatorLabel(indicator)),
    pageName: String((json.page || {}).name || ""),
    incident: headline,
    incidentCount: ongoing.length,
    maintenanceCount: maintenances.length,
    degraded: degraded
  }
}

// The batch fetcher emits, per service:
//   ===FEED <url>===
//   <body or nothing>
//   ===END <exitCode>===
// One malformed or unreachable feed therefore cannot spoil the others, and a
// body containing our delimiters is only ever read as body text because the
// delimiter lines are matched whole.
function parseBatch(text) {
  var lines = String(text || "").split("\n")
  var out = {}
  var url = null
  var body = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var start = line.match(/^===FEED (.+)===$/)
    if (start) {
      url = start[1]
      body = []
      continue
    }
    var end = line.match(/^===END (-?\d+)===$/)
    if (end && url !== null) {
      var exitCode = Number(end[1])
      if (exitCode !== 0) {
        out[url] = { error: "Could not reach the status page" }
      } else {
        try {
          var reading = parseSummary(body.join("\n"))
          out[url] = reading.error ? { error: reading.error } : reading
        } catch (e) {
          out[url] = { error: "Could not read the status feed" }
        }
      }
      url = null
      body = []
      continue
    }
    if (url !== null) body.push(line)
  }
  return out
}

// Identity of a reading for change detection. Anything that would make the
// popup read differently belongs here; anything that ticks on its own (the
// page's updated_at stamp) must not, or every poll would notify.
function signatureOf(reading) {
  if (!reading) return ""
  if (reading.error) return "error"
  var incident = reading.incident
  var parts = [
    reading.indicator,
    reading.description,
    incident ? incident.id : "-",
    incident ? incident.status : "-",
    incident ? incident.updateId : "-"
  ]
  var degraded = reading.degraded || []
  for (var i = 0; i < degraded.length; i++) parts.push(degraded[i].name + ":" + degraded[i].status)
  return parts.join("|")
}

// -------------------------------------------------------------- aggregation

function worstIndicator(readings) {
  var worst = ""
  var worstRank = -1
  for (var i = 0; i < readings.length; i++) {
    var indicator = readings[i].error ? "unknown" : readings[i].indicator
    if (!indicator) continue
    var rank = INDICATOR_RANK[indicator]
    if (rank === undefined) rank = INDICATOR_RANK.unknown
    if (rank > worstRank) {
      worstRank = rank
      worst = indicator
    }
  }
  return worst
}

function affectedCount(readings) {
  var count = 0
  for (var i = 0; i < readings.length; i++) {
    if (readings[i].error) continue
    if (readings[i].indicator && !isHealthy(readings[i].indicator)) count++
  }
  return count
}

function unreachableCount(readings) {
  var count = 0
  for (var i = 0; i < readings.length; i++) if (readings[i].error) count++
  return count
}

// The hero's one-line verdict across every watched service.
function overallText(readings) {
  if (readings.length === 0) return "No services configured"
  var known = 0
  for (var i = 0; i < readings.length; i++) if (readings[i].indicator || readings[i].error) known++
  if (known === 0) return "Checking…"

  var affected = affectedCount(readings)
  var unreachable = unreachableCount(readings)

  // One service is the common case and deserves the provider's own wording
  // rather than a count of one.
  if (readings.length === 1) {
    if (readings[0].error) return "Status unavailable"
    return readings[0].description || indicatorLabel(readings[0].indicator)
  }

  var parts = []
  if (affected > 0) parts.push(affected + " of " + readings.length + " affected")
  else if (unreachable < readings.length) parts.push("All " + readings.length + " operational")
  if (unreachable > 0) parts.push(unreachable + " unreachable")
  return parts.join(" · ")
}

// ----------------------------------------------------- notification copy

// Never `critical`: Omarchy gives a critical toast a duration of 0, i.e. it
// stays on screen until the user deals with it. A service outage does not
// warrant that — the bar icon is the persistent signal, and the toast is just
// the announcement, so it should always time out on its own.
function notificationUrgency(indicator) {
  if (indicator === "none") return "low"
  return "normal"
}

// Milliseconds on screen. An outage carries three lines worth reading, so it
// gets longer than the daemon's 8s default; a recovery is one line and can go
// at the low-urgency floor. The daemon clamps anything above 30s.
function notificationTimeoutMs(indicator) {
  if (indicator === "none") return 6000
  if (indicator === "minor" || indicator === "maintenance") return 10000
  return 15000
}

function notificationHeadline(serviceName, reading) {
  var name = String(serviceName || "Status")
  if (reading.error) return name + ": status unavailable"
  return name + ": " + (reading.description || indicatorLabel(reading.indicator))
}

function notificationBody(reading) {
  if (reading.error) return reading.error
  var incident = reading.incident
  if (!incident) {
    if (isHealthy(reading.indicator)) return "No ongoing incidents."
    var degraded = reading.degraded || []
    if (degraded.length === 0) return indicatorLabel(reading.indicator)
    var names = []
    for (var i = 0; i < degraded.length; i++) names.push(degraded[i].name + " — " + degraded[i].label)
    return names.join("\n")
  }
  var meta = []
  if (incident.status !== "") meta.push(titleize(incident.status))
  if (incident.impact !== "" && incident.impact !== "none") meta.push(titleize(incident.impact) + " impact")

  var lines = [incident.name]
  if (meta.length > 0) lines.push(meta.join(" · "))
  if (incident.updateBody !== "") lines.push(truncate(incident.updateBody, 180))
  return lines.join("\n")
}
