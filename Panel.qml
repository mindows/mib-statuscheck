import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button plus popup for status.claude.com. The button is the at-a-glance
// signal (a check when Claude is fine, a warning glyph tinted urgent when it
// is not); the popup answers the only question worth opening it for — is there
// an ongoing incident right now, and what does the latest update say.
Panel {
  id: root
  moduleName: "omacheckstatus"
  ipcTarget: "omacheckstatus"
  manageIpc: false

  // Rows the keyboard cursor can land on, in visual order. The set shrinks
  // when there is no incident, so the cursor is rebuilt on every reading
  // rather than tracked as a fixed index space.
  readonly property var actions: {
    var list = []
    if (claude.incident) list.push("incident")
    list.push("page")
    list.push("refresh")
    return list
  }
  property int actionIndex: 0
  property bool cursorActive: false

  // Drives every "4m ago" label in the popup. Only ticks while open, so a
  // closed popup costs nothing.
  property double nowMs: Date.now()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color statusColor: claude.degradedKnown ? urgent : foreground
  // Dimmed until the first reading lands, so an unknown status never looks
  // like a healthy one.
  readonly property color barIconColor: claude.known ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property bool hideWhenOperational: setting("hideWhenOperational", false) === true

  readonly property string checkedText: {
    if (claude.loading) return "Checking…"
    if (claude.lastSuccessMs === 0) return claude.lastError !== "" ? "Never reached" : "Not checked yet"
    var stamp = new Date(claude.lastSuccessMs).toISOString()
    return "Checked " + Model.relativeTime(stamp, root.nowMs)
  }

  readonly property string tooltip: {
    if (!claude.known) return claude.lastError !== "" ? "Claude status unavailable" : "Checking Claude status…"
    var text = "Claude — " + claude.description
    if (claude.incident) text += "\n" + claude.incident.name
    return text
  }

  function clampCursor() {
    if (actionIndex >= actions.length) actionIndex = Math.max(0, actions.length - 1)
    if (actionIndex < 0) actionIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex + dy))
  }

  function activateCursor() {
    clampCursor()
    var action = actions[actionIndex]
    if (action === "incident") claude.openIncident()
    else if (action === "page") claude.openStatusPage()
    else if (action === "refresh") claude.refresh()
  }

  function setCursor(action) {
    cursorActive = true
    var index = actions.indexOf(action)
    if (index >= 0) actionIndex = index
  }

  function hasCursor(action) {
    return cursorActive && actions[actionIndex] === action
  }

  visible: !hideWhenOperational || !claude.known || !claude.healthy
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onActionsChanged: clampCursor()
  onOpenedChanged: if (opened) {
    cursorActive = false
    actionIndex = 0
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: claude
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { claude.refresh(); return "ok" }
    function state(): string { return claude.known ? claude.description : "unknown" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: claude.glyph
    // `active` is what paints the glyph in the theme's urgent color, so a
    // degradation reads the same as every other alarming bar widget.
    active: claude.degradedKnown
    foreground: root.barIconColor
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.opened ? "" : root.tooltip

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) claude.refresh()
      else if (buttonCode === Qt.MiddleButton) claude.openStatusPage()
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") claude.refresh()
        else if (t === "o" || t === "O") claude.openStatusPage()
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
            id: hero
            width: parent.width
            title: "Claude"
            meta: claude.headline
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: claude.glyph
                color: root.statusColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          // Only surfaced when the last poll failed. A stale-but-known
          // reading stays on screen above it rather than being replaced, so
          // the user can see both what we last knew and that it is old.
          Text {
            textFormat: Text.PlainText
            visible: claude.lastError !== ""
            width: parent.width
            text: claude.known
              ? "Last check failed — showing the previous reading."
              : "Could not reach status.claude.com."
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          // ---------------------------------------------------- the answer

          PanelSectionHeader {
            text: claude.incident && claude.incident.kind === "maintenance" ? "ACTIVE MAINTENANCE" : "ONGOING INCIDENT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            textFormat: Text.PlainText
            visible: !claude.incident
            width: parent.width
            text: !claude.known
              ? "Status not yet known."
              : (claude.healthy
                ? "None. Claude is running normally."
                : "No incident has been posted for the current degradation.")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          IncidentCard {
            visible: !!claude.incident
            width: parent.width
          }

          // ------------------------------------------- affected components

          PanelSeparator {
            visible: claude.degraded.length > 0
            foreground: root.foreground
          }

          Column {
            visible: claude.degraded.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "AFFECTED SERVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              Repeater {
                model: claude.degraded
                Row {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    id: componentName
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.foreground
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, Math.max(0, parent.width - componentStatus.implicitWidth - parent.spacing))
                  }

                  Item {
                    width: Math.max(0, parent.width - componentName.width - componentStatus.implicitWidth - parent.spacing * 2)
                    height: 1
                  }

                  Text {
                    id: componentStatus
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          // --------------------------------------------------------- footer

          PanelSeparator { foreground: root.foreground }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: root.checkedText + " · every " + Math.round(claude.refreshIntervalSec / 60) + "m"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            PanelActionButton {
              iconText: ""
              tooltipText: "Check now (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !claude.loading
              hasCursor: root.hasCursor("refresh")
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setCursor("refresh") }
              onClicked: claude.refresh()
            }

            PanelActionButton {
              iconText: ""
              tooltipText: "Open status.claude.com (o)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.hasCursor("page")
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setCursor("page") }
              onClicked: claude.openStatusPage()
            }
          }
        }
      }
    }
  }

  // The incident itself: title, impact and lifecycle status, when it started,
  // and the body of the most recent update — which is the sentence that
  // actually tells you whether your problem is this problem.
  component IncidentCard: CursorSurface {
    id: card

    readonly property var incident: claude.incident || ({})

    hasCursor: root.hasCursor("incident")
    foreground: root.foreground
    implicitHeight: cardContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor("incident")
      onClicked: claude.openIncident()
    }

    Column {
      id: cardContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: card.incident.name || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: {
          var parts = []
          if (card.incident.status) parts.push(Model.titleize(card.incident.status))
          if (card.incident.impact && card.incident.impact !== "none")
            parts.push(Model.titleize(card.incident.impact) + " impact")
          if (card.incident.startedAt)
            parts.push("started " + Model.relativeTime(card.incident.startedAt, root.nowMs))
          if (card.incident.kind === "maintenance" && card.incident.scheduledUntil)
            parts.push("ends " + Model.relativeFuture(card.incident.scheduledUntil, root.nowMs))
          return parts.join(" · ")
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        width: parent.width
        text: card.incident.updateBody || ""
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
          if (card.incident.updateAt)
            parts.push("Updated " + Model.relativeTime(card.incident.updateAt, root.nowMs))
          if (claude.incidentCount > 1)
            parts.push("+" + (claude.incidentCount - 1) + " more ongoing")
          return parts.join(" · ")
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
