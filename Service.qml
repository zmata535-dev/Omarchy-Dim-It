import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/dim-it.json"
  readonly property string stayAwakePath: home + "/.local/state/omarchy/indicators/stay-awake"

  property int displayDimSeconds: 60
  property int barDimSeconds: 60
  property int monitorOffSeconds: 0
  property bool nativeIdle: false
  property double nativeIdleSinceMs: 0
  property int nativeIdleElapsedSeconds: 0
  property bool barPlaybackIdle: false
  property double barPlaybackIdleSinceMs: 0
  property int barPlaybackElapsedSeconds: 0
  property bool nativeLockLatched: false
  property bool lockTriggered: false
  property int dimPercentage: 25
  property bool enabled: true
  property bool barColorDuringPlayback: false
  property bool stayAwake: false
  property int savedBrightness: 0
  property bool isDimmed: false
  property bool manualTest: false
  property bool monitorWasTurnedOff: false

  readonly property bool monitorShouldBeActive: enabled && !stayAwake
  readonly property var mediaPlayers: Mpris.players ? Mpris.players.values : []
  readonly property bool playbackActive: {
    var players = root.mediaPlayers
    for (var i = 0; i < players.length; i++)
      if (players[i] && players[i].isPlaying) return true
    return false
  }
  readonly property bool barPlaybackOverrideActive: root.barColorDuringPlayback && root.playbackActive && root.monitorShouldBeActive
  property bool barPlaybackMonitorWasIdle: false

  function applyConfig(raw) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") return
    displayDimSeconds = typeof parsed.displayDimSeconds === "number" && parsed.displayDimSeconds >= 5 && parsed.displayDimSeconds <= 18000
      ? Math.round(parsed.displayDimSeconds)
      : typeof parsed.dimSeconds === "number" && parsed.dimSeconds >= 5 && parsed.dimSeconds <= 3600
        ? Math.round(parsed.dimSeconds) : 60
    barDimSeconds = typeof parsed.barDimSeconds === "number" && parsed.barDimSeconds >= 5 && parsed.barDimSeconds <= 18000
      ? Math.round(parsed.barDimSeconds)
      : typeof parsed.dimSeconds === "number" && parsed.dimSeconds >= 5 && parsed.dimSeconds <= 3600
        ? Math.round(parsed.dimSeconds) : 60
    monitorOffSeconds = typeof parsed.monitorOffSeconds === "number" && parsed.monitorOffSeconds >= 0 && parsed.monitorOffSeconds <= 18000
      ? Math.round(parsed.monitorOffSeconds) : 0
    if (typeof parsed.dimPercentage === "number" && parsed.dimPercentage >= 1 && parsed.dimPercentage <= 100)
      dimPercentage = Math.round(parsed.dimPercentage)
    if (typeof parsed.enabled === "boolean") enabled = parsed.enabled
    if (typeof parsed.barColorDuringPlayback === "boolean") barColorDuringPlayback = parsed.barColorDuringPlayback
    else if (typeof parsed.playbackTimerEnabled === "boolean") barColorDuringPlayback = parsed.playbackTimerEnabled
  }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
  }

  FileView {
    id: stayAwakeFile
    path: root.stayAwakePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.stayAwake = true
    onLoadFailed: root.stayAwake = false
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: stayAwakeFile.reload()
  }

  function handleDimIdle(isManual) {
    if (!root.enabled || (root.stayAwake && !isManual) || root.isDimmed) return
    root.manualTest = !!isManual
    readBrightness.running = true
  }

  function handleActive() {
    root.manualTest = false
    if (!root.isDimmed || root.savedBrightness <= 0) return
    var restoreValue = root.savedBrightness
    root.isDimmed = false
    root.savedBrightness = 0
    Quickshell.execDetached(["omarchy-brightness-display", "--no-osd", restoreValue + "%"])
  }

  function endNativeIdle() {
    var hadNativeState = root.nativeIdle || root.nativeLockLatched
    root.nativeIdle = false
    root.nativeIdleSinceMs = 0
    root.nativeIdleElapsedSeconds = 0
    root.nativeLockLatched = false
    root.lockTriggered = false
    if (hadNativeState) root.handleActive()
    if (root.monitorWasTurnedOff) {
      root.monitorWasTurnedOff = false
      Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "on"])
    }
  }

  function restoreIdleEffects() {
    root.endNativeIdle()
    root.handleActive()
    if (root.monitorWasTurnedOff) {
      root.monitorWasTurnedOff = false
      Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "on"])
    }
  }

  function applyNativeIdleStatus(raw) {
    if (!raw || String(raw).length > 8192) {
      root.endNativeIdle()
      return
    }
    var status = null
    try { status = JSON.parse(String(raw)) } catch (e) { status = null }
    if (!status || typeof status !== "object") {
      root.endNativeIdle()
      return
    }

    var screensaver = Number(status.screensaver)
    var nativeLock = Number(status.lock)
    var firstTimeout = Math.min(
      screensaver > 0 && isFinite(screensaver) ? screensaver : Infinity,
      nativeLock > 0 && isFinite(nativeLock) ? nativeLock : Infinity
    )
    var nativeEnabled = root.monitorShouldBeActive && status.enabled === true && isFinite(firstTimeout)
    var inNativeCycle = status.idle === true || status.inIdleCycle === true
    var event = String(status.lastEvent || "")
    var activeEvent = event.indexOf("idle-monitor: active") === 0 && status.inIdleCycle !== true

    if (event.indexOf("lock-system") === 0 || event.indexOf("process-start: lock") === 0) {
      root.nativeLockLatched = true
      root.lockTriggered = true
    }
    if (activeEvent) root.nativeLockLatched = false

    if (!nativeEnabled || (!inNativeCycle && !root.nativeLockLatched)) {
      root.endNativeIdle()
      return
    }

    if (!root.nativeIdle) {
      var eventAt = Date.parse(String(status.lastEventAt || ""))
      var eventTimeout = firstTimeout
      var canAnchorToNativeEvent = event.indexOf("idle-cycle-start") === 0 || event.indexOf("idle-monitor: idle") === 0
      if (event.indexOf("lock-system") === 0 || event.indexOf("process-start: lock") === 0) {
        eventTimeout = nativeLock
        canAnchorToNativeEvent = nativeLock > 0
      } else if (event.indexOf("screensaver") !== -1 && screensaver > 0) {
        eventTimeout = screensaver
        canAnchorToNativeEvent = true
      }
      root.nativeIdleSinceMs = canAnchorToNativeEvent && isFinite(eventAt)
        ? eventAt - eventTimeout * 1000
        : Date.now() - firstTimeout * 1000
      root.nativeIdle = true
      root.lockTriggered = root.nativeLockLatched || (status.processes && status.processes.lock === true)
      root.monitorWasTurnedOff = false
    }

    root.nativeIdleElapsedSeconds = Math.max(0, Math.floor((Date.now() - root.nativeIdleSinceMs) / 1000))
    root.applyIdleActions()
  }

  function applyIdleActions() {
    if (!root.nativeIdle || !root.monitorShouldBeActive) return
    if (!root.isDimmed && root.displayDimSeconds > 0 && root.nativeIdleElapsedSeconds >= root.displayDimSeconds)
      root.handleDimIdle(false)
    if (!root.monitorWasTurnedOff && root.monitorOffSeconds > 0 && root.nativeIdleElapsedSeconds >= root.monitorOffSeconds) {
      root.monitorWasTurnedOff = true
      Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "off"])
    }
  }

  function updatePlaybackIdle(isIdle) {
    if (!root.barPlaybackOverrideActive) return
    if (isIdle) {
      root.barPlaybackMonitorWasIdle = true
      if (!root.barPlaybackIdle) {
        root.barPlaybackIdleSinceMs = Date.now() - root.barDimSeconds * 1000
        root.barPlaybackIdle = true
      }
      root.barPlaybackElapsedSeconds = Math.max(0, Math.floor((Date.now() - root.barPlaybackIdleSinceMs) / 1000))
    } else if (root.barPlaybackMonitorWasIdle) {
      root.barPlaybackMonitorWasIdle = false
      root.barPlaybackIdle = false
      root.barPlaybackIdleSinceMs = 0
      root.barPlaybackElapsedSeconds = 0
    }
  }

  onBarPlaybackOverrideActiveChanged: {
    if (!barPlaybackOverrideActive && barPlaybackMonitorWasIdle) {
      barPlaybackMonitorWasIdle = false
      barPlaybackIdle = false
      barPlaybackIdleSinceMs = 0
      barPlaybackElapsedSeconds = 0
    }
  }

  IdleMonitor {
    id: playbackIdleMonitor
    enabled: root.barPlaybackOverrideActive && root.barDimSeconds > 0
    timeout: Math.max(1, root.barDimSeconds)
    respectInhibitors: false
    onIsIdleChanged: root.updatePlaybackIdle(isIdle)
    Component.onCompleted: if (isIdle) root.updatePlaybackIdle(true)
  }

  Timer {
    interval: 1000
    running: root.barPlaybackOverrideActive && root.barPlaybackMonitorWasIdle
    repeat: true
    onTriggered: root.updatePlaybackIdle(playbackIdleMonitor.isIdle)
  }

  Process {
    id: nativeIdleStatusProcess
    command: ["omarchy-shell", "idle", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyNativeIdleStatus(String(text || ""))
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.endNativeIdle()
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: if (!nativeIdleStatusProcess.running) nativeIdleStatusProcess.running = true
  }

  Process {
    id: readBrightness
    command: ["omarchy-brightness-display"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var current = parseInt(String(text || "").trim(), 10)
        if (isNaN(current) || current <= 1) {
          root.manualTest = false
          return
        }
        if (!root.isIdle && !root.manualTest) {
          root.manualTest = false
          return
        }
        root.savedBrightness = current
        root.isDimmed = true
        var target = Math.max(1, Math.round(current * root.dimPercentage / 100))
        Quickshell.execDetached(["omarchy-brightness-display", "--no-osd", target + "%"])
      }
    }
  }

  readonly property bool isIdle: root.nativeIdle

  onMonitorShouldBeActiveChanged: {
    if (!monitorShouldBeActive) root.restoreIdleEffects()
  }

  IpcHandler {
    target: "dim-it.service"
    function status(): string {
      return JSON.stringify({ enabled: root.enabled, stayAwake: root.stayAwake,
        displayDimSeconds: root.displayDimSeconds, barDimSeconds: root.barDimSeconds,
        monitorOffSeconds: root.monitorOffSeconds, barColorDuringPlayback: root.barColorDuringPlayback,
        playbackActive: root.playbackActive,
        dimPercentage: root.dimPercentage,
        isDimmed: root.isDimmed, isIdle: root.isIdle,
        barTimerIdle: root.nativeIdle || root.barPlaybackIdle,
        barIdleElapsedSeconds: Math.max(root.nativeIdle ? root.nativeIdleElapsedSeconds : 0, root.barPlaybackIdle ? root.barPlaybackElapsedSeconds : 0),
        nativeIdleElapsedSeconds: root.nativeIdleElapsedSeconds,
        nativeLockLatched: root.nativeLockLatched })
    }
    function triggerDim(): void { root.handleDimIdle(true) }
    function triggerActive(): void { root.handleActive() }
  }

  Component.onDestruction: root.restoreIdleEffects()
}
