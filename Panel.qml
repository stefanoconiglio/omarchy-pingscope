import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "PingModel.js" as Model

// PingScope — bar widget + popup for the pingscope.latency plugin.
//
// Bar face: the focused site's latency, green / yellow / red by response time,
// on a dark pill outlined in the bar's own foreground colour. Right-click
// cycles the focused site, middle-click samples immediately, and left-click
// opens the panel.
//
// Panel: current latency per site, plus a configuration section that edits up
// to Model.maxSites() hosts and persists them into this widget's inline
// shell.json entry.
Panel {
  id: root

  moduleName: "pingscope.latency"
  ipcTarget: "pingscope.latency"
  manageIpc: false

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  // The transparent bar chooses this dynamically from the wallpaper. Popup
  // content must use the popup palette instead: its card keeps the theme's
  // popup background even when the wallpaper makes barForeground go dark.
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color popupForeground: Color.popups.text
  readonly property color popupMuted: Qt.darker(popupForeground, 1.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color goodLatency: "#22c55e"
  readonly property color warningLatency: "#eab308"
  readonly property color badLatency: "#ef4444"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Globe, in the panel header only; the bar shows text alone.
  readonly property string glyph: "󰖟"

  // ---------- settings ----------

  readonly property var sites: Model.normalizeSites(setting("sites", Model.defaultSites()))

  readonly property int closedRefreshSec: Math.max(1, Number(setting("closedRefreshSec", 1)))
  readonly property int openRefreshSec: Math.max(1, Number(setting("openRefreshSec", 1)))
  readonly property real greenMaxMs: 50
  readonly property real redMinMs: 100
  readonly property int ipVersion: Number(setting("ipVersion", 4)) === 6 ? 6 : 4
  readonly property bool probesRunning: {
    var value = setting("running", true)
    if (typeof value === "string") return value.toLowerCase() !== "false"
    return value !== false
  }
  // Clamp to the list so removing the last entry never leaves the face
  // pointing at a ghost.
  readonly property int focusedSite: {
    var requested = Math.max(0, Math.floor(Number(setting("focusedSite", 0)) || 0))
    return sites.length > 0 ? Math.min(requested, sites.length - 1) : 0
  }

  // ---------- sampling ----------

  function pingerAt(index) {
    return pingerRepeater.itemAt(index)
  }

  function sampleAll() {
    for (var i = 0; i < sites.length; i++) {
      var pinger = pingerAt(i)
      if (pinger) pinger.sample()
    }
  }

  // Reading `count` makes the binding re-evaluate when the sites model
  // churns delegates, so a stale destroyed pinger is never held.
  readonly property var focusedPinger: {
    var ignored = pingerRepeater.count
    return pingerRepeater.itemAt(focusedSite)
  }

  readonly property string focusedStatus: !probesRunning ? "idle" : focusedPinger
    ? Model.statusFor(focusedPinger.latencyMs, focusedPinger.hasSample, greenMaxMs, redMinMs)
    : "idle"

  // ---------- presentation helpers ----------

  function statusColor(status, normalColor, idleColor) {
    if (status === "bad" || status === "down") return badLatency
    if (status === "warning") return warningLatency
    if (status === "good") return goodLatency
    if (status === "idle") return idleColor
    return normalColor
  }

  // Bar face: a dark pill whatever the theme, so the green, yellow and red
  // latency stays readable; it stands out from a light bar by its fill and
  // from a dark one by its border, drawn in the bar's foreground colour (which
  // every theme keeps in contrast with the bar).
  readonly property color pillFill: "#18181b"
  readonly property color pillText: "#e4e4e7"
  readonly property color pillMuted: "#a1a1aa"

  function barLabel() {
    var label
    if (sites.length === 0) label = "—"
    else if (!probesRunning) label = "off"
    else if (!focusedPinger || !focusedPinger.hasSample) label = "…"
    else if (focusedStatus === "down") label = vertical ? "×" : "no net"
    else {
      var ms = Number(focusedPinger.latencyMs)
      if (vertical) label = String(Math.round(ms))
      else label = ms >= 1000 ? (ms / 1000).toFixed(1) + " s" : Math.round(ms) + " ms"
    }
    return label
  }

  function faceLabel() {
    if (sites.length === 0) return "—"
    if (!probesRunning) return "off"
    if (!focusedPinger || !focusedPinger.hasSample) return "…"
    return Model.formatMs(focusedPinger.latencyMs)
  }

  function tooltipText() {
    if (sites.length === 0) return "PingScope · no sites configured"
    var lines = ["PingScope · IPv" + ipVersion + (probesRunning ? "" : " · stopped")]
    for (var i = 0; i < sites.length; i++) {
      var pinger = pingerAt(i)
      var value = !probesRunning ? "stopped" : pinger && pinger.hasSample ? Model.formatMs(pinger.latencyMs) : "…"
      lines.push(Model.escapeMarkup(sites[i]) + " " + value)
    }
    lines.push("Left: dashboard & sites · Right: cycle site · Middle: refresh")
    return lines.join("\n")
  }

  function panelMeta() {
    if (!probesRunning) return "stopped · IPv" + ipVersion
    return "icmp IPv" + ipVersion + " · every " + (opened ? openRefreshSec : closedRefreshSec) + "s"
  }

  // ---------- settings persistence ----------

  function persist(patch) {
    settings = Object.assign({}, settings, patch)
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, settings)
  }

  function toggleIpVersion() {
    persist({ ipVersion: ipVersion === 4 ? 6 : 4 })
  }

  function toggleRunning() {
    persist({ running: !probesRunning })
  }

  function cycleSite() {
    if (sites.length < 2) return
    persist({ focusedSite: (focusedSite + 1) % sites.length })
  }

  // ---------- drafts (configuration section) ----------

  property var draftSites: []
  property int pendingFocusIndex: -1

  function addDraft() {
    if (draftSites.length >= Model.maxSites()) return
    draftSites = draftSites.concat([""])
    pendingFocusIndex = draftSites.length - 1
  }

  function removeDraftAt(index) {
    if (index < 0 || index >= draftSites.length) return
    var next = draftSites.slice()
    next.splice(index, 1)
    draftSites = next
  }

  function saveDrafts() {
    var cleaned = Model.normalizeSites(draftSites)
    persist({
      sites: cleaned,
      focusedSite: Math.min(focusedSite, Math.max(0, cleaned.length - 1))
    })
    // Rebuild the fields with the cleaned hostnames so a "https://x.com/"
    // entry visibly becomes "x.com" the moment it is saved.
    draftSites = cleaned.slice()
  }

  // ---------- keyboard cursor over the action row ----------

  property bool cursorActive: false
  property int selectedIndex: 0
  readonly property int actionCount: 2

  function moveCursor(delta) {
    if (delta === 0) return
    selectedIndex = Math.max(0, Math.min(actionCount - 1, selectedIndex + delta))
  }

  function activateCursor() {
    if (selectedIndex === 0) addDraft()
    else saveDrafts()
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var point = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = point.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = Style.space(6)
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin) flick.contentY = bottom + margin - flick.height
  }

  function handlePress(buttonCode) {
    if (buttonCode === Qt.RightButton) cycleSite()
    else if (buttonCode === Qt.MiddleButton) sampleAll()
    else toggle()
  }

  visible: true
  implicitWidth: vertical ? barSize : pill.width + Style.space(10)
  implicitHeight: vertical ? pill.height + Style.space(10) : barSize

  onOpenedChanged: {
    if (opened) {
      draftSites = sites.slice()
      cursorActive = false
      selectedIndex = 0
      sampleAll()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  // One pinger per site, owned by the root so latency continues to update
  // while the panel is closed.
  Repeater {
    id: pingerRepeater
    model: root.sites

    SitePinger {
      required property string modelData
      host: modelData
      intervalSec: root.opened ? root.openRefreshSec : root.closedRefreshSec
      ipVersion: root.ipVersion
      active: root.probesRunning
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.sampleAll(); return "ok" }
    function status(): string {
      if (root.sites.length === 0) return "no sites configured"
      var parts = []
      for (var i = 0; i < root.sites.length; i++) {
        var pinger = root.pingerAt(i)
        parts.push(root.sites[i] + "=" + (pinger && pinger.hasSample ? Model.formatMs(pinger.latencyMs) : "…"))
      }
      return parts.join(" ")
    }
  }

  // ---------- bar face ----------
  //
  // Hand-made like PingScope's own face (WidgetButton draws text only): it
  // registers as a click target and shows the bar's shared tooltip itself.

  Item {
    id: face
    anchors.fill: parent

    Component.onCompleted: if (root.bar && root.bar.registerClickTarget) root.bar.registerClickTarget(face)
    Component.onDestruction: if (root.bar && root.bar.unregisterClickTarget) root.bar.unregisterClickTarget(face)

    // The widest label sets the pill's width, so "9 ms" turning into
    // "10 ms" never moves the neighbouring widgets.
    TextMetrics {
      id: widest
      font: pillLabel.font
      text: root.vertical ? "888" : "888 ms"
    }

    // The ink of the current label: centring the line box would leave the
    // glyphs high (it keeps room for descenders) and off by bearings.
    TextMetrics {
      id: ink
      font: pillLabel.font
      text: pillLabel.text
    }

    FontMetrics {
      id: lineMetrics
      font: pillLabel.font
    }

    Rectangle {
      id: pill
      anchors.centerIn: parent
      // Even, like the ink of the labels measured (3 ms, 142 ms, no net),
      // so the space left and right of them splits without a half pixel.
      width: {
        var w = Math.ceil(widest.width) + Style.space(14)
        return w % 2 === 0 ? w : w + 1
      }
      // Same parity as the bar, so centring the pill leaves no half pixel.
      height: {
        var h = Math.min(root.barSize - Style.space(2), Math.ceil(lineMetrics.height) + Style.space(2))
        return (root.barSize - h) % 2 === 0 ? h : h - 1
      }
      radius: height / 2
      color: root.pillFill
      border.width: Math.max(1, Math.round(Style.space(1.5)))
      border.color: root.foreground

      Text {
        id: pillLabel
        // Horizontally the ink of this label is centred; vertically that of
        // the digits ("888 ms"), so every label sits on the same baseline.
        // tightBoundingRect is relative to the baseline, at ascent below the top.
        x: (pill.width - ink.tightBoundingRect.width) / 2 - ink.tightBoundingRect.x
        y: Math.round((pill.height - widest.tightBoundingRect.height) / 2
                      - widest.tightBoundingRect.y - lineMetrics.ascent)
        text: root.barLabel()
        color: root.statusColor(root.focusedStatus, root.pillText, root.pillMuted)
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(face, root.tooltipText())
      onExited: if (root.bar) root.bar.hideTooltip(face)
      onClicked: function(mouse) {
        if (root.bar) root.bar.hideTooltip(face)
        root.handlePress(mouse.button)
      }
    }
  }

  // ---------- popup ----------

  KeyboardPanel {
    id: panel
    anchorItem: face
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dy !== 0 ? dy : dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.sampleAll()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(9)

          PanelHero {
            width: parent.width
            title: "PingScope"
            meta: root.panelMeta()
            foreground: root.popupForeground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: root.glyph
                color: root.popupForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑖"
                tooltipText: "Refresh (R)"
                foreground: root.popupForeground
                hoverColor: root.accent
                fontFamily: root.fontFamily
                onClicked: root.sampleAll()
              }
            }
          }

          PanelSeparator { foreground: root.popupForeground }

          SectionHeading {
            title: "CONTROLS"
            value: (root.probesRunning ? "RUNNING" : "STOPPED") + " · IPV" + root.ipVersion
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.ipVersion === 4 ? "IPv4 → IPv6" : "IPv6 → IPv4"
              tooltipText: root.ipVersion === 4 ? "Switch probes to IPv6" : "Switch probes to IPv4"
              bordered: true
              foreground: root.popupForeground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.toggleIpVersion()
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.probesRunning ? "Stop" : "Start"
              tooltipText: root.probesRunning ? "Stop all ping probes" : "Start all ping probes"
              bordered: true
              foreground: root.probesRunning ? root.urgent : root.popupForeground
              accent: root.probesRunning ? root.urgent : root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.toggleRunning()
            }
          }

          Text {
            width: parent.width
            text: "Controls apply immediately — Save is only for site changes."
            color: root.popupMuted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.popupForeground }

          // ---------- live status ----------

          SectionHeading {
            title: "CURRENT LATENCY"
            value: root.probesRunning ? "COLOR BY RESPONSE TIME" : "PROBES STOPPED"
          }

          Row {
            width: parent.width
            spacing: Style.space(16)

            Text {
              text: "● 1–50 ms"
              color: root.goodLatency
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              text: "● 51–99 ms"
              color: root.warningLatency
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              text: "● 100+ ms"
              color: root.badLatency
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Repeater {
            model: root.sites

            Row {
              id: siteRow
              required property int index
              required property string modelData
              width: parent.width
              height: Style.space(26)
              spacing: Style.space(8)

              // Re-evaluate after the sampling Repeater has created its
              // delegates. Without the count dependency this can stay null
              // when the panel rows are built first.
              readonly property var pinger: {
                var ignored = pingerRepeater.count
                return pingerRepeater.itemAt(siteRow.index)
              }
              readonly property string status: !root.probesRunning ? "idle" : pinger
                ? Model.statusFor(pinger.latencyMs, pinger.hasSample, root.greenMaxMs, root.redMinMs)
                : "idle"

              Text {
                id: hostText
                width: Math.max(1, parent.width - rowValue.width - parent.spacing)
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: siteRow.modelData
                color: siteRow.index === root.focusedSite ? root.accent : root.popupForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.persist({ focusedSite: siteRow.index })
                }
              }

              Text {
                id: rowValue
                width: Style.space(72)
                anchors.verticalCenter: parent.verticalCenter
                text: !root.probesRunning ? "stopped" : siteRow.pinger && siteRow.pinger.hasSample
                  ? Model.formatMs(siteRow.pinger.latencyMs)
                  : "checking…"
                color: root.statusColor(siteRow.status, root.popupForeground, root.popupMuted)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                horizontalAlignment: Text.AlignRight
              }

            }
          }

          Text {
            width: parent.width
            visible: root.sites.length === 0
            text: "No sites configured — add up to four below."
            color: root.popupMuted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.popupForeground }

          // ---------- configuration ----------

          SectionHeading {
            title: "SITES"
            value: "UP TO " + Model.maxSites() + " · SAVED TO SHELL.JSON"
          }

          Repeater {
            model: root.draftSites

            Row {
              id: configRow
              required property int index
              required property string modelData
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: hostField
                width: parent.width - removeButton.width - parent.spacing
                foreground: root.popupForeground
                accent: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                placeholderText: "hostname, e.g. example.com"
                text: configRow.modelData
                Component.onCompleted: if (root.pendingFocusIndex === configRow.index) {
                  root.pendingFocusIndex = -1
                  Qt.callLater(function() { hostField.forceActiveFocus() })
                }
                // Mutate in place: reassigning draftSites here would
                // rebuild this Repeater mid-keystroke and drop focus.
                onTextEdited: root.draftSites[configRow.index] = hostField.text
                onAccepted: root.saveDrafts()
              }

              Button {
                id: removeButton
                iconText: "󰀍"
                tooltipText: "Remove site"
                bordered: true
                foreground: root.popupForeground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                iconSize: Style.font.bodySmall
                onClicked: root.removeDraftAt(configRow.index)
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            ActionButton {
              width: (parent.width - parent.spacing) / 2
              index: 0
              iconText: "󰅐"
              text: "Add site"
              tooltipText: "Add a site (max " + Model.maxSites() + ")"
              enabled: root.draftSites.length < Model.maxSites()
              opacity: enabled ? 1 : 0.45
              onClicked: root.addDraft()
            }

            ActionButton {
              width: (parent.width - parent.spacing) / 2
              index: 1
              iconText: "󰑖"
              text: "Save"
              tooltipText: "Save sites to shell.json"
              onClicked: root.saveDrafts()
            }
          }

          Text {
            width: parent.width
            visible: root.sites.length > 0
            text: "Sites that block ICMP will show as down — swap them here anytime. Right-click the bar widget to cycle the focused site."
            color: root.popupMuted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // Section label on the left, its live summary on the right — the shell's
  // house pattern.
  component SectionHeading: Item {
    property string title: ""
    property string value: ""

    width: parent ? parent.width : 0
    implicitHeight: Math.max(headingText.implicitHeight, valueText.implicitHeight)

    PanelSectionHeader {
      id: headingText
      text: title
      textFormat: Text.PlainText
      foreground: root.popupForeground
      fontFamily: root.fontFamily
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: valueText.visible ? valueText.left : parent.right
      anchors.rightMargin: valueText.visible ? Style.space(8) : 0
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: valueText
      text: value
      visible: text !== ""
      color: root.popupMuted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      width: Math.min(implicitWidth, parent.width * 0.62)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
    }
  }

  component ActionButton: Button {
    id: actionButton
    property int index: -1

    bordered: true
    foreground: root.popupForeground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    iconSize: Style.font.icon
    hasCursor: root.cursorActive && root.selectedIndex === actionButton.index
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(actionButton)
    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.selectedIndex = actionButton.index
    }
  }
}
