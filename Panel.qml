import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button plus popup for a set of Statuspage feeds. The button carries the
// worst status across every watched service; the popup lists one compact row
// per service, expanding the one you click to show its ongoing incident. A
// gear flips the same popup into a settings view for the service list and the
// check interval.
Panel {
  id: root
  moduleName: "omacheckstatus"
  ipcTarget: "omacheckstatus"
  manageIpc: false

  // Which service row is expanded, by url. Only one at a time: with ten
  // services, expanding everything is the busy popup we are avoiding.
  property string expandedUrl: ""
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool settingsOpen: false
  property string addError: ""

  // Drives every "4m ago" label. Only ticks while open, so a closed popup
  // costs nothing.
  property double nowMs: Date.now()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool hideWhenOperational: setting("hideWhenOperational", false) === true
  readonly property var rows: monitor.rows

  // Green when everything is operational, amber when exactly one service is
  // not, red when two or more are — see Model.severity for the full rule and
  // for why an unreachable feed is neither.
  readonly property string severity: Model.severity(rows)
  readonly property color severityColor: statusColors.forSeverity(severity)
  readonly property bool atCapacity: rows.length >= Model.MAX_SERVICES

  readonly property string checkedText: {
    if (monitor.loading) return "Checking…"
    if (monitor.lastSuccessMs === 0) return "Not checked yet"
    var stamp = new Date(monitor.lastSuccessMs).toISOString()
    return "Checked " + Model.relativeTime(stamp, root.nowMs)
  }

  readonly property string tooltip: {
    if (rows.length === 0) return "No status pages configured"
    if (!monitor.known) return "Checking service status…"
    var trouble = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (row.error) trouble.push(row.name + " — unreachable")
      else if (row.indicator && !Model.isHealthy(row.indicator))
        trouble.push(row.name + " — " + Model.shortStatusLabel(row.indicator))
    }
    if (trouble.length === 0) return monitor.overall
    return trouble.join("\n")
  }

  // ------------------------------------------------------------- persistence

  // Applied locally first so the popup redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function saveServices(list) {
    persistSettings({ services: Model.normalizeServices(list) })
  }

  // Shared gate for both add paths. Returns the canonical URL, or "" having
  // set the error to show.
  function vetUrl(url) {
    var page = Model.normalizePageUrl(url)
    if (page === "") {
      root.addError = "That doesn't look like a status page URL."
      return ""
    }
    if (root.atCapacity) {
      root.addError = "Watching " + Model.MAX_SERVICES + " already — remove one first."
      return ""
    }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].url === page) {
        root.addError = rows[i].name + " is already on the list."
        return ""
      }
    }
    return page
  }

  function addService(name, url) {
    var page = vetUrl(url)
    if (page === "") return false

    var preset = Model.presetFor(page)
    var label = String(name || "").trim()
    if (label === "") label = preset ? preset.name : Model.nameFromUrl(page)

    var next = []
    for (var r = 0; r < rows.length; r++) next.push({ name: rows[r].name, url: rows[r].url })
    next.push({ name: label, url: page })
    saveServices(next)
    root.addError = ""
    return true
  }

  // A pasted URL is verified before it is committed: most status pages are not
  // Statuspage, and adding one of those would leave a row that can only ever
  // say "unreachable".
  function addCustomService(url) {
    var page = vetUrl(url)
    if (page === "") return false
    root.addError = ""
    if (!monitor.probe(page)) {
      root.addError = "Still checking the last one\u2026"
      return false
    }
    return true
  }

  function removeService(url) {
    var next = []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].url !== url) next.push({ name: rows[i].name, url: rows[i].url })
    }
    saveServices(next)
    if (root.expandedUrl === url) root.expandedUrl = ""
    root.addError = ""
  }

  function setInterval(seconds) {
    persistSettings({ refreshIntervalSec: Model.clampInterval(seconds) })
  }

  // --------------------------------------------------------------- behaviour

  function toggleExpanded(url) {
    root.expandedUrl = root.expandedUrl === url ? "" : url
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0 || rows.length === 0) return
    cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + dy))
  }

  function activateCursor() {
    if (settingsOpen || rows.length === 0) return
    var row = rows[Math.max(0, Math.min(cursorIndex, rows.length - 1))]
    if (row) toggleExpanded(row.url)
  }

  function openCursorPage() {
    if (rows.length === 0) return
    var row = rows[Math.max(0, Math.min(cursorIndex, rows.length - 1))]
    if (row) monitor.openPage(row.url)
  }

  function setCursor(index) {
    cursorActive = true
    cursorIndex = index
  }

  function hasCursor(index) {
    return !settingsOpen && cursorActive && cursorIndex === index
  }

  function showSettings(on) {
    settingsOpen = on
    addError = ""
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
  }

  visible: !hideWhenOperational || !monitor.known || monitor.alarming || rows.length === 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    settingsOpen = false
    addError = ""
    nowMs = Date.now()
    // With a single service there is nothing to choose between, so show its
    // detail straight away rather than making the user click twice.
    expandedUrl = rows.length === 1 ? rows[0].url : ""
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Not named `palette`: every Item already has an inherited `palette`
  // property (QQuickPalette), and it shadows an id of that name.
  StatusPalette { id: statusColors }

  Service {
    id: monitor
    settings: root.settings
    // The provider knows what it is called; adopt the name so a pasted URL
    // ends up labelled "GitHub" rather than "Githubstatus".
    onServicesDiscovered: function(services) { root.saveServices(services) }
    onProbeFinished: function(url, ok, name) {
      if (ok) {
        if (root.addService(name, url)) urlField.text = ""
        return
      }
      root.addError = "No status feed there. Only Atlassian Statuspage pages work "
        + "— Google, X, Slack and AWS publish their own formats."
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { monitor.refresh(); return "ok" }
    // Scriptable list management, so a dotfiles bootstrap can set the list up
    // without hand-editing shell.json. `add` verifies the page first, exactly
    // as the settings view does, and reports the outcome asynchronously in the
    // panel rather than here.
    function add(url: string): string {
      return root.addCustomService(url) ? "checking" : (root.addError || "rejected")
    }
    function addPreset(name: string): string {
      for (var i = 0; i < Model.PRESETS.length; i++) {
        var preset = Model.PRESETS[i]
        if (preset.name.toLowerCase() === String(name || "").toLowerCase())
          return root.addService(preset.name, preset.url) ? "ok" : (root.addError || "rejected")
      }
      return "unknown preset"
    }
    function remove(name: string): string {
      var needle = String(name || "").toLowerCase()
      for (var i = 0; i < root.rows.length; i++) {
        var row = root.rows[i]
        if (row.name.toLowerCase() === needle || row.url.toLowerCase().indexOf(needle) !== -1) {
          root.removeService(row.url)
          return "removed " + row.name
        }
      }
      return "not watching " + name
    }
    // Open the popup with one service's detail already unfolded, for a keybind
    // along the lines of "show me what's wrong with Cloudflare".
    function expand(name: string): string {
      var needle = String(name || "").toLowerCase()
      for (var i = 0; i < root.rows.length; i++) {
        var row = root.rows[i]
        if (row.name.toLowerCase().indexOf(needle) !== -1 || row.url.toLowerCase().indexOf(needle) !== -1) {
          root.open()
          root.showSettings(false)
          root.expandedUrl = row.url
          root.setCursor(i)
          return "showing " + row.name
        }
      }
      return "not watching " + name
    }
    function interval(seconds: string): string {
      root.setInterval(seconds)
      return Model.intervalLabel(monitor.refreshIntervalSec)
    }
    function presets(): string {
      var names = []
      for (var i = 0; i < Model.PRESETS.length; i++) names.push(Model.PRESETS[i].name)
      return names.join(", ")
    }
    function openSettings(): void { root.open(); root.showSettings(true) }
    function state(): string {
      var lines = []
      for (var i = 0; i < root.rows.length; i++) {
        var row = root.rows[i]
        lines.push(row.name + ": " + (row.error ? "unreachable" : (row.description || "unknown")))
      }
      return lines.length === 0 ? "no services configured" : lines.join("\n")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: monitor.glyph
    // Monochrome on purpose. The severity colors live in the popup; the bar
    // stays in the theme's bar foreground like every widget beside it, and the
    // glyph alone carries the state — a check, a warning triangle, an
    // exclamation, a times-circle. Dimmed until the first reading lands, so an
    // unknown status never looks like a healthy one.
    foreground: monitor.known ? barForeground : Qt.darker(barForeground, 1.55)
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.opened ? "" : root.tooltip

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) monitor.refresh()
      else if (buttonCode === Qt.MiddleButton) { root.open(); root.showSettings(true) }
      else root.toggle()
    }
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The URL field and the preset filter own their keys while they are
      // active, or typing "r" would fire a refresh instead of entering a
      // character.
      blocked: urlField.activeFocus || presetPicker.popupOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: if (root.settingsOpen) root.showSettings(false); else root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") monitor.refresh()
        else if (t === "o" || t === "O") root.openCursorPage()
        else if (t === "s" || t === "S") root.showSettings(!root.settingsOpen)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.settingsOpen ? "Status settings" : "Service status"
            meta: root.settingsOpen
              ? rows.length + " of " + Model.MAX_SERVICES + " watched · " + Model.intervalLabel(monitor.refreshIntervalSec)
              : monitor.overall
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.settingsOpen ? "" : monitor.glyph
                color: root.settingsOpen ? root.foreground : root.severityColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ------------------------------------------------- status view

          Column {
            visible: !root.settingsOpen
            width: parent.width
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              visible: root.rows.length === 0
              width: parent.width
              text: "No status pages yet. Open settings to add one."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.rows
              ServiceRow {
                required property var modelData
                required property int index
                width: parent.width
                row: modelData
                rowIndex: index
              }
            }
          }

          // ----------------------------------------------- settings view

          Column {
            visible: root.settingsOpen
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "CHECK INTERVAL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              width: parent.width
              showLabel: false
              options: Model.INTERVAL_CHOICES
              value: String(monitor.refreshIntervalSec)
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) { root.setInterval(value) }
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "WATCHING · " + rows.length + " OF " + Model.MAX_SERVICES
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.rows
                RowLayout {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Model.indicatorGlyph(modelData.error ? "" : modelData.indicator)
                    color: statusColors.forSeverity(Model.severityFor(modelData))
                    opacity: modelData.indicator || modelData.error ? 1.0 : 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                      textFormat: Text.PlainText
                      Layout.fillWidth: true
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      Layout.fillWidth: true
                      text: modelData.url.replace(/^https?:\/\//, "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  PanelActionButton {
                    iconText: ""
                    tooltipText: "Stop watching " + modelData.name
                    foreground: root.foreground
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.removeService(modelData.url)
                  }
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "ADD A STATUS PAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // Presets first, because it is the path that always works: every
            // one is a known-good Statuspage. The URL field is the escape
            // hatch for everything else.
            SearchableDropdown {
              id: presetPicker
              width: parent.width
              showLabel: false
              triggerLabel: root.atCapacity ? "List is full" : "Pick a popular service…"
              placeholderText: "Filter…"
              emptyText: "Nothing left to add"
              enabled: !root.atCapacity
              options: {
                var list = []
                for (var i = 0; i < Model.PRESETS.length; i++) {
                  var preset = Model.PRESETS[i]
                  var alreadyWatched = false
                  for (var r = 0; r < root.rows.length; r++) {
                    if (root.rows[r].url === Model.normalizePageUrl(preset.url)) alreadyWatched = true
                  }
                  if (!alreadyWatched) list.push({ value: preset.url, label: preset.name })
                }
                return list
              }
              value: ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) {
                if (value === "") return
                var preset = Model.presetFor(value)
                root.addService(preset ? preset.name : "", value)
                presetPicker.value = ""
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: urlField
                Layout.fillWidth: true
                placeholderText: "or paste a status page URL"
                enabled: !root.atCapacity
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                onAccepted: root.addCustomService(text)
                Keys.onEscapePressed: function(event) {
                  urlField.focus = false
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }

              PanelActionButton {
                iconText: ""
                tooltipText: "Watch this page"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.atCapacity && urlField.text !== "" && !monitor.probing
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.addCustomService(urlField.text)
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: root.addError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              textFormat: Text.PlainText
              visible: root.addError === ""
              width: parent.width
              text: monitor.probing
                ? "Checking that page…"
                : "Any Atlassian Statuspage works — the page URL is enough."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSeparator { foreground: root.foreground }

            Toggle {
              width: parent.width
              label: "Notify on change"
              description: "One toast per service when its status changes"
              checked: monitor.notifyEnabled
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ notify: !monitor.notifyEnabled })
            }

            Toggle {
              width: parent.width
              label: "Hide when all clear"
              description: "Keep the icon off the bar unless something is wrong"
              checked: root.hideWhenOperational
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ hideWhenOperational: !root.hideWhenOperational })
            }
          }

          // ----------------------------------------------------- footer

          PanelSeparator { foreground: root.foreground }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: root.settingsOpen
                ? "Saved as you change it"
                : root.checkedText + " · " + Model.intervalLabel(monitor.refreshIntervalSec).toLowerCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            PanelActionButton {
              visible: !root.settingsOpen
              iconText: ""
              tooltipText: "Check now (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !monitor.loading && root.rows.length > 0
              Layout.alignment: Qt.AlignVCenter
              onClicked: monitor.refresh()
            }

            PanelActionButton {
              iconText: root.settingsOpen ? "" : ""
              tooltipText: root.settingsOpen ? "Back to status (s)" : "Settings (s)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.showSettings(!root.settingsOpen)
            }
          }
        }
      }
    }
  }

  // One service, one line: glyph, name, and our own uniform status word so ten
  // providers' worth of prose doesn't turn the popup into a wall of text. The
  // clicked row expands to show the provider's own description and the latest
  // incident update.
  component ServiceRow: CursorSurface {
    id: serviceRow

    required property var row
    required property int rowIndex

    readonly property bool expanded: root.expandedUrl === row.url
    readonly property bool troubled: row.error !== "" || (row.indicator !== "" && !Model.isHealthy(row.indicator))
    readonly property var incident: row.incident

    hasCursor: root.hasCursor(rowIndex)
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      onEntered: root.setCursor(serviceRow.rowIndex)
      onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton) monitor.openPage(serviceRow.row.url)
        else root.toggleExpanded(serviceRow.row.url)
      }
    }

    Column {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(4)

      // Headline line: always exactly one line tall, whatever the provider
      // wrote, so a list of ten stays scannable.
      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: Model.indicatorGlyph(serviceRow.row.error ? "" : serviceRow.row.indicator)
          color: statusColors.forSeverity(Model.severityFor(serviceRow.row))
          opacity: serviceRow.row.indicator || serviceRow.row.error ? 1.0 : 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          textFormat: Text.PlainText
          text: serviceRow.row.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          textFormat: Text.PlainText
          text: serviceRow.row.error
            ? "Unreachable"
            : (serviceRow.row.indicator ? Model.shortStatusLabel(serviceRow.row.indicator) : "…")
          color: serviceRow.troubled
            ? statusColors.forSeverity(Model.severityFor(serviceRow.row))
            : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          textFormat: Text.PlainText
          visible: serviceRow.incident !== null || serviceRow.row.degraded.length > 0
          text: serviceRow.expanded ? "" : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          Layout.alignment: Qt.AlignVCenter
        }
      }

      // Collapsed teaser: the incident title on one elided line, so a glance
      // tells you what is wrong without opening anything.
      Text {
        textFormat: Text.PlainText
        visible: !serviceRow.expanded && serviceRow.incident !== null
        width: parent.width
        text: serviceRow.incident ? serviceRow.incident.name : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      // Expanded detail.
      Column {
        visible: serviceRow.expanded
        width: parent.width
        spacing: Style.space(4)

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: serviceRow.row.error !== ""
            ? serviceRow.row.error
            : serviceRow.row.description
          color: serviceRow.row.error !== "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          visible: serviceRow.incident !== null
          width: parent.width
          text: serviceRow.incident ? serviceRow.incident.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: {
            if (!serviceRow.incident) return ""
            var incident = serviceRow.incident
            var parts = []
            if (incident.status) parts.push(Model.titleize(incident.status))
            if (incident.impact && incident.impact !== "none")
              parts.push(Model.titleize(incident.impact) + " impact")
            if (incident.startedAt)
              parts.push("started " + Model.relativeTime(incident.startedAt, root.nowMs))
            if (incident.kind === "maintenance" && incident.scheduledUntil)
              parts.push("ends " + Model.relativeFuture(incident.scheduledUntil, root.nowMs))
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // Trimmed: the provider's full update can run to paragraphs, and this
        // popup may be showing ten of them. The status page has the rest.
        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: serviceRow.incident ? Model.truncate(serviceRow.incident.updateBody, 240) : ""
          color: root.foreground
          opacity: 0.9
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: {
            var parts = []
            if (serviceRow.incident && serviceRow.incident.updateAt)
              parts.push("Updated " + Model.relativeTime(serviceRow.incident.updateAt, root.nowMs))
            if (serviceRow.row.incidentCount > 1)
              parts.push("+" + (serviceRow.row.incidentCount - 1) + " more ongoing")
            var degraded = serviceRow.row.degraded
            if (degraded.length > 0) {
              var names = []
              for (var i = 0; i < degraded.length; i++) names.push(degraded[i].name)
              parts.push(Model.truncate(names.join(", "), 90))
            }
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Button {
          text: "Open status page"
          iconText: ""
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: monitor.openPage(serviceRow.row.url)
        }
      }
    }
  }
}
