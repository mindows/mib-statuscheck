# Feed ingestion guide

How to read each provider's status feed and turn it into the plugin's
reading. This is the reference for v2.3 of the [roadmap](../ROADMAP.md).

Every endpoint, field and enum value below was fetched live on **2026-09-23**,
unless it is marked **unverified**. Unverified means the value comes from
documentation or source code, and no live sample showing it was available
that day.

## Summary

| Provider | Endpoint(s) | Format | Adapter needed? | Main trap |
|---|---|---|---|---|
| Atlassian Statuspage | `/api/v2/summary.json` | JSON | no, this is today's parser | `indicator` can say `none` during an open incident |
| incident.io | `/api/v2/summary.json` | Statuspage-compatible JSON | **no**, works today | `incidents` is `null` rather than `[]` |
| Slack | `slack-status.com/api/v2.0.0/current` | JSON | yes, S | component list is a fixed set of 14 names |
| Heroku | `status.heroku.com/api/v4/current-status` | JSON | yes, S | `resolved` is false on resolved incidents; stale maintenance |
| Instatus | `/v3/summary.json` + `/v3/components.json` | JSON | yes, S | needs two requests; docs and live shape differ |
| Better Stack | `/index.json` | JSON:API | yes, S–M | `ends_at` is null on resolved reports |
| Google Workspace | `google.com/appsstatus/dashboard/incidents.json` | JSON | yes, M | ~400 KB per poll; product filter needed |
| Google Cloud | `status.cloud.google.com/incidents.json` | JSON | yes, M | needs product *and* region filters |
| AWS | `health.aws.amazon.com/public/currentevents` | JSON in **UTF-16** | yes, M | red for 6+ months without a region filter |
| Azure | `azure.status.microsoft/en-us/status/feed/` | RSS | yes, M | no severity, no components; low fidelity |
| Uptime Kuma | `/api/status-page/<slug>` + `/api/status-page/heartbeat/<slug>` | JSON | yes, M | unverified live; field renamed in v2 |
| Generic RSS/Atom | `/history.rss`, `/history.atom` | XML | maybe, for #11 only | no state field; cannot say "down now" |

Two findings change the roadmap:

1. **incident.io needs no adapter.** Its pages serve a Statuspage-compatible
   `summary.json`, and the current parser reads Linear correctly today (run
   through `parseSummary`, it gives `pageName: "Linear"`). HashiCorp and
   Zapier, both existing presets, have already moved to incident.io, and
   they keep working through the same compatibility endpoint.
2. **The AWS region filter is required, not optional.** Right now AWS lists
   two region-wide disruptions (UAE `me-central-1` and Bahrain `me-south-1`)
   that have been open since 2026-03-01 and 2026-03-02, each affecting 140+
   services. An unfiltered AWS row would have been red for six months.

---

## The target: the reading shape

Each adapter produces the object `Model.parseSummary` returns today, so the
panel, notifications and severity logic do not change:

```js
{
  indicator: "none" | "maintenance" | "minor" | "major" | "critical",
  description: "All Systems Operational",   // provider's own wording
  pageName: "GitHub",                       // adopted as the default label
  incident: {                               // headline event, or null
    kind: "incident" | "maintenance",
    id, name, status, impact,
    url,                                    // deep link, "" if none
    startedAt, updatedAt, scheduledUntil,   // ISO strings, "" if none
    updateId, updateBody, updateAt,         // newest update, plain text
    affected: ["API Requests", ...]         // component names
  },
  incidentCount: 1,                         // open incidents
  maintenanceCount: 0,                      // in-progress maintenances
  degraded: [{ name, status, label }]       // non-operational components
}
```

Component `status` uses Statuspage's vocabulary, which `componentStatusLabel`
already understands: `operational`, `degraded_performance`,
`partial_outage`, `major_outage`, `under_maintenance`. Adapters translate
into it.

