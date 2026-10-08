import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "PingModel.js" as Model

// PingScope — bar widget for the pingscope.latency plugin.
//
// Bar face: the site's latency inside a soft outline, in the bar's colour,
// orange when slow, red at 100 ms or when down (one `ping -c 1` a second).
//
// Behind it, one shell runs `ping <site> -i 1` all the time, in a tmux session
// of its own (ping-terminal.sh). Hovering the face shows that session's
// screen, live; a click opens a terminal attached to it in the same place, to
// type in. The terminal closes when it loses focus, or on another click; the
// ping goes on.
BarWidget {
  id: root

  moduleName: "pingscope.latency"
  readonly property string ipcTarget: "pingscope.latency"

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---------- settings ----------

  readonly property var sites: Model.normalizeSites(setting("sites", Model.defaultSites()))

  readonly property int closedRefreshSec: Math.max(1, Number(setting("closedRefreshSec", 1)))
  readonly property real greenMaxMs: 50
  readonly property real redMinMs: 100
  readonly property int ipVersion: Number(setting("ipVersion", 4)) === 6 ? 6 : 4
  readonly property int timeoutSec: Math.max(1, Number(setting("timeoutSec", 10)))
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
  // The one site of the face and of the ping session.
  readonly property string host: sites.length > 0 ? sites[focusedSite] : ""

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

  // Bar face: the latency inside a soft outline in the bar's text colour, in
  // the bar's colour when fast, orange when slow, red at 100 ms or when down
  // (Attention.qml: the theme's own orange and red when it has them, always
  // readable on its bar).
  Attention { id: attention; bar: root.bar }

  function faceColor(status) {
    if (status === "bad" || status === "down") return attention.red
    if (status === "warning") return attention.orange
    if (status === "idle") return attention.dim
    return attention.normal
  }

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

  // ---------- the ping session: hover view and attached terminal ----------

  readonly property string script: decodeURIComponent(Qt.resolvedUrl("ping-terminal.sh").toString().replace(/^file:\/\//, ""))
  readonly property string terminalClass: "pingscope.terminal"

  // The hover view and the attached terminal share this rectangle, under the
  // face; the text is the terminal's 9 pt (12 px) and padding.
  readonly property int viewWidth: 720
  readonly property int viewHeight: 300
  readonly property int viewGap: Style.gapsOut
  readonly property int viewPadding: 14
  readonly property int viewFontSize: 12
  readonly property int viewLines: Math.max(1, Math.floor(screenLabel.height / viewMetrics.lineSpacing))

  property bool peeking: false          // the pointer rests on the face
  property bool attaching: false        // a click is starting the terminal
  property string terminalAddress: ""   // its window, from Hyprland's events (no 0x)
  property bool terminalFocused: false
  property string screenText: ""

  // Kept up while a click starts the terminal, which then takes its place.
  readonly property bool viewShown: (peeking || attaching) && terminalAddress === "" && host !== ""

  function ensureSession() {
    if (host !== "") Util.execArgv([script, "session", host])
  }

  function capture() {
    if (!captureProc.running) captureProc.running = true
  }

  function showScreen(raw) {
    var lines = String(raw || "").replace(/\s+$/, "").split("\n")
    screenText = lines.slice(-viewLines).join("\n")
  }

  // Where the view goes, for a top or bottom bar: under (over) the face, inside
  // the screen. `windowY` is in the bar's coordinates (the popup's anchor), `y`
  // in the monitor's (the terminal's window rule).
  function viewPlace() {
    var win = face.QsWindow.window
    if (!win) return null
    var center = win.contentItem.mapFromItem(face, face.width / 2, 0)
    var x = Math.round(center.x - viewWidth / 2)
    x = Math.max(viewGap, Math.min(x, win.width - viewWidth - viewGap))
    var bottomBar = bar && bar.position === "bottom"
    var screenHeight = win.screen ? win.screen.height : 0
    return {
      x: x,
      windowY: bottomBar ? -viewHeight - viewGap : win.height + viewGap,
      y: bottomBar ? screenHeight - win.height - viewHeight - viewGap : win.height + viewGap
    }
  }

  function toggleTerminal() {
    if (terminalAddress !== "") { closeTerminal(); return }
    if (attaching || host === "") return
    var place = viewPlace()
    if (!place) return
    attaching = true
    attachTimeout.restart()
    Util.execArgv([script, "attach", host, String(place.x), String(place.y), String(viewWidth), String(viewHeight)])
  }

  // Closing the window only detaches tmux: the ping goes on.
  function closeTerminal() {
    if (terminalAddress === "") return
    Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.window.close({ window = "address:0x' + terminalAddress + '" })'])
  }

  onViewShownChanged: if (viewShown) ensureSession()
  onHostChanged: ensureSession()
  Component.onCompleted: ensureSession()

  Timer {
    id: hoverDelay
    interval: 150
    onTriggered: root.peeking = true
  }

  Timer {
    interval: 500
    repeat: true
    triggeredOnStart: true
    running: root.viewShown
    onTriggered: root.capture()
  }

  // A click that opened nothing gives the view back to the hover.
  Timer {
    id: attachTimeout
    interval: 4000
    onTriggered: root.attaching = false
  }

  // A terminal that never got the focus would never lose it either.
  Timer {
    id: focusFallback
    interval: 2000
    onTriggered: if (!root.terminalFocused) root.closeTerminal()
  }

  Process {
    id: captureProc
    command: ["tmux", "-L", "pingscope", "capture-pane", "-p", "-J", "-t", "=ping:"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.showScreen(text)
    }
  }

  // The terminal is ours from its first appearance (openwindow), focused when
  // Hyprland says so (activewindowv2), and closed as soon as the focus goes
  // anywhere else.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var data = String(event.data)
      if (event.name === "openwindow") {
        var fields = data.split(",")
        if (fields[2] !== root.terminalClass) return
        root.terminalAddress = fields[0]
        root.terminalFocused = false
        root.attaching = false
        focusFallback.restart()
      } else if (event.name === "activewindowv2") {
        if (root.terminalAddress === "") return
        if (data === root.terminalAddress) root.terminalFocused = true
        else if (root.terminalFocused) root.closeTerminal()
      } else if (event.name === "closewindow") {
        if (data !== root.terminalAddress) return
        root.terminalAddress = ""
        root.terminalFocused = false
      }
    }
  }

  visible: true
  implicitWidth: vertical ? barSize : pill.width + Style.space(10)
  implicitHeight: vertical ? pill.height + Style.space(10) : barSize

  // One pinger per site, for the face.
  Repeater {
    id: pingerRepeater
    model: root.sites

    SitePinger {
      required property string modelData
      host: modelData
      intervalSec: root.closedRefreshSec
      ipVersion: root.ipVersion
      timeoutSec: root.timeoutSec
      active: root.probesRunning
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { if (root.terminalAddress === "") root.toggleTerminal() }
    function close(): void { root.closeTerminal() }
    function toggle(): void { root.toggleTerminal() }
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
  // Hand-made like PingScope's own face (WidgetButton draws text only); it
  // registers as a click target.

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
      color: "transparent"
      border.width: Math.max(1, Math.round(Style.space(1.5)))
      border.color: attention.outline

      Text {
        id: pillLabel
        // Horizontally the ink of this label is centred; vertically that of
        // the digits ("888 ms"), so every label sits on the same baseline.
        // tightBoundingRect is relative to the baseline, at ascent below the top.
        x: (pill.width - ink.tightBoundingRect.width) / 2 - ink.tightBoundingRect.x
        y: Math.round((pill.height - widest.tightBoundingRect.height) / 2
                      - widest.tightBoundingRect.y - lineMetrics.ascent)
        text: root.barLabel()
        color: root.faceColor(root.focusedStatus)
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }

    MouseArea {
      id: faceMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.terminalAddress === "") hoverDelay.restart()
      onExited: {
        hoverDelay.stop()
        root.peeking = false
      }
      onClicked: {
        root.peeking = false
        root.toggleTerminal()
      }
    }
  }

  // ---------- hover view ----------
  //
  // A plain popup of the bar, not a PopupCard: those take the bar's single
  // popout slot, so passing over the face would close an open panel.

  PopupWindow {
    id: view
    visible: root.viewShown && viewAnchor.window !== null
    color: "transparent"
    implicitWidth: root.viewWidth
    implicitHeight: root.viewHeight

    anchor {
      id: viewAnchor
      window: face.QsWindow.window
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1
      onAnchoring: {
        var place = root.viewPlace()
        if (!place) return
        viewAnchor.rect.x = place.x
        viewAnchor.rect.y = place.windowY
      }
    }

    BorderSurface {
      id: viewCard
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.viewPadding

      Text {
        id: screenLabel
        x: viewCard.contentLeftInset
        y: viewCard.contentTopInset
        width: viewCard.width - viewCard.contentLeftInset - viewCard.contentRightInset
        height: viewCard.height - viewCard.contentTopInset - viewCard.contentBottomInset
        clip: true
        textFormat: Text.PlainText
        wrapMode: Text.NoWrap
        text: root.screenText !== "" ? root.screenText : "starting ping " + root.host + " …"
        color: Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: root.viewFontSize
      }

      FontMetrics {
        id: viewMetrics
        font: screenLabel.font
      }
    }
  }
}
