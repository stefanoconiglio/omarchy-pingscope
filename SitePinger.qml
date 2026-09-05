import QtQuick
import Quickshell.Io
import "PingModel.js" as Model

// One host's repeating ICMP probe. Pingers run whether the panel is open or
// not so the current latency is always ready when the dashboard opens.
Item {
  id: pinger

  property string host: ""
  property int intervalSec: 1
  property int ipVersion: 4
  property bool active: true

  // -1 until the first probe lands; -1 with hasSample = a failed probe.
  property real latencyMs: -1
  property bool hasSample: false
  property bool busy: false

  function sample() {
    if (!active || host === "" || busy || pingProc.running) return
    busy = true
    // `--` keeps a configuration value beginning with "-" from being
    // interpreted as another ping option.
    pingProc.command = ["ping", ipVersion === 6 ? "-6" : "-4", "-n", "-c", "1", "-W", "1", "--", host]
    pingProc.running = true
  }

  function clear() {
    busy = false
    pingProc.running = false
    latencyMs = -1
    hasSample = false
  }

  onHostChanged: {
    clear()
    // The killed probe's collector may still deliver one straggler EOF;
    // `busy` being false makes handleResult drop it.
    sample()
  }

  onIpVersionChanged: {
    clear()
    if (active) sample()
  }

  onActiveChanged: active ? sample() : clear()

  Component.onCompleted: sample()

  Timer {
    id: pollTimer
    interval: Math.max(1, pinger.intervalSec) * 1000
    repeat: true
    running: pinger.active && pinger.host !== ""
    onTriggered: pinger.sample()
  }

  Process {
    id: pingProc
    stdout: StdioCollector {
      waitForEnd: true
      // Read the result only after stdout is complete. Process.onExited can
      // arrive before the collector has received the summary and would mark
      // a successful ping as down.
      onStreamFinished: pinger.handleResult(text)
    }
  }

  function handleResult(raw) {
    if (!busy) return
    busy = false
    var ms = Model.parsePing(raw)
    latencyMs = ms
    hasSample = true
  }
}