`signatureOf` builds the change-detection key from this shape. As long as an
adapter fills the same fields, a new provider gets notifications for free.
The one rule is to leave anything that ticks on its own (fetch time,
`lastBuildDate`, Heroku's `updated_at` on untouched items) out of the
reading, or every poll will notify.

### Implementation notes (for #12)

- **Store the adapter per service.** Save it on the service entry
  (`"adapter": "slack"`), decided at add time by the probe, so polls never
  guess. Entries without it default to `statuspage`, so existing configs
  keep working.
- **Some adapters need more than one request.** Instatus needs 2 and Kuma
  needs 2. The batch loop's `===FEED <url>===` framing already allows
  several bodies per tick. Key them as `<service url>#<part>` and hand the
  adapter every part.
- **AWS is UTF-16.** Decode it in the fetch script (`iconv -f UTF-16 -t
  UTF-8`; iconv comes with glibc on Arch), so `parseBatch` stays line-based
  and UTF-8. `bottelet.is-it-down` does the same and lists `iconv` as a
  dependency.
- **The Google feeds are large** (Workspace ~400 KB, Cloud ~170 KB). At the
  default 5-minute interval that is fine; below 5 minutes, consider a
  separate interval for those feeds.
- **Probe order for pasted URLs (#14).** Check known hosts first (Slack,
  Heroku, AWS, Google, Azure). Then try Statuspage/incident.io
  `/api/v2/summary.json`, then Instatus `/summary.json` (a `page.status` of
  `UP`/`HASISSUES`/`UNDERMAINTENANCE`), then Better Stack `/index.json`
  (`data.type == "status_page"`), then Kuma. Statuspage goes first because
  it is the most common, and because other platforms imitate it.

---

## Atlassian Statuspage (current parser)

**Endpoint:** `GET <page>/api/v2/summary.json`

**Also available:**

| Endpoint | Returns | Use for |
|---|---|---|
| `/api/v2/incidents.json` | last 50 incidents, resolved ones included | #11, "recently resolved" |
| `/api/v2/scheduled-maintenances/upcoming.json` | upcoming maintenances only | not needed, see below |
| `/history.rss`, `/history.atom` | incident history as XML | not needed |

`summary.json` already includes upcoming *and* in-progress maintenances in
`scheduled_maintenances`, so roadmap item #2 needs no extra request. Filter
on `status == "scheduled"` and read `scheduled_for` / `scheduled_until`.

**Live sample** (GitHub, 2026-09-23, trimmed):

```json
{
  "status": { "indicator": "none", "description": "All Systems Operational" },
  "incidents": [{
    "id": "8zc63m64hy36",
    "name": "Incident across several services",
    "status": "investigating",
    "impact": "minor",
    "started_at": "2026-09-23T10:11:12.836Z",
    "shortlink": "https://stspg.io/m1ps7yrhp4n8",
    "components": [{ "name": "API Requests", "status": "operational" }],
    "incident_updates": [{
      "status": "investigating",
      "body": "Users may experience stale Project search results. ...",
      "display_at": "2026-09-23T13:35:44.672Z",
      "affected_components": [{ "code": "brv1bkgrwx7q", "name": "API Requests",
                                "old_status": "operational", "new_status": "operational" }]
    }]
  }]
}
```

**Enums:**

| Field | Values |
|---|---|
| `status.indicator` | `none`, `minor`, `major`, `critical`, `maintenance` |
| incident `impact` | `none`, `minor`, `major`, `critical`, `maintenance` |
| incident `status` | `investigating`, `identified`, `monitoring`, `resolved`, `postmortem` |
| maintenance `status` | `scheduled`, `in_progress`, `verifying`, `completed` |
| component `status` | the five listed under the reading shape |

Component groups have `group: true` and are containers, so skip them (the
parser already does). Components carry `group_id` to find their parent,
which the #9 page uses to collapse groups.

**Trap (live today):** GitHub has an open `minor` incident while
`status.indicator` is `none`, because every component still reports
operational. Right now the row reads "Operational" and still shows the
incident's title. **Fix:** set `indicator = worst(status.indicator, impact of
each open incident)`. This belongs in v2.1.

---

## incident.io

**No adapter needed.** Every incident.io page tested serves the Statuspage
contract at `/api/v2/summary.json`, `/api/v2/incidents.json`,
`/api/v2/status.json` and `/api/v2/components.json`.

Hosts confirmed on incident.io by their `/proxy/<host>` response (2026-09-23):

- status.openai.com
- linearstatus.com
- status.incident.io
- status.hashicorp.com
- status.zapier.com
- status.miro.com
- status.clerk.com
- status.elevenlabs.io
- status.bolt.new
- status.lovable.dev
- status.cohere.com

**How it differs from real Statuspage** (the parser already tolerates all of
these):

| Field | Statuspage | incident.io compat |
|---|---|---|
| `incidents`, `scheduled_maintenances` when empty | `[]` | `null` |
| incident `components` | list | missing, so `affected` is always empty |
| incident `shortlink` | URL | `null`, so fall back to the page URL |
| component `group` | present | missing, so the feed is always flat |
| `/api/v2/scheduled-maintenances/upcoming.json` | 200 | **404**, so read `summary.json` only |

**Live compat incident** (OpenAI `/api/v2/incidents.json`, resolved
2026-09-23):

```json
{
  "id": "01M36RMC01ZFWQ861WYJKC4XE1",
  "name": "Elevated Error Rates for ChatGPT across Plus and Pro plans.",
  "status": "resolved", "impact": "minor",
  "created_at": "2026-09-23T09:13:00Z", "resolved_at": "2026-09-23T09:54:16Z",
  "incident_updates": [{ "body": "All impacted services have now fully recovered.",
                          "status": "resolved", "display_at": "2026-09-23T09:54:16Z" }]
}
```

Values seen across OpenAI's last 25 incidents: `impact` was `none`, `minor`
or `major`; update `status` was `investigating`, `identified`, `monitoring`
or `resolved`.

**Optional richer endpoints** (only worth using if incidents need affected
components, which the compat feed lacks):

- `GET <page>/proxy/<host>` returns `{ summary: { name, public_url,
  components[], structure, affected_components[], ongoing_incidents[],
  scheduled_maintenances[] } }`.
- `GET <page>/api/v1/summary` (the documented "Widget API") returns `{
  page_title, page_url, ongoing_incidents[], in_progress_maintenances[],
  scheduled_maintenances[] }`.
- **Unverified:** what their incident objects look like. No incident.io page
  had anything ongoing on 2026-09-23, and the docs publish no schema.
  Capture one during a live incident before building on it.

---

## Slack

**Endpoints:**

- `GET https://slack-status.com/api/v2.0.0/current`, the live state
- `GET https://slack-status.com/api/v2.0.0/history`, the last ~37 events,
  for #11

