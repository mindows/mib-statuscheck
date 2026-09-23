# mib-statuscheck roadmap

*Written 2026-09-23, against v2.0.0.*

## Summary

This plugin is already better than most desktop status watchers. It batches
every fetch into one request, fires a toast per service with a silent first
baseline, never treats an unreachable page as an outage, uses theme-native
colors, has full keyboard control, and exposes a scriptable IPC surface.
None of the menu-bar or tray apps reviewed does all of that.

What it lacks is **coverage** and **noise control**. Those are the two things
users of similar tools ask for most, again and again:

1. **Watch the services I actually use.** It only speaks Atlassian
   Statuspage, so Slack, AWS, Google, Azure, Linear and Heroku are missing.
   Across every project reviewed, "add support for X" was the single most
   common kind of issue.
2. **Only tell me about the parts I use.** Examples: "GitHub Actions, not
   Codespaces" or "us-east-1, not every region". Component and severity
   filtering is the main selling point of both commercial aggregators, and
   the most requested fix for alert fatigue.

Everything below is ordered by value per unit of effort, for a desktop bar
widget used by one person. Anything built for teams, SLAs or on-call work has
been cut on purpose (see *Won't do*).

---

## How this was researched

- **117 open-source projects on GitHub, each with 50+ stars**, found by 40
  search queries over the GitHub API. They cover menu-bar/tray watchers,
  Omarchy plugins, bar-widget ecosystems, status aggregators, uptime
  monitors, status-page software (which defines the feeds we read), and
  homelab dashboards. The full list is in the appendix.
- **Top-reacted issues** (sorted by 👍) were pulled for the 16 most relevant
  projects: stts, Instatus Out, statusphere, is-service-up, RepoBar,
  github-statuses, Gatus, Uptime Kuma, Homepage, Glance, Dashy, Upptime,
  Kener, OpenStatus, sahin/status-page, and Nazar (Nazar is under the star
  cutoff, but its issues were read before the cutoff was set). That came to
  about 380 issues.
- **Non-GitHub products** were reviewed for their feature sets: StatusGator,
  IsDown, IncidentHub, StatusSight and Downdetector (commercial
  aggregators), and the Raycast extensions *Is It Alive?*, *AI Provider
  Status* and *GitHub Status*.
- **Every new feed format proposed below was tested live** from this machine
  on 2026-09-23 (see *Verified endpoints*).
- Reddit could not be fetched directly, and web search surfaced almost no
  Reddit threads on this topic. User demand is therefore taken from GitHub
  issues and vendor write-ups instead.

---

## Where we stand

| | mib-statuscheck | stts (macOS, 567★) | Instatus Out (171★) | Is It Alive? (Raycast) | StatusGator / IsDown (SaaS) |
|---|---|---|---|---|---|
| Feed formats | Statuspage only | Many, hardcoded per service | Statuspage + a few | 15 adapters, auto-detected | Thousands, scraped |
| Custom URL | ✅ verified before adding | ❌ (open request, top issue) | ❌ (open request) | ✅ | ✅ |
| Change notifications | ✅ per service, silent baseline | ✅ | ✅ | ❌ | ✅ |
| Component filter | ❌ | ❌ (requested) | ❌ | shows, no filter | ✅ headline feature |
| Severity filter | ❌ | ❌ | ❌ | ❌ | ✅ |
| Upcoming maintenance | ❌ (active only) | ❌ | ❌ | ❌ | ✅ |
| Recent history | ❌ | ❌ | ❌ | ✅ 90-day bars | ✅ |
| Theme-native, keyboard, IPC | ✅ | n/a | n/a | partial | n/a |

**Keep these strengths.** They are real advantages, and several competitors
have open bugs where they get them wrong:

- the batched single request
- the rule that unreachable ≠ down
- toasts that dismiss themselves
- the silent first baseline
- IPC scripting

---

## What users ask for (themes, with evidence)

| Theme | Evidence |
|---|---|
| **More providers / formats** | Most service-request issues in stts are for providers it didn't support (Slack, Okta, Salesforce, GCP, Azure, Railway). Out: "Add Azure", "Google Cloud & DigitalOcean", "Cachet-based", "Hund-based". statusphere: providers for AWS, GCP, incident.io, Status.io, Statuspal, hund.io. is-service-up: "base class for other providers". |
| **Custom / private pages** | stts's top issue: "UI to add user-specific status check" and "custom/private services". Out: "Adding my own status pages?" |
| **Filter to components / regions** | StatusGator and IsDown lead with it. stts: "More granular monitoring of AWS / Azure". github-statuses: "Add filters by region". IncidentHub's guide: GCP has "8000+ region-service combinations". |
| **Severity / lifecycle control** | Gatus: "support for severity" (22), "yellow for non-critical checks" (14). IncidentHub: notify "when it starts, when it ends, or for all updates" depending on how critical a service is. |
| **Maintenance awareness** | Uptime Kuma: "show upcoming scheduled maintenance" (102). Gatus: maintenance windows (18). Kener: scheduled downtime. StatusGator: notification for upcoming maintenance. |
| **Duration & recency** | Uptime Kuma: "Duration of downtime in notifications" (70), "Incident timeline" (70). github-statuses: headline uptime is easy to misread; per-day uptime. |
| **Calm UI when all is well** | Gatus: "collapse all groups if all green" (29), "compact layout", "quick overview". |
| **Uptime Kuma / homelab** | Homepage, Dashy and Glance each have top requests for Kuma widgets. Kuma plasmoid and Stream Deck projects exist. Omarchy users skew toward homelabs. |
| **Quiet hours** | github-statuses: "filter outages by your work hours". |
| **Escape hatch to other tools** | statusphere: webhook notifications. OpenStatus: ntfy.sh notifications. Uptime Kuma: notification templating (72). |

---

## Roadmap

Effort: **S** takes an evening or less, **M** takes a few sessions, and **L**
is a project.

### v2.1: Quick wins (no new formats)

1. **Fix Notion: it *is* watchable.** (S)
   `https://www.notion-status.com` serves a working Statuspage feed. It was
   verified live, and the page name is "Notion". Add it as a preset and
   correct the README, which lists Notion as unsupported.

2. **Show upcoming maintenance.** (S)
   `scheduled_maintenances` is already in `summary.json`, but `parseSummary`
   keeps only the *active* ones. Add a dim line to the row, e.g.
   *"Maintenance in 2d · Sat 02:00–04:00"*. Optionally send a single toast a
   few hours before it starts (off by default).

3. **Put the downtime length in recovery toasts.** (S)
   Example: *"GitHub recovered · down 47m"*. We already have the time the
   bad state started, from the change detection. This is Uptime Kuma's
   top-voted notification request.

4. **Per-service notification level.** (S–M)
   Each service gets a notify setting: `all` / `outages only` (skip minor
   and maintenance) / `off`, stored as a `notifyLevel` key on the service
   entry. The icon still shows the true state; only the toasts are filtered.
   This is the cheapest cure for noise. Until the per-service page (#9)
   exists, set it with `n` on the highlighted row, which cycles the level and
   shows it on the row, or with IPC (`notify GitHub outages`). Keep it out of
   the settings view, which stays global-only (see *Popup space* under v2.2).

5. **Report "Offline" when every feed fails.** (S)
   When every request in a batch fails, the problem is almost certainly this
   machine's connection, not ten providers at once. Say "No network"
   instead of "5 unreachable". *Is It Alive?* is built around exactly this
   question: is the outage on my side or theirs?

6. **Allow hosts with a port.** (S)
   The README already calls this a gap. It unblocks self-hosted Statuspage
   clones and the Uptime Kuma adapter (v2.3). Keep the https requirement.

7. **Sort problems first.** (S)
   In the popup, put non-operational rows at the top, then show the rest in
   the user's order. Gatus's most-voted UI requests are all versions of
   "get healthy things out of my way".

8. **Publish.** (S)
   Push to GitHub as `mib-statuscheck` and submit it to
   `omacom/omarchy-plugin-marketplace`. First run through
   `wbso-ai/omarchy-plugin-security-skill`, which lists the known reasons
   plugins get rejected: the curl argv handling is already right, so check
   the rest.

### v2.2: Components and noise control

**Popup space.** The popup is 380px wide and at most 560px tall, and there
are two views: status and settings. Component counts vary far more than
that space can absorb. Checked 2026-09-23: Claude has 6, GitHub has 12,
Cloudflare has **480** in 8 groups (mostly data-centre locations). A
checklist tucked into either existing view cannot handle the large pages.
So v2.2 **does not widen the panel or grow the settings view**. Instead:

- Actions that apply at a moment (snooze) are **keys on the row**, with no
  settings UI.
- Per-service configuration moves to **its own page** inside the popup.
- The settings view keeps only global things: the service list, the check
  interval, and the notify / hide-when-operational toggles.

9. **Per-service page and component filter.** (M)
   A third popup view, swapped in the same way settings already is, holding
   everything that belongs to one service:

   ```
   ┌ ← GitHub ─────────────────────────┐
   │ Notify   [All ▾]   Muted: no      │
   │ Components   1 of 12 ignored      │
   │ ┌ filter… ────────────────────┐   │
   │ ☑ Git Operations                  │
   │ ☑ API Requests                    │
   │ ☐ Codespaces                      │
   │ ☑ Actions                         │
   │ …  (scrolls)                      │
   └───────────────────────────────────┘
   ```

   - **Ways in:** `e` on the highlighted row, or "Watch settings…" in the
     unfolded detail. In the settings view, clicking a service in the list
     opens the same page. Each settings-list row shows a one-line summary,
     e.g. *"1 ignored · outages only"*.
   - **Space:** the list gets the full 560px and scrolls. The filter field
     appears only on pages with more than ~20 components, and grouped pages
     (Cloudflare) start with their groups collapsed.
   - **Keys:** `j`/`k` to move, `Space` to toggle, `/` to filter, `Esc` to go
     back. The filter field owns the keyboard while focused, as the URL
     field does now.
   - **Ignore list, not an allow list.** Most people want to drop a few
     noisy parts ("I don't use Codespaces"), not list everything they need.
     Store `ignore: ["<component id>", ...]`, matched by id with name as a
     fallback. The common case is one or two clicks, and a component the
     provider adds later is watched by default, which is the safe failure.
   - **"Only these" mode.** A toggle at the top of the list switches to an
     allow list (`only: [...]`) for huge pages like Cloudflare or AWS
     regions, where ignoring 470 locations one by one is absurd.
   - **Effect:** the service's status and notifications are computed from
     the watched components (plus any incident touching them), not from the
     page-wide indicator. When something is filtered out, the row says so,
     in dim text, e.g. *"Operational · 1 ignored issue"*, so the popup
     never hides a real outage without saying it has.
   - The notify level from #4 moves here too.

   This is the most important feature in the commercial tools, and the
   Statuspage feed already carries the component data.

   **Ignore from the incident itself.** (S, with #9)
   In the unfolded detail, each name in the affected-components line is
   clickable: "Ignore Codespaces". It is set up at the moment a component
   annoys you, which is when you care, so many users would never need to
   open the component page at all.

   **CLI path.** (S, with #9)
   IPC commands for dotfiles and power users, in the style of the existing
   ones: `components GitHub` lists the components with ids and marks the
   ignored ones, `ignore GitHub Codespaces` and `unignore GitHub Codespaces`
   change the list, and `only Cloudflare "Frankfurt, Germany - (FRA)"`
   switches to an allow list.

10. **Snooze.** (S)
    A row action, not a setting. `m` on the highlighted row cycles 1h → 4h →
    until it recovers → off. The row shows a muted-bell glyph and
    *"Muted · 52m"*, and the per-service page shows the same state. IPC:
    `snooze GitHub 1h`, `snooze GitHub off`. Snooze silences toasts only;
    the icon and the row still show the true state. This covers the
    quiet-hours request without adding a scheduler.

11. **"Recently resolved" line.** (M)
    If an incident closed within the last 24h, show *"Resolved 2h ago ·
    lasted 40m"* on the row. That way a toast you missed isn't lost. It
    needs `incidents.json`, so fetch it only for the row being unfolded
    (lazily), not on every tick.

### v2.3: Provider adapters (the coverage jump)

12. **Adapter layer in `Model.js`.** (M)
    Each adapter provides `detect(url)`, `endpoint(url)` and
    `parse(text) → reading`, all returning the current reading shape so the
    UI does not change. The batched curl loop stays; each URL just carries
    the adapter id. This is the refactor that makes everything below cheap.

13. **Adapters, in order of demand × ease** (all tested live, see below):

    | Adapter | Unlocks | Effort |
    |---|---|---|
    | incident.io (`/proxy/<host>`) | Linear, and a growing list of AI/dev-tool pages | S |
    | Slack (`slack-status.com/api/v2.0.0/current`) | Slack | S |
    | Heroku (`/api/v4/current-status`) | Heroku | S |
    | Instatus (`/summary.json`) | Instatus-hosted pages | S |
    | Better Stack (`/index.json`) | Better Stack-hosted pages | S |
    | Uptime Kuma status page (`/api/status-page/<slug>` + heartbeat) | the user's **own homelab** | M |
    | Google Workspace (`google.com/appsstatus/dashboard/incidents.json`) | Gmail, Drive, Meet, … | M (large feed, filter by product) |
    | Google Cloud (`status.cloud.google.com/incidents.json`) | GCP | M (needs component filter to be usable) |
    | AWS (`health.aws.amazon.com/public/currentevents`) | AWS | M (UTF-16 body, region filtering) |
    | Azure (RSS feed) | Azure | M (RSS only; no clear "all good" state) |
    | Generic RSS/Atom | anything with a history feed | M (weakest signal, so last) |

    Google Cloud and AWS are only useful once #9 exists. Unfiltered, AWS
    would show red somewhere nearly all the time.

14. **Better URL discovery.** (M)
    When a user pastes `github.com`, `notion.so` or `status.notion.so`,
    follow the redirect and try every adapter's `detect`/probe, so the right
    feed is found without the user knowing about `summary.json`.

### v2.4: Polish and reach

15. **Searchable preset catalog, ~150 entries.** (M)
    A filter field in settings in place of the flat dropdown. Store the
    catalog as data (`presets.json`), not code. Nazar and stts both show that
    a catalog matters, and that catalogs rot. So add the next item with it.
16. **Preset verification script.** (S)
    `node tools/verify-presets.js` probes every preset and fails on a dead
    one. Run it before each release. Add unit tests for `Model.js`
    (normalization, parsing, severity) using the same `new Function`
    pattern the README already shows.
17. **Optional bar label.** (S)
    Off by default, since the icon-only design is intentional. When on, show
    the count or the worst service's name next to the icon when something is
    wrong, e.g. `2` or `GitHub`. The StatusCake Omarchy widget's
    `2/10` pill and most Waybar modules do this.
18. **Raise the cap from 10 to 20.** (S, after #7 and #15)
    Only once problems-first sorting and a catalog exist, so a long list is
    still easy to scan.
19. **`onChange` hook.** (S)
    Run a user-configured command on every status change, with service, old
    state and new state as argv (never through a shell string). One setting
    replaces a pile of integrations: forward to ntfy, flash the keyboard,
    pause a CI job. This is the escape hatch that statusphere's webhook
    request and OpenStatus's ntfy request are asking for.

### Later / maybe

- **90-day uptime bars in the detail view.** It looks nice (*Is It Alive?*
  has it), but Statuspage exposes uptime only through HTML/undocumented
  endpoints, and this is a glanceable widget. Revisit if the history
  endpoints firm up.
- **Per-service poll interval.** It would break the single batched request.
  Only worth doing if a real provider rate-limits a shared 5-minute
  interval.
- **Walker/launcher integration.** An `omarchy-menu`-style picker for
  "open status page of…". IPC already covers keybinds.

### Won't do (over-engineering for a personal bar widget)

- **Crowd-sourced "early warning"** (Downdetector-style, IsDown's user
  reports). There is no free, reliable API, and even the vendors admit it is
  prone to false positives.
- **Active probing of endpoints** (ping/HTTP checks). That is what Uptime
  Kuma and Gatus do well. Read their status pages through the #13 adapter
  instead of rebuilding them.
- **Slack / PagerDuty / email / Teams integrations.** The `onChange` hook
  (#19) covers everyone who needs this.
- **Teams, accounts, SLA reports, incident history database.** These are
  the core of the commercial aggregators, and irrelevant to one person's
  bar.
- **Scraping JS-rendered status pages** (Xbox, PlayStation, Okta, …). It is
  fragile, and Nazar's issues show it becomes endless maintenance. Only
  pages with a stable JSON or RSS feed get supported.
- **Mobile / web companion.**

---

## Verified endpoints (2026-09-23)

| Feed | Result |
|---|---|
| `www.notion-status.com/api/v2/summary.json` | 200 JSON, Statuspage, page name "Notion" |
| `linearstatus.com/proxy/linearstatus.com` | 200 JSON, incident.io (`summary.components`, `ongoing_incidents`, `scheduled_maintenances`) |
| `status.openai.com/proxy/status.openai.com` | 200 JSON, incident.io (Statuspage endpoint also still works) |
| `slack-status.com/api/v2.0.0/current` | 200 JSON |
| `status.heroku.com/api/v4/current-status` | 200 JSON |
| `status.betterstack.com/index.json` | 200 JSON:API |
| `www.google.com/appsstatus/dashboard/incidents.json` | 200 JSON, ~400 KB |
| `status.cloud.google.com/incidents.json` | 200 JSON, ~170 KB |
| `health.aws.amazon.com/public/currentevents` | 200 JSON, **UTF-16** |
| `azure.status.microsoft/en-us/status/feed/` | 200 RSS |
| `status.claude.com/api/v2/scheduled-maintenances/upcoming.json` | 200 JSON |
| `status.x.com/api/v2/summary.json` | no response, X stays unsupported |

---

## Appendix: projects reviewed

All are on GitHub with **50 or more stars** (counts as of 2026-09-23).

**Some GitHub projects were read but are not counted, because they fell
under the cutoff:** Nazar, statuspage-monitor, omarchy-statuscake and
kuma-plasmoid.

### Menu-bar / tray / desktop status apps
| ★ | Project | What it is |
|---|---|---|
| 2194 | steipete/RepoBar | GitHub repo status in the macOS menu bar |
| 1116 | Nightonke/Gitee | macOS status-bar app for GitHub |
| 567 | inket/stts | macOS app monitoring cloud-service status pages; closest analogue |
| 187 | macadmins/SupportCompanion | Mac menu-bar device health |
| 171 | instatushq/out | Monitor services in your menu bar |
| 58 | riveerxd/nightbell | Android uptime monitor, no server |
| 58 | MarlBurroW/Streamdeck-Uptime-Kuma | Kuma monitors on a Stream Deck |
| 56 | dotWee/macOS-PiholeShortcuts | Pi-hole status in the menu bar |
| 53 | HolyMayhem/TorrServe-Silicon | macOS menu-bar service monitor |

### Omarchy ecosystem and Quickshell
| ★ | Project | What it is |
|---|---|---|
| 42810 | omacom/omarchy | The platform |
| 3062 | quickshell-mirror/quickshell | QtQuick shell toolkit the Omarchy shell is built on |
| 563 | aorumbayev/awesome-omarchy | Curated Omarchy resources |
| 548 | thisisgm/flea | Quickshell file manager for Omarchy |
| 543 | akitaonrails/ai-usagebar | Claude/GPT usage widget, Omarchy panel + Waybar |
| 299 | omacom/omarchy-plugin-marketplace | Where this plugin should be submitted |
| 256 | huacnlee/omamail | Omarchy mail plugin |
| 224 | andreumassanet/impasto | Quickshell shell with widgets |
| 214 | stappmus/Omarchy-Spotify | Quickshell Spotify |
| 212 | thisisgm/omarchy-pods | AirPods in the Omarchy bar |
| 195 | HANCORE-linux/Shibumi-Shell | Bar + plugin suite for Omarchy |
| 122 | huacnlee/omarchy-mihoro | Proxy status plugin |
| 114 | nixfred/infomarchy | Wallpaper information desk plugin |
| 86 | Aleph1-9012/Tsugumori | Quickshell HUD widgets |
| 75 | wbso-ai/omarchy-plugin-security-skill | Marketplace rejection pitfalls |
| 68 | finna/herdr-hud | HUD + Omarchy plugin |
| 67 | fross100/omaplug | Plugin manager |
| 64 | brianblakely/omarchy-plugins | Plugin storefront |
| 58 | x3me/omarchy-nexthop | Internet quality monitor plugin |
| 58 | lijiawei0305-pixel/omarchy-mihomo-plugin | Proxy status-bar plugin |
| 52 | tcballard/build-omarchy-plugins | Plugin-building guide |
| 50 | bobby-nicholas/omaland | Hyprland look-and-feel plugin |

### Bar-widget ecosystems (Waybar / Eww / Polybar)
| ★ | Project | What it is |
|---|---|---|
| 12680 | elkowar/eww | Widget system |
| 809 | adi1090x/widgets | Eww widgets |
| 623 | HANCORE-linux/waybar-themes | Omarchy-inspired Waybar themes |
| 403 | dharmx/vile | Eww widgets |
| 368 | bjesus/wttrbar | Waybar weather module |
| 242 | atif-1402/minimal-waybar-themes | Waybar themes with Omarchy modules |
| 153 | LawnGnome/niri-taskbar | Waybar module |
| 138 | Ewwii-sh/ewwii | Eww rewrite |
| 129 | Andeskjerf/waybar-module-pomodoro | Waybar module |
| 115 | coffebar/waybar-module-pacman-updates | Waybar updates module |
| 81 | samjoshuadud/waylandar | Wayland calendar widget |
| 67 | savely-krasovsky/waybar-updates | Waybar updates module |
| 60 | Andeskjerf/waybar-module-music | Waybar module |
| 57 | zzqmt/polycat | Polybar/Waybar module |
| 57 | anufrievroman/polytiramisu | Notifications in Polybar/Waybar |
| 56 | yurihs/waybar-media | Waybar module |
| 52 | lucalabs-de/end | Notification daemon as Eww widgets |
| 50 | wneessen/waybar-weather | Waybar weather module |

### Status aggregators and vendor-status projects
| ★ | Project | What it is |
|---|---|---|
| 3815 | ivbeg/awesome-status-pages | Status page software + public pages list |
| 565 | mrshu/github-statuses | Historical GitHub status record |
| 291 | mtojek/greenwall | Tiny service health dashboard |
| 267 | sahin/status-page | Page of cloud-service statuses |
| 234 | tmobile/kardio | Service health dashboard |
| 223 | OpsiMate/OpsiMate | Alert management across tools |
| 166 | marcopaz/is-service-up | Cloud-service status in one page |
| 125 | salesforce/refocus | Service health visualization |
| 71 | metoro-io/statusphere | Open-source status page aggregator |

### Uptime / health monitors
| ★ | Project | What it is |
|---|---|---|
| 91729 | louislam/uptime-kuma | Self-hosted monitoring |
| 12140 | TwiN/gatus | Status page with alerting |
| 10879 | bluewave-labs/Checkmate | Self-hosted uptime/hardware monitor |
| 10357 | healthchecks/healthchecks | Cron job monitoring |
| 7292 | statping/statping | Status page + monitoring |
| 5986 | alexjustesen/speedtest-tracker | Internet uptime/perf tracker |
| 3590 | fzaninotto/uptime | Remote monitoring app |
| 3458 | sourcegraph/checkup | Health checks + status pages |
| 3275 | operacle/checkcle | Full-stack monitoring |
| 3100 | msgbyte/tianji | Analytics + uptime |
| 2294 | megaease/easeprobe | Lightweight health checking |
| 1982 | brotandgames/ciao | HTTP checks |
| 1948 | valeriansaliou/vigil | Microservices status page + alerts |
| 1194 | 0xfurai/peekaping | Uptime Kuma alternative |
| 1134 | Owloops/updo | Uptime monitoring CLI |
| 1070 | spatie/laravel-uptime-monitor | Uptime + SSL monitor |
| 817 | Alice39s/kuma-mieru | Uptime Kuma dashboard |
| 750 | jonbeckman/solstatus | Uptime monitoring at scale |
| 738 | KSJaay/Lunalytics | Monitoring tool |
| 704 | cloudprober/cloudprober | Active monitoring |
| 634 | kuvasz-uptime/kuvasz | Uptime + SSL monitoring |
| 628 | hyperjumptech/monika | YAML-configured CLI monitor |
| 511 | kOlapsis/maintenant | Docker/K8s/uptime monitoring |
| 475 | maelstrom-cms/odin | Domain monitoring |
| 398 | flo-at/minmon | Minimal monitoring and alarming |
| 109 | likeastore/heartbeat | HTTP/DB health monitoring |
| 73 | SelmiAbderrahim/pulsy.org | Uptime + incident tracking |
| 55 | opsknight-labs/OpsKnight | On-call, incidents, status pages |

### Status-page software (defines the feeds we'd read)
| ★ | Project | What it is |
|---|---|---|
| 17168 | upptime/upptime | GitHub Actions uptime + status page |
| 15249 | cachethq/cachet | Self-hosted status page |
| 9139 | openstatusHQ/openstatus | Status page + monitoring |
| 5175 | rajnandan1/kener | Status pages |
| 3870 | jayfk/statuspage | Status page on GitHub |
| 3829 | lyc8503/UptimeFlare | Serverless status page on Workers |
| 2894 | cstate/cstate | Static status page |
| 2806 | eidam/cf-workers-status-page | Workers status page |
| 2624 | juliomrqz/statusfy | Status page system |
| 1593 | harsxv/tinystatus | Tiny status page |
| 1287 | ks888/LambStatus | Serverless status page |
| 984 | goksan/statusnook | Status page + monitoring |
| 770 | statsig-io/statuspage | Zero-dependency status page |
| 733 | Cyclenerd/static_status | Bash status page generator |
| 627 | paulogr/dstatuspage | Decentralized status page |
| 513 | bderenzo/tinystatus | Static status page generator |
| 482 | VrianCao/Uptimer | Serverless uptime + status page |
| 427 | tadhglewis/issue-status | Status page |
| 408 | server-status-project/server-status | Server status page |
| 280 | mehatab/fettle | GitHub-powered status page |
| 113 | darkpixel/statuspage | Django status page |
| 74 | Status-Page/Status-Page | Open-source Statuspage software |

### Homelab dashboards with status widgets
| ★ | Project | What it is |
|---|---|---|
| 37175 | glanceapp/glance | Dashboard; monitor widget |
| 32815 | gethomepage/homepage | Dashboard; Kuma and status widgets |
| 26549 | lissy93/dashy | Dashboard with status-checking |
| 677 | Monitorr/Monitorr | Service status web app |
| 605 | daledavies/jump | Startpage + status page |
| 260 | enchant97/web-portal | Dashboard with widgets |
| 198 | dougmaitelli/DockDash | Docker/service dashboard |
| 134 | Framerrr/Framerr | Homelab dashboard |
| 93 | samuelloranger/labby | Homelab dashboard |

### Non-GitHub products reviewed
StatusGator, IsDown, IncidentHub, StatusSight, Downdetector, and the Raycast
extensions *Is It Alive?*, *AI Provider Status* and *GitHub Status*.
