// Pure helpers for the Claude status widget: parsing the Statuspage summary
// payload, and turning it into the glyphs, labels, and relative times the bar
// button and the popup render. Kept free of QML types so the same functions
// serve the service and the panel.

// Statuspage's overall indicator vocabulary, worst last. `none` means every
// component reports operational.
var INDICATOR_RANK = {
  none: 0,
  maintenance: 1,
  minor: 2,
  major: 3,
  critical: 4
}

function indicatorGlyph(indicator) {
  switch (indicator) {
  case "none": return ""        // check-circle
  case "maintenance": return "" // wrench
  case "minor": return ""       // warning triangle
  case "major": return ""       // exclamation-circle
  case "critical": return ""    // times-circle
  default: return ""            // question-circle — never fetched yet
  }
}

function isHealthy(indicator) {
  return indicator === "none"
}

function isUnknown(indicator) {
  return !indicator || INDICATOR_RANK[indicator] === undefined
}

// Statuspage already ships a human description ("All Systems Operational",
// "Partial System Outage"). Fall back to a label only when it is missing.
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

// --------------------------------------------------------------- time helpers

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
  var days = Math.floor(hours / 24)
  return days + "d ago"
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

// ------------------------------------------------------------------- parsing

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
    scheduledFor: String(raw.scheduled_for || ""),
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

// Turn one summary.json body into the flat state the widget binds to. Throws
// nothing: a malformed payload comes back as `{ error: ... }` so the caller
// can keep showing the last good reading.
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
    incident: headline,
    incidentCount: ongoing.length,
    maintenanceCount: maintenances.length,
    degraded: degraded,
    pageUpdatedAt: String((json.page || {}).updated_at || "")
  }
}

// Identity of a reading for change detection. Anything that would make the
// popup read differently belongs here; anything that ticks on its own (the
// page's updated_at stamp) must not, or every poll would notify.
function signatureOf(state) {
  if (!state) return ""
  var incident = state.incident
  var parts = [
    state.indicator,
    state.description,
    incident ? incident.id : "-",
    incident ? incident.status : "-",
    incident ? incident.updateId : "-"
  ]
  var degraded = state.degraded || []
  for (var i = 0; i < degraded.length; i++) parts.push(degraded[i].name + ":" + degraded[i].status)
  return parts.join("|")
}

// ------------------------------------------------------- notification copy

function notificationUrgency(indicator) {
  if (indicator === "critical" || indicator === "major") return "critical"
  if (indicator === "minor") return "normal"
  return "low"
}

function notificationHeadline(state) {
  return "Claude: " + (state.description || indicatorLabel(state.indicator))
}

// A toast has room for a couple of lines; the popup holds the full update
// text, so trim at a word boundary rather than letting the notification
// daemon elide mid-word.
function truncate(raw, limit) {
  var text = String(raw || "").replace(/\s+/g, " ").trim()
  if (text.length <= limit) return text
  var cut = text.slice(0, limit)
  var space = cut.lastIndexOf(" ")
  if (space > limit * 0.6) cut = cut.slice(0, space)
  return cut.replace(/[.,;:\-]$/, "") + "\u2026"
}

function notificationBody(state) {
  var incident = state.incident
  if (!incident) {
    if (isHealthy(state.indicator)) return "No ongoing incidents."
    var degraded = state.degraded || []
    if (degraded.length === 0) return indicatorLabel(state.indicator)
    var names = []
    for (var i = 0; i < degraded.length; i++) names.push(degraded[i].name + " \u2014 " + degraded[i].label)
    return names.join("\n")
  }
  var meta = []
  if (incident.status !== "") meta.push(titleize(incident.status))
  if (incident.impact !== "" && incident.impact !== "none") meta.push(titleize(incident.impact) + " impact")

  var lines = [incident.name]
  if (meta.length > 0) lines.push(meta.join(" \u00b7 "))
  if (incident.updateBody !== "") lines.push(truncate(incident.updateBody, 180))
  return lines.join("\n")
}