**Live sample** (current, healthy):

```json
{ "status": "ok", "date_created": "2026-09-12T04:04:17-07:00",
  "date_updated": "2026-09-12T13:00:00-07:00", "active_incidents": [] }
```

**When something is active** (from Slack's docs; the history entries match
this item shape):

```json
{
  "status": "active",
  "active_incidents": [{
    "id": "546",
    "date_created": "2018-09-07T14:35:00-07:00",
    "date_updated": "2018-09-07T18:34:15-07:00",
    "title": "Slack's forwarding email feature is failing for some customers",
    "type": "incident",
    "status": "active",
    "url": "https://slack-status.com/2018-09/7dea1cd14cd0f657",
    "services": ["Apps/Integrations/APIs"],
    "notes": [{ "body": "<p>...</p>", "date_created": "..." }]
  }]
}
```

**Enums:**

| Field | Values |
|---|---|
| top-level `status` | `ok`, `active` |
| incident `type` | `incident`, `notice`, `outage` |
| incident `status` | `active`, `resolved`, `scheduled`, `completed`, `cancelled` |
| `services` (the component list) | Login/SSO, Messaging, Notifications, Search, Workspace/Org Administration, Canvases, Connectivity, Files, Huddles, Apps/Integrations/APIs, Workflows, Posts/Files, Calls, Link Previews |

