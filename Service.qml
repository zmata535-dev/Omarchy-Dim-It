import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/dim-it.json"
  readonly property string stayAwakePath: home + "/.local/state/omarchy/indicators/stay-awake"

  property int displayDimSeconds: 60
  property int barDimSeconds: 60
  property int screensaverSeconds: 150
  property int monitorOffSeconds: 0
  property int lockSeconds: 300
  property bool actionIdle: false
  property double actionIdleSinceMs: 0
  property int actionIdleElapsedSeconds: 0
  property bool barPlaybackIdle: false
  property double barPlaybackIdleSinceMs: 0
  property int barPlaybackElapsedSeconds: 0
  property bool screensaverStartedThisCycle: false
  property bool screensaverLaunchPending: false
  property var screensaverWindows: ({})
  property int screensaverWindowCount: 0
  property int dimPercentage: 25
  property bool enabled: true
  property bool barColorDuringPlayback: false
  property bool stayAwake: false
  property int savedBrightness: 0
  property bool isDimmed: false
  property bool manualTest: false
  property bool monitorWasTurnedOff: false
  property bool lockStartedThisCycle: false
  property bool omarchyIdleEnabled: false
  property bool omarchyIdleStatusLoaded: false

  readonly property bool monitorShouldBeActive: enabled && !stayAwake && omarchyIdleStatusLoaded
  readonly property int firstActionTimeoutSeconds: {
    var delays = [displayDimSeconds, barDimSeconds, monitorOffSeconds]
    if (!omarchyIdleEnabled) delays.push(screensaverSeconds, lockSeconds)
    var first = Infinity
    for (var i = 0; i < delays.length; i++)
      if (delays[i] > 0 && delays[i] < first) first = delays[i]
    return isFinite(first) ? first : 0
  }
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
    var previousDimPercentage = dimPercentage
    displayDimSeconds = typeof parsed.displayDimSeconds === "number" && parsed.displayDimSeconds >= 5 && parsed.displayDimSeconds <= 18000
      ? Math.round(parsed.displayDimSeconds)
      : typeof parsed.dimSeconds === "number" && parsed.dimSeconds >= 5 && parsed.dimSeconds <= 3600
        ? Math.round(parsed.dimSeconds) : 60
    barDimSeconds = typeof parsed.barDimSeconds === "number" && parsed.barDimSeconds >= 5 && parsed.barDimSeconds <= 18000
      ? Math.round(parsed.barDimSeconds)
      : typeof parsed.dimSeconds === "number" && parsed.dimSeconds >= 5 && parsed.dimSeconds <= 3600
        ? Math.round(parsed.dimSeconds) : 60
    screensaverSeconds = typeof parsed.screensaverSeconds === "number" && parsed.screensaverSeconds >= 0
      ? Math.round(parsed.screensaverSeconds) : screensaverSeconds
    screensaverSeconds = Math.min(1800, screensaverSeconds)
    monitorOffSeconds = typeof parsed.monitorOffSeconds === "number" && parsed.monitorOffSeconds >= 0
      ? Math.min(3600, Math.round(parsed.monitorOffSeconds)) : 0
    lockSeconds = typeof parsed.lockSeconds === "number" && parsed.lockSeconds >= 0
      ? Math.min(10800, Math.round(parsed.lockSeconds)) : lockSeconds
    if (typeof parsed.dimPercentage === "number" && parsed.dimPercentage >= 1 && parsed.dimPercentage <= 100)
      dimPercentage = Math.round(parsed.dimPercentage)
    if (typeof parsed.enabled === "boolean") enabled = parsed.enabled
    if (typeof parsed.barColorDuringPlayback === "boolean") barColorDuringPlayback = parsed.barColorDuringPlayback
    else if (typeof parsed.playbackTimerEnabled === "boolean") barColorDuringPlayback = parsed.playbackTimerEnabled

    if (root.actionIdle) {
      if (root.isDimmed && !root.manualTest && root.actionIdleElapsedSeconds < root.displayDimSeconds) {
        root.handleActive()
      } else if (root.isDimmed && root.savedBrightness > 0 && dimPercentage !== previousDimPercentage) {
        var target = Math.max(1, Math.round(root.savedBrightness * root.dimPercentage / 100))
        Quickshell.execDetached(["omarchy-brightness-display", "--no-osd", target + "%"])
      }
      if (root.monitorWasTurnedOff
          && (root.monitorOffSeconds <= 0 || root.actionIdleElapsedSeconds < root.monitorOffSeconds)) {
        root.monitorWasTurnedOff = false
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "enable" })'])
      }
      root.applyIdleActions()
    }
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

  function applyPluginStatus(raw) {
    var plugins = null
    try { plugins = JSON.parse(String(raw)) } catch (e) { plugins = null }
    if (!Array.isArray(plugins)) {
      omarchyIdleStatusLoaded = false
      return
    }
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && plugins[i].id === "omarchy.idle") {
        omarchyIdleEnabled = plugins[i].enabled === true
        omarchyIdleStatusLoaded = true
        return
      }
    }
    omarchyIdleStatusLoaded = false
  }

  Process {
    id: pluginStatusProcess
    command: ["omarchy-shell", "shell", "listPlugins"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPluginStatus(String(text || ""))
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.omarchyIdleStatusLoaded = false
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: if (!pluginStatusProcess.running) pluginStatusProcess.running = true
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

  function resetScreensaverWindows() {
    root.screensaverWindows = ({})
    root.screensaverWindowCount = 0
  }

  function beginActionIdle() {
    if (root.actionIdle || root.firstActionTimeoutSeconds <= 0) return
    root.actionIdle = true
    root.actionIdleSinceMs = Date.now() - root.firstActionTimeoutSeconds * 1000
    root.actionIdleElapsedSeconds = root.firstActionTimeoutSeconds
    root.screensaverStartedThisCycle = false
    root.screensaverLaunchPending = false
    root.monitorWasTurnedOff = false
    root.lockStartedThisCycle = false
    root.resetScreensaverWindows()
    root.applyIdleActions()
  }

  function endActionIdle(reason) {
    var hadActionState = root.actionIdle || root.screensaverStartedThisCycle || root.screensaverLaunchPending
    root.actionIdle = false
    root.actionIdleSinceMs = 0
    root.actionIdleElapsedSeconds = 0
    root.screensaverStartedThisCycle = false
    root.screensaverLaunchPending = false
    root.lockStartedThisCycle = false
    screensaverLaunchTimer.stop()
    screensaverLaunchGraceTimer.stop()
    root.resetScreensaverWindows()
    if (hadActionState) root.handleActive()
    if (root.monitorWasTurnedOff) {
      root.monitorWasTurnedOff = false
      Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "enable" })'])
    }
  }

  function handleActionMonitorActive() {
    if (!root.actionIdle) return
    if (root.screensaverStartedThisCycle
        && (root.screensaverWindowCount > 0 || screensaverLaunchGraceTimer.running)) return
    root.endActionIdle("activity")
  }

  function setScreensaverWindow(address, visible) {
    var key = String(address || "")
    if (!key) return
    var next = ({})
    var count = 0
    for (var existing in root.screensaverWindows) {
      if (existing !== key && root.screensaverWindows[existing]) {
        next[existing] = true
        count++
      }
    }
    if (visible) {
      next[key] = true
      count++
    }
    root.screensaverWindows = next
    root.screensaverWindowCount = count
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    var parts = []
    try { parts = event && event.parse ? event.parse(name === "openwindow" ? 4 : 1) : [] } catch (e) {}
    if (name === "openwindow" && String(parts[2] || "") === "org.omarchy.screensaver") {
      root.setScreensaverWindow(String(parts[0] || ""), true)
      root.screensaverStartedThisCycle = true
      root.screensaverLaunchPending = false
      screensaverLaunchTimer.stop()
      screensaverLaunchGraceTimer.stop()
    } else if (name === "closewindow") {
      var address = String(parts[0] || "")
      if (root.screensaverWindows[address]) {
        root.setScreensaverWindow(address, false)
        if (root.actionIdle && root.screensaverStartedThisCycle && root.screensaverWindowCount === 0)
          root.endActionIdle("screensaver-dismissed")
      }
    }
  }

  function restoreIdleEffects() {
    root.endActionIdle("disabled")
    root.barPlaybackMonitorWasIdle = false
    root.barPlaybackIdle = false
    root.barPlaybackIdleSinceMs = 0
    root.barPlaybackElapsedSeconds = 0
    root.handleActive()
    if (root.monitorWasTurnedOff) {
      root.monitorWasTurnedOff = false
      Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "enable" })'])
    }
  }

  function applyIdleActions() {
    if (!root.actionIdle || !root.monitorShouldBeActive) return
    if (!root.isDimmed && root.displayDimSeconds > 0 && root.actionIdleElapsedSeconds >= root.displayDimSeconds)
      root.handleDimIdle(false)
    if (!root.omarchyIdleEnabled && root.screensaverSeconds > 0
        && root.actionIdleElapsedSeconds >= root.screensaverSeconds
        && !root.screensaverStartedThisCycle && !root.screensaverLaunchPending) {
      root.screensaverLaunchPending = true
      screensaverLaunchGraceTimer.restart()
      screensaverLaunchTimer.restart()
    }
    if (!root.omarchyIdleEnabled && root.lockSeconds > 0
        && root.actionIdleElapsedSeconds >= root.lockSeconds
        && !root.lockStartedThisCycle) {
      root.lockStartedThisCycle = true
      root.screensaverStartedThisCycle = false
      root.screensaverLaunchPending = false
      screensaverLaunchTimer.stop()
      screensaverLaunchGraceTimer.stop()
      lockStatusProcess.command = ["omarchy-shell", "lock", "isLocked"]
      lockStatusProcess.running = true
    }
    if (!root.monitorWasTurnedOff && root.monitorOffSeconds > 0 && root.actionIdleElapsedSeconds >= root.monitorOffSeconds) {
      root.monitorWasTurnedOff = true
      Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "disable" })'])
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

  onOmarchyIdleEnabledChanged: {
    if (omarchyIdleEnabled) {
      screensaverLaunchTimer.stop()
      screensaverLaunchGraceTimer.stop()
      screensaverLaunchPending = false
    }
    if (actionIdle) applyIdleActions()
  }

  IdleMonitor {
    id: actionIdleMonitor
    enabled: root.monitorShouldBeActive && root.firstActionTimeoutSeconds > 0
    timeout: Math.max(1, root.firstActionTimeoutSeconds)
    respectInhibitors: true
    onIsIdleChanged: if (isIdle) root.beginActionIdle(); else root.handleActionMonitorActive()
    Component.onCompleted: if (isIdle) root.beginActionIdle()
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
    running: root.actionIdle || (root.barPlaybackOverrideActive && root.barPlaybackMonitorWasIdle)
    repeat: true
    onTriggered: {
      if (root.actionIdle) {
        root.actionIdleElapsedSeconds = Math.max(0,
          Math.floor((Date.now() - root.actionIdleSinceMs) / 1000))
        root.applyIdleActions()
      }
      if (root.barPlaybackOverrideActive)
        root.updatePlaybackIdle(playbackIdleMonitor.isIdle)
    }
  }

  Timer {
    id: screensaverLaunchTimer
    interval: 1200
    repeat: false
    onTriggered: {
      if (!root.actionIdle || !root.screensaverLaunchPending) return
      root.screensaverStartedThisCycle = true
      root.screensaverLaunchPending = false
      Quickshell.execDetached(["omarchy-launch-screensaver"])
    }
  }

  Timer {
    id: screensaverLaunchGraceTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (!root.screensaverWindowCount && !actionIdleMonitor.isIdle)
        root.endActionIdle("screensaver-not-running")
      else if (!root.screensaverWindowCount)
        root.screensaverStartedThisCycle = false
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
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

  Process {
    id: lockStatusProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim() === "true") return
        lockProcess.command = ["omarchy-system-lock"]
        lockProcess.running = true
      }
    }
  }

  Process {
    id: lockProcess
    command: []
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) console.warn("Dim-It: native lock command failed with exit code " + exitCode)
    }
  }

  readonly property bool isIdle: root.actionIdle

  onMonitorShouldBeActiveChanged: {
    if (!monitorShouldBeActive) root.restoreIdleEffects()
  }

  IpcHandler {
    target: "dim-it.service"
    function reloadSettings(): void { root.configFile.reload() }
    function status(): string {
      return JSON.stringify({ enabled: root.enabled, stayAwake: root.stayAwake,
        omarchyIdleEnabled: root.omarchyIdleEnabled,
        omarchyIdleStatusLoaded: root.omarchyIdleStatusLoaded,
        monitorShouldBeActive: root.monitorShouldBeActive,
        monitorWasTurnedOff: root.monitorWasTurnedOff,
        displayDimSeconds: root.displayDimSeconds, barDimSeconds: root.barDimSeconds,
        monitorOffSeconds: root.monitorOffSeconds, barColorDuringPlayback: root.barColorDuringPlayback,
        screensaverSeconds: root.screensaverSeconds,
        lockSeconds: root.lockSeconds,
        lockStartedThisCycle: root.lockStartedThisCycle,
        playbackActive: root.playbackActive,
        dimPercentage: root.dimPercentage,
        isDimmed: root.isDimmed, isIdle: root.isIdle,
        barTimerIdle: root.barPlaybackIdle || (root.actionIdle && root.actionIdleElapsedSeconds >= root.barDimSeconds),
        barIdleElapsedSeconds: Math.max(
          root.barPlaybackIdle ? root.barPlaybackElapsedSeconds : 0,
          root.actionIdle ? root.actionIdleElapsedSeconds : 0
        ),
        idleElapsedSeconds: root.actionIdleElapsedSeconds })
    }
    function triggerDim(): void { root.handleDimIdle(true) }
    function triggerActive(): void { root.handleActive() }
  }

  Component.onDestruction: root.restoreIdleEffects()
}