**Mapping:**

| Slack | Reading |
|---|---|
| `status: ok` | `indicator: none` |
| `type: outage` | `major` |
| `type: incident` | `minor` |
| `type: notice` | `none`, but set `incident` so the row shows it as information |
| `status: scheduled` / `completed` | maintenance (`scheduled` is upcoming) |

- `pageName` is `"Slack"`, a constant.
- `degraded`: the `services` of every active item, with a label from its
  type.
- `url`: the item's `url`.
- `updateBody`: the newest note's `body`, with HTML stripped.

**Traps:**

- Timestamps use a local offset (`-07:00`), not `Z`. `Date.parse` handles
  that, but never compare them as strings.
- The last 37 history entries were all `type: incident`. Maintenance
  appears rarely, if at all.

---

## Heroku

**Endpoints:**

- `GET https://status.heroku.com/api/v4/current-status`
- `GET https://status.heroku.com/api/v4/incidents?limit=N`, the history,
  for #11

**Live sample** (trimmed):

```json
{
  "status": [ { "system": "Apps", "status": "green" },
              { "system": "Data", "status": "green" },
              { "system": "Tools", "status": "green" } ],
  "incidents": [],
  "scheduled": [{
    "id": 2959, "title": "Heroku Platform Maintenance",
    "state": "upcoming", "resolved": false,
    "created_at": "2026-07-15T17:00:24.339Z",
    "full_url": "https://status.heroku.com/incidents/2959",
    "systems": [ { "name": "Apps", "status": "green", "services": ["Apps"] } ],
    "tags": ["EMEA", "NA", "APAC"],
    "updates": [
      { "created_at": "2026-07-15T21:23:52.796Z", "contents": "Maintenance is complete",
        "update_type": "scheduled" },
      { "created_at": "2026-07-15T17:00:24.339Z",
        "contents": "On July 15, 2026, starting at 17:00 UTC ... (3 hours) ...",
        "update_type": "scheduled" } ]
  }]
}
```

**Mapping:**

| Field | Reading |
|---|---|
| `status[].status`: `green` / `yellow` / `red` | `none` / `minor` / `major`, taking the worst system |
| `status[]` | the components (Apps, Data, Tools), with `yellow` → `degraded_performance` and `red` → `major_outage` |
| `incidents[]` | open incidents; headline `title`, `url` = `full_url` |
| `updates[0].contents` | `updateBody` (updates come newest first) |
| `tags` | regions (EMEA / NA / APAC), usable later for a region filter |

**Traps:**

- **`resolved` is unreliable.** Incident 2963 has `state: "resolved"` and
  `resolved: false` at the same time. Use `state`, and treat anything
  other than `resolved` as open.
- **`scheduled[]` holds stale entries.** Maintenance 2959 still says
  `state: "upcoming"` two months after its own update said "Maintenance is
  complete". The window appears only in prose. So never raise `maintenance`
  from `scheduled[]`; derive maintenance from the systems' colors only, and
  at most show `scheduled[]` as a dim "announced" line.
- The only `state` value seen was `resolved`. Assume
  `investigating`/`identified`/`monitoring` exist (**unverified**).

---

## Instatus

**Endpoints** (the page is usually on a custom domain):

- `GET <page>/v3/summary.json`: page status plus active incidents and
  maintenances
- `GET <page>/v3/components.json`: components (a second request)
- `GET <page>/summary.json`: the legacy form, with the page status only.
  Useful for detection.

**Live sample** (Wistia, healthy; `/v3/summary.json` and `/summary.json`
were identical):

```json
{ "page": { "name": "Wistia", "url": "https://status.wistia.com", "status": "UP" } }
```

`activeIncidents` / `activeMaintenances` are **left out entirely** when
empty.

**With activity** (from Instatus's public-API page, not seen live):

```json
{
  "page": { "name": "...", "url": "...", "status": "HASISSUES" },
  "activeIncidents": [{ "id": "...", "name": "We're facing an issue with our API",
    "started": "2022-06-11T18:55:50Z", "status": "INVESTIGATING",
    "impact": "MAJOROUTAGE", "url": "https://.../incident/...", "updatedAt": "..." }],
  "activeMaintenances": [{ "id": "...", "name": "Database maintenance",
    "start": "2022-06-11T18:55:54Z", "status": "NOTSTARTEDYET",
    "duration": "60", "url": "...", "updatedAt": "..." }]
}
```

**Components** (live, Wistia `/v3/components.json`):

```json
{ "components": [ { "id": "cm86c68hh003drlefrrklqlw1", "name": "Group Record",
    "description": "", "status": "OPERATIONAL", "group": null } ] }
```

The docs show a bare array with `isParent` / `children`, but the live
response is an object with `group`. Accept both.

**Enums and mapping:**

| Instatus | Values | Reading |
|---|---|---|
| `page.status` | `UP`, `HASISSUES`, `UNDERMAINTENANCE` | `none`, (worst below), `maintenance` |
| incident `impact` / component `status` | `OPERATIONAL`, `DEGRADEDPERFORMANCE`, `PARTIALOUTAGE`, `MAJOROUTAGE` | `none`, `minor`, `minor`, `major` |
| incident `status` | `INVESTIGATING`, `IDENTIFIED`, `MONITORING`, `RESOLVED` | lowercase and pass through |
| maintenance `status` | `NOTSTARTEDYET`, `INPROGRESS`, `COMPLETED` | `scheduled`, `in_progress`, `completed` |

Component status becomes Statuspage vocabulary by lowercasing and adding
underscores, e.g. `PARTIALOUTAGE` → `partial_outage`.

**Traps:**

- `status.instatus.com` is **not** Instatus's own status page. On
  2026-09-23 it returned a customer's demo ("Prakrit's Pro Music"), so
  never use it as a test fixture.
- Instatus lists no `critical` impact. Its worst level maps to `major`.

---

## Better Stack

**Endpoint:** `GET <page>/index.json` (JSON:API, ~47 KB; the size comes
from 90 days of per-resource history)

**Live sample** (status.betterstack.com, trimmed):

```json
{
  "data": { "id": "133002", "type": "status_page",
    "attributes": { "company_name": "Better Stack", "aggregate_state": "operational",
                    "announcement": null, "timezone": "UTC" } },
  "included": [
    { "type": "status_page_section", "id": "104771",
      "attributes": { "name": "Better Stack ", "position": 0 } },
    { "type": "status_page_resource", "id": "4018902",
      "attributes": { "public_name": "Better Stack", "status": "operational",
        "status_page_section_id": 104771, "availability": 1.0,
        "status_history": [ { "day": "2026-06-26", "status": "operational",
                              "downtime_duration": 0, "maintenance_duration": 0 } ] } },
    { "type": "status_report", "id": "1050825",
      "attributes": { "title": "Delayed data processing in the Europe region",
        "report_type": "manual", "starts_at": "2026-09-04T13:50:00.000Z",
        "ends_at": null, "aggregate_state": "resolved",
        "affected_resources": [ { "status_page_resource_id": "4188758", "status": "resolved" } ] },
      "relationships": { "status_updates": { "data": [ { "id": "5709883", "type": "status_update" } ] } } },
    { "type": "status_update", "id": "5709883",
      "attributes": { "message": "Processing of new data in the Europe region is starting to recover. ...",
        "published_at": "2026-09-04T19:53:00.000Z",
        "affected_resources": [ { "status_page_resource_id": "4188758", "status": "degraded" } ] } }
  ]
}
```

**Mapping:**

| Field | Reading |
|---|---|
| `data.attributes.company_name` | `pageName` |
| `aggregate_state`: `operational` / `degraded` / `downtime` / `maintenance` | `none` / `minor` / `major` / `maintenance` |
| `status_page_resource` | components: `public_name`, with `status_page_section_id` → section name as the group |
| resource `status` | `operational`, `degraded` → `degraded_performance`, `downtime` → `major_outage`, `maintenance` → `under_maintenance`, `not_monitored` → skip it |
| `status_report` with `aggregate_state != "resolved"` | open incident; `report_type` tells incident from maintenance |
| newest `status_update` (by `published_at`) linked from the report | `updateBody` |

**Traps:**

- **`ends_at` is null on a resolved report**, as in report 1050825 above.
  Use `aggregate_state`, never `ends_at`.
- Values seen live: `aggregate_state` was `operational` or `resolved`;
  resource status was `operational` or `not_monitored`; `report_type` was
  `manual`. The values `degraded`, `downtime` and `maintenance`, and the
  maintenance `report_type`, are **unverified** (no incident was live).
- Bonus: `status_history` has 90 days of daily status per resource. That
  would make "Later: 90-day uptime bars" nearly free for Better Stack
  pages.

---

## Google Workspace

**Endpoints:**

- `GET https://www.google.com/appsstatus/dashboard/incidents.json`, ~400 KB:
  46 incidents, open and closed
- `GET https://www.google.com/appsstatus/dashboard/products.json`, 37
  products (`{ products: [ { title, id } ] }`). Fetch it once at add time
  for the #9 picker.

**Live sample** (an open Gmail incident, 2026-09-23, trimmed):

```json
{
  "id": "B5V4MfnVp97nxoTYbxdX", "number": "9353823205405529898",
  "begin": "2026-09-18T05:00:00+00:00", "end": null,
  "created": "2026-09-22T21:38:51+00:00", "modified": "2026-09-23T03:05:44+00:00",
  "external_desc": "**Title:**\nGmail Android App users on the latest Gmail Android release may exper...",
  "severity": "low", "status_impact": "SERVICE_INFORMATION",
  "service_key": "prPt2Yra2CbGsbEm9cpC", "service_name": "Gmail",
  "affected_products": [ { "title": "Gmail", "id": "prPt2Yra2CbGsbEm9cpC" } ],
  "most_recent_update": { "when": "2026-09-23T02:56:03+00:00",
    "status": "SERVICE_INFORMATION", "text": "**Title:**\n..." },
  "updates": [ ... ], "uri": "..."
}
```

**Enums and mapping:**

| Field | Values | Reading |
|---|---|---|
| open vs closed | `end == null` means open | open incident |
| `status_impact` | `SERVICE_INFORMATION`, `SERVICE_DISRUPTION`, `SERVICE_OUTAGE` | `none` (show as info), `minor`, `major` |
| `most_recent_update.status` | above, plus `AVAILABLE` | `AVAILABLE` = recovered |
| `severity` | `low`, `medium`, `high` | tie-break only |

- `pageName` is `"Google Workspace"`, a constant.
- Components are `affected_products[].title`, filtered by the ids the user
  picked.
- `updateBody` is `most_recent_update.text`, a Markdown string, so strip
  the `**` marks.
- `url` is `https://www.google.com/appsstatus/dashboard/` + `uri`.

**Traps:**

- There is no "all clear" field. Operational means *no open incident
  touches the selected products*.
- The feed is history, not state, so filter on `end == null` before
  anything else.

---

## Google Cloud

**Endpoints:**

- `GET https://status.cloud.google.com/incidents.json` (~170 KB; 6 recent
  incidents on 2026-09-23)
- `GET https://status.cloud.google.com/products.json` (213 products, `{
  products: [ { title, id, current_title } ] }`)

**Schema:** the same as Google Workspace, plus location fields:

```json
{
  "begin": "2026-09-01T14:44:00+00:00", "end": "2026-09-01T18:52:00+00:00",
  "severity": "medium", "status_impact": "SERVICE_DISRUPTION",
  "service_name": "Multiple Products",
  "affected_products": [ { "title": "AlloyDB for PostgreSQL", "id": "fPovtKbaWN9UTepMm3kJ",
                           "current_title": "AlloyDB for PostgreSQL" } ],
  "currently_affected_locations": [],
  "previously_affected_locations": [ { "title": "Iowa (us-central1)", "id": "us-central1" } ]
}
```

The mapping is the same as Workspace. The filter is **product ∩
location**: an incident counts only if it touches a picked product *and*,
when regions are picked, one of `currently_affected_locations[].id`.

**Trap:** `service_name` is often `"Multiple Products"`, so always read
`affected_products`.

---

## AWS

**Endpoint:** `GET https://health.aws.amazon.com/public/currentevents`

- The content type is `application/json;charset=utf-16`, so **decode before
  parsing** (`iconv -f UTF-16 -t UTF-8`).
- The body is an empty array when nothing is open.
- `/public/historyevents` returns **404**, so AWS has no history source for
  #11.

**Live sample** (one of two open events, 2026-09-23, trimmed):

```json
{
  "date": "1772369485",
  "arn": "arn:aws:health:me-central-1::event/MULTIPLE_SERVICES/AWS_MULTIPLE_SERVICES_OPERATIONAL_ISSUE/...",
  "region_name": "UAE",
  "status": "3",
  "service": "multipleservices-me-central-1",
  "service_name": "Multiple services",
  "summary": "Region Availability",
  "event_log": [ { "summary": "Increased Error Rates",
                   "message": "We are investigating issues with AWS services in the ME-CENTRAL-1 Region.",
                   "status": 1, "timestamp": 1772369485 } ],
  "impacted_services": { "cloudwatchsynthetics-me-central-1":
                         { "service_name": "Amazon CloudWatch Synthetics", "current": "3", "max": "3" } },
  "impacted_service_status_changes": [ { "service": "acm-pca-me-central-1",
     "service_name": "AWS Private Certificate Authority",
     "previous_status": "0", "current_status": "3", "timestamp": 1772369485 } ]
}
```

**Status codes** (inferred from the payload: logs escalate 1 → 2 → 3, and
services change from `"0"` to `"3"`):

| Code | Meaning | Reading |
|---|---|---|
| `0` | operational / resolved | `none` |
| `1` | informational | `none`, shown as info |
| `2` | degraded | `minor` |
| `3` | disruption | `major` |

- `status` is a **string** at the top level and in `impacted_services`,
  but a **number** in `event_log`. Compare with `Number(x)`.
- `date` and `timestamp` are epoch seconds (strings or numbers), not ISO.
  Convert them to ISO for the reading.
- Region code: take it from the ARN (`arn:aws:health:<region>::`) or from
  the `service` suffix. `region_name` is only a display name ("UAE").
  Global events probably use an empty ARN region (**unverified**).
- Components are `impacted_services[*].service_name`, which is where the
  #9 service filter applies.
- `updateBody` is the `message` of the `event_log` entry with the highest
  `timestamp`.
- `url` is `https://health.aws.amazon.com/health/status` (there are no
  per-event links).

**Required UX:** when AWS is added, ask for regions immediately (the #9
"only these" mode). Without that, the row is permanently red: the two
Middle East disruptions above have been open since March, and were last
updated 2026-09-15.

---

## Azure

**Endpoint:** `GET https://azure.status.microsoft/en-us/status/feed/` (RSS
2.0)

**Live sample** (healthy): a channel with **no `<item>`** elements:

```xml
<rss version="2.0"><channel>
  <title>Azure Status</title>
  <link>https://azure.status.microsoft/en-us/status/</link>
  <lastBuildDate>Wed, 23 Sep 2026 15:42:00 Z</lastBuildDate>
</channel></rss>
```

**Mapping:**

- No items means `none`. Any item means `minor`, because the feed carries
  no severity.
- Headline: the newest item's `<title>`, `<description>` (HTML, stripped)
  and `<link>`.

**Traps:**

- The item shape is **unverified**; nothing was active on 2026-09-23.
  Record a live one before shipping.
- No components, no regions (except in prose) and no maintenance signal.
  This is the weakest adapter, so ship it last and label the row's detail
  "Azure's feed gives no severity".
- `lastBuildDate` changes on every build. Keep it out of `signatureOf`.

---

## Uptime Kuma (self-hosted)

**Unverified live.** There is no public demo any more (`demo.kuma.pet` →
404). Everything below is from `louislam/uptime-kuma` master on
2026-09-23: `server/routers/status-page-router.js`,
`server/model/status_page.js`, `server/model/heartbeat.js` and
`src/util.ts`.

**Endpoints** (the user pastes `https://host[:port]/status/<slug>`):

- `GET <host>/api/status-page/<slug>`, cached 5 min server-side
- `GET <host>/api/status-page/heartbeat/<slug>`, cached 1 min

**Shapes:**

```js
// /api/status-page/<slug>
{
  config: { slug, title, description, ... },
  incidents: [ { id, title, content, style, createdDate, lastUpdatedDate, pin } ], // v2: array
  publicGroupList: [ { id, name, weight, monitorList: [ { id, name, type, ... } ] } ],
  maintenanceList: [ ... ]
}
// /api/status-page/heartbeat/<slug>
{
  heartbeatList: { "<monitorId>": [ { status, time, msg: "", ping } ] },  // oldest → newest, ≤100
  uptimeList:    { "<monitorId>_24": 0.998 }
}
```

**Status codes** (`src/util.ts`): `0` DOWN, `1` UP, `2` PENDING, `3`
MAINTENANCE.

**Mapping:**

- Take each monitor's **last** heartbeat.
- Any `0` gives `major` (it's your own box, so down is down), otherwise any
  `2` gives `minor`, otherwise any `3` gives `maintenance`, otherwise
  `none`.
- Components are the monitors, grouped by `publicGroupList[].name`. Map
  `0` → `major_outage`, `2` → `degraded_performance`, `3` →
  `under_maintenance`.
- The headline is the newest pinned incident's `title` and `content`.
- `pageName` is `config.title`.

**Traps:**

- **Version difference:** v2 returns `incidents` (an array). 1.x returned
  `incident` (a single object or `null`). Accept both.
- Homelab instances often run on a port and sometimes plain `http` on the
  LAN. That needs #6 (ports), plus a decision on whether to allow `http`
  for private-range hosts only.
- **Competition:** three Kuma plugins are already on the Omarchy
  marketplace (`daan.uptime-kuma`, `io.github.p145085.uptime-kuma`,
  `scoop.uptime-kuma`). Keep this adapter at the bottom of v2.3.

---

## Generic RSS / Atom

**Available on:**

| Platform | Feeds |
|---|---|
| Statuspage | `/history.rss`, `/history.atom` |
| incident.io | `/history.rss`, `/history.atom`, `/feed.rss` |
| Instatus | `/history.rss` |

**Live item shapes:**

```text
RSS (GitHub history.rss):
  title, description (HTML with update text), pubDate (RFC 822), link, guid

Atom (OpenAI history.atom):
  title, id, link@href, updated (ISO),
  summary/content (HTML, starts "<b>Status: Resolved</b>", lists affected components)
```

**Verdict:** these feeds are *history*, with no machine-readable "down
now" state (incident.io puts it inside HTML). **Don't ship a generic RSS
status adapter.** The only use is as a fallback source for #11 ("recently
resolved") on a platform without a JSON history, and every platform above
has one.

---

## Test fixtures

Save one body per adapter under `tests/fixtures/` (healthy, plus an active
sample whenever one is live) so `Model.js` adapter tests run offline. The
bodies captured for this doc on 2026-09-23 were:

- GitHub with an open minor incident
- OpenAI's resolved incident
- Slack current and history
- Heroku current and incidents
- Instatus (Wistia)
- Better Stack
- Google Workspace with an open Gmail incident
- Google Cloud
- AWS with two open regional events
- Azure (empty)

Recapture them when implementation starts: these files lived in a session
scratchpad and were not committed.
