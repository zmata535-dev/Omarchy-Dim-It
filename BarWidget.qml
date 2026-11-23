import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "dim-it"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/dim-it.json"
  readonly property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  readonly property string stayAwakePath: Quickshell.env("HOME") + "/.local/state/omarchy/indicators/stay-awake"
  property int displayDimSeconds: 60
  property int barDimSeconds: 60
  property int monitorOffSeconds: 0
  property int screensaverSeconds: 150
  property int lockSeconds: 300
  property int dimItScreensaverSeconds: 150
  property int dimItLockSeconds: 300
  property bool dimItLockSettingLoaded: false
  property int nativeScreensaverSeconds: 150
  property int nativeLockSeconds: 300
  property bool nativeIdleConfigLoaded: false
  property int dimPercentage: 25
  property bool barColorDuringPlayback: false
  property bool blinkClockEnabled: true
  property string foregroundMode: "very-dark"
  property bool enabled: true
  property bool stayAwake: false
  property bool popupOpen: false
  property bool testDimActive: false
  property bool settingsLoaded: false
  property bool settingsDirty: false
  property bool nativeConfigDirty: false
  property bool saveError: false
  property bool foregroundSyncPending: false
  property bool idleCycleActive: false
  property int idleElapsedSeconds: 0
  property bool idleStatusLoaded: false
  property bool omarchyIdleEnabled: false
  property bool omarchyIdleStatusLoaded: false
  property bool omarchyIdleTogglePending: false
  property string omarchyIdleToggleError: ""
  readonly property bool opened: popupOpen
  readonly property bool isIdle: idleCycleActive && idleElapsedSeconds >= barDimSeconds
  readonly property bool indicatorDimmed: root.isIdle || root.testDimActive
  readonly property color themeForeground: root.bar ? root.bar.barForeground : Commons.Color.bar.text
  readonly property color themeActiveColor: root.bar ? root.bar.urgent : Commons.Color.urgent
  readonly property string foregroundScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/dim-it/bar-foreground.py"

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }
  function applyDimItServiceStatus(raw) {
    if (!raw || String(raw).length > 8192) return
    var status = null
    try { status = JSON.parse(String(raw)) } catch (e) { status = null }
    if (!status || typeof status !== "object") return
    idleCycleActive = status.isIdle === true || status.barTimerIdle === true
    var elapsed = status.isIdle === true && typeof status.idleElapsedSeconds === "number"
      ? status.idleElapsedSeconds : status.barIdleElapsedSeconds
    idleElapsedSeconds = idleCycleActive && typeof elapsed === "number"
      ? Math.max(0, Math.min(18000, Math.floor(elapsed))) : 0
    if (typeof status.omarchyIdleEnabled === "boolean") {
      omarchyIdleEnabled = status.omarchyIdleEnabled
      omarchyIdleStatusLoaded = status.omarchyIdleStatusLoaded === true
      syncIdleTimerValues()
    }
    idleStatusLoaded = true
  }
  function setOmarchyIdlePluginEnabled(value) {
    if (!omarchyIdleStatusLoaded || omarchyIdleTogglePending) return
    omarchyIdleTogglePending = true
    omarchyIdleToggleError = ""
    idlePluginToggleProcess.command = ["omarchy-shell", "shell", "setPluginEnabled", "omarchy.idle", value ? "true" : "false"]
    idlePluginToggleProcess.running = true
  }
  function testDim() {
    testDimActive = true
    Quickshell.execDetached(["omarchy-shell", "dim-it.service", "triggerDim"])
  }
  function restore() {
    testDimActive = false
    Quickshell.execDetached(["omarchy-shell", "dim-it.service", "triggerActive"])
  }
  function syncBarForeground() {
    if (!root.settingsLoaded) return
    if (foregroundSync.running) {
      foregroundSyncPending = true
      return
    }
    if (root.indicatorDimmed && root.bar) {
      foregroundSync.command = ["python3", root.foregroundScript, "apply", root.foregroundMode,
        String(root.themeForeground), String(root.themeActiveColor)]
    } else {
      foregroundSync.command = ["python3", root.foregroundScript, "restore"]
    }
    foregroundSync.running = true
  }
  onIndicatorDimmedChanged: syncBarForeground()
  onForegroundModeChanged: if (indicatorDimmed) syncBarForeground()
  onThemeForegroundChanged: if (indicatorDimmed) syncBarForeground()
  onThemeActiveColorChanged: if (indicatorDimmed) syncBarForeground()
  onEnabledChanged: {
    if (!enabled) {
      idleCycleActive = false
      idleElapsedSeconds = 0
      testDimActive = false
      popupOpen = false
      Quickshell.execDetached(["omarchy-shell", "dim-it.service", "triggerActive"])
      syncBarForeground()
    }
  }
  function secondsUntilDim(timeoutSeconds) { return Math.max(0, timeoutSeconds - idleElapsedSeconds) }
  function formatSeconds(seconds) {
    if (seconds < 60) return strings.t("time.seconds").arg(seconds)
    var minutes = Math.floor(seconds / 60)
    var remainder = seconds % 60
    return remainder ? strings.t("time.minute_seconds").arg(minutes).arg(remainder) : strings.t(minutes === 1 ? "time.minute" : "time.minutes").arg(minutes)
  }
  function formatTimeout(seconds) {
    return seconds <= 0 ? strings.t("time.off") : formatSeconds(seconds)
  }
  function clampTimeout(seconds, maximum) {
    return Math.max(0, Math.min(maximum, Math.round(Number(seconds) || 0)))
  }
  function syncIdleTimerValues() {
    if (omarchyIdleStatusLoaded && omarchyIdleEnabled && nativeIdleConfigLoaded) {
      screensaverSeconds = nativeScreensaverSeconds
      lockSeconds = nativeLockSeconds
    } else {
      screensaverSeconds = dimItScreensaverSeconds
      lockSeconds = dimItLockSeconds
    }
  }
  function applyConfig(raw) {
    if (settingsDirty) return
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") return
    var legacySeconds = typeof parsed.dimSeconds === "number" && parsed.dimSeconds >= 5 && parsed.dimSeconds <= 3600
      ? Math.round(parsed.dimSeconds) : 60
    displayDimSeconds = typeof parsed.displayDimSeconds === "number" && parsed.displayDimSeconds >= 5 && parsed.displayDimSeconds <= 18000
      ? Math.round(parsed.displayDimSeconds) : legacySeconds
    barDimSeconds = typeof parsed.barDimSeconds === "number" && parsed.barDimSeconds >= 5 && parsed.barDimSeconds <= 18000
      ? Math.round(parsed.barDimSeconds) : legacySeconds
    monitorOffSeconds = typeof parsed.monitorOffSeconds === "number" && parsed.monitorOffSeconds >= 0
      ? clampTimeout(parsed.monitorOffSeconds, 3600) : 0
    if (typeof parsed.dimPercentage === "number" && parsed.dimPercentage >= 1 && parsed.dimPercentage <= 100) dimPercentage = Math.round(parsed.dimPercentage)
    if (typeof parsed.barColorDuringPlayback === "boolean") barColorDuringPlayback = parsed.barColorDuringPlayback
    else if (typeof parsed.playbackTimerEnabled === "boolean") barColorDuringPlayback = parsed.playbackTimerEnabled
    if (typeof parsed.screensaverSeconds === "number" && parsed.screensaverSeconds >= 0) {
      dimItScreensaverSeconds = clampTimeout(parsed.screensaverSeconds, 1800)
    }
    dimItLockSettingLoaded = typeof parsed.lockSeconds === "number" && parsed.lockSeconds >= 0
    if (dimItLockSettingLoaded) dimItLockSeconds = clampTimeout(parsed.lockSeconds, 10800)
    if (typeof parsed.blinkClockEnabled === "boolean") blinkClockEnabled = parsed.blinkClockEnabled
    foregroundMode = parsed.foregroundMode === "black" ? "black" : "very-dark"
    if (typeof parsed.enabled === "boolean") enabled = parsed.enabled
    settingsDirty = false
    syncIdleTimerValues()
  }
  function applyNativeConfig(raw) {
    if (nativeConfigDirty || !String(raw || "").trim()) return
    try {
      var parsed = JSON.parse(String(raw || ""))
      var idle = parsed && parsed.idle && typeof parsed.idle === "object" ? parsed.idle : ({})
      nativeScreensaverSeconds = typeof idle.screensaver === "number" && idle.screensaver >= 0
        ? clampTimeout(idle.screensaver, 1800) : 150
      nativeLockSeconds = typeof idle.lock === "number" && idle.lock >= 0
        ? clampTimeout(idle.lock, 10800) : 300
      nativeIdleConfigLoaded = true
      if (!dimItLockSettingLoaded) dimItLockSeconds = nativeLockSeconds
      syncIdleTimerValues()
      saveError = false
    } catch (e) {
      saveError = true
    }
  }
  function saveConfig() {
    var data = { displayDimSeconds: displayDimSeconds, barDimSeconds: barDimSeconds,
      screensaverSeconds: dimItScreensaverSeconds, lockSeconds: dimItLockSeconds, monitorOffSeconds: monitorOffSeconds,
      dimPercentage: dimPercentage, foregroundMode: foregroundMode,
      barColorDuringPlayback: barColorDuringPlayback, blinkClockEnabled: blinkClockEnabled,
      enabled: enabled }
    var output = JSON.stringify(data, null, 2) + "\n"
    if (configFile && typeof configFile.setText === "function") configFile.setText(output)
    settingsDirty = false
  }
  function saveNativeConfig() {
    try {
      var source = shellConfigFile.text()
      if (!String(source || "").trim()) throw new Error("Shell config is not loaded")
      var parsed = JSON.parse(source)
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Invalid shell config")
      if (!parsed.idle || typeof parsed.idle !== "object" || Array.isArray(parsed.idle)) parsed.idle = ({})
      parsed.idle.screensaver = nativeScreensaverSeconds
      parsed.idle.lock = nativeLockSeconds
      nativeConfigDirty = true
      shellConfigFile.setText(JSON.stringify(parsed, null, 2) + "\n")
      saveError = false
    } catch (e) {
      saveError = true
    }
  }
  function selectDisplayTimeout(seconds) { displayDimSeconds = seconds; settingsDirty = true }
  function selectBarTimeout(seconds) { barDimSeconds = seconds; settingsDirty = true }
  function selectMonitorOffTimeout(seconds) { monitorOffSeconds = clampTimeout(seconds, 3600); settingsDirty = true }
  function selectScreensaverTimeout(seconds) {
    screensaverSeconds = clampTimeout(seconds, 1800)
    if (omarchyIdleStatusLoaded && omarchyIdleEnabled) {
      nativeScreensaverSeconds = screensaverSeconds
      nativeConfigDirty = true
    } else {
      dimItScreensaverSeconds = screensaverSeconds
      settingsDirty = true
    }
  }
  function selectLockTimeout(seconds) {
    lockSeconds = clampTimeout(seconds, 10800)
    if (omarchyIdleStatusLoaded && omarchyIdleEnabled) {
      nativeLockSeconds = lockSeconds
      nativeConfigDirty = true
    } else {
      dimItLockSeconds = lockSeconds
      settingsDirty = true
    }
  }
  function selectLevel(percent) { dimPercentage = percent; settingsDirty = true }
  function saveSettings() { saveConfig(); if (nativeConfigDirty) saveNativeConfig() }
  function restartShell() { Quickshell.execDetached(["omarchy", "restart", "shell"]) }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onSaved: {
      root.settingsDirty = false
      Quickshell.execDetached(["omarchy-shell", "dim-it.service", "reloadSettings"])
    }
    onLoaded: {
      root.applyConfig(text())
      if (!root.settingsLoaded) {
        root.settingsLoaded = true
        root.syncBarForeground()
      }
    }
    onLoadFailed: {
      if (!root.settingsLoaded) {
        root.settingsLoaded = true
        root.syncBarForeground()
      }
    }
  }
  FileView {
    id: shellConfigFile
    path: root.shellConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyNativeConfig(text())
    onLoadFailed: root.saveError = true
    onSaved: {
      root.nativeConfigDirty = false
      root.saveError = false
      Quickshell.execDetached(["omarchy-shell", "shell", "reloadConfig"])
    }
  }
  Process {
    id: foregroundSync
    command: []
    onExited: {
      if (root.foregroundSyncPending) {
        root.foregroundSyncPending = false
        root.syncBarForeground()
      }
    }
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
    interval: 1500
    running: true
    repeat: true
    onTriggered: { root.configFile.reload(); stayAwakeFile.reload() }
  }
  Process {
    id: dimItServiceStatusProcess
    command: ["omarchy-shell", "dim-it.service", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDimItServiceStatus(String(text || ""))
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.idleCycleActive = false
        root.idleElapsedSeconds = 0
        root.idleStatusLoaded = false
      }
    }
  }
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: if (!dimItServiceStatusProcess.running) dimItServiceStatusProcess.running = true
  }
  onStayAwakeChanged: {
    if (stayAwake) {
      idleCycleActive = false
      idleElapsedSeconds = 0
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰃞"
    slotSize: Style.bar.iconSlot
    active: root.indicatorDimmed
    useActiveColor: false
    foreground: root.enabled ? root.themeForeground : Commons.Color.muted
    tooltipText: root.omarchyIdleEnabled ? strings.t("tooltip.omarchy_idle")
      : !root.omarchyIdleStatusLoaded ? strings.t("tooltip.checking_idle")
      : !root.enabled ? strings.t("tooltip.disabled")
      : root.stayAwake ? strings.t("tooltip.stay_awake")
      : root.testDimActive ? strings.t("tooltip.test_dim")
      : root.isIdle ? strings.t("tooltip.idle")
      : strings.t("tooltip.after").arg(root.formatSeconds(root.barDimSeconds))
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (!root.omarchyIdleStatusLoaded || root.omarchyIdleEnabled) return
        root.enabled = !root.enabled
        root.saveConfig()
      }
      else root.toggle()
    }
  }

  Process {
    id: idlePluginToggleProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var response = String(text || "").trim()
        if (response !== "ok") root.omarchyIdleToggleError = response || strings.t("panel.idle_toggle_error")
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.omarchyIdleToggleError)
        root.omarchyIdleToggleError = strings.t("panel.idle_toggle_error")
      root.omarchyIdleTogglePending = false
    }
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
    function toggle(): void { root.broadcast("toggle") }
    function testDim(): void { root.broadcast("testDim") }
    function restore(): void { root.broadcast("restore") }
    function status(): string {
      return JSON.stringify({ isIdle: root.isIdle, testDimActive: root.testDimActive,
        foregroundMode: root.foregroundMode, displayDimSeconds: root.displayDimSeconds,
        barDimSeconds: root.barDimSeconds, monitorOffSeconds: root.monitorOffSeconds,
        lockSeconds: root.lockSeconds, screensaverSeconds: root.screensaverSeconds, themeForeground: String(root.themeForeground),
        blinkClockEnabled: root.blinkClockEnabled,
        barActive: root.bar ? String(root.bar.urgent) : "",
        idleCycleActive: root.idleCycleActive,
        idleElapsedSeconds: root.idleElapsedSeconds,
        idleStatusLoaded: root.idleStatusLoaded,
        omarchyIdleEnabled: root.omarchyIdleEnabled,
        omarchyIdleStatusLoaded: root.omarchyIdleStatusLoaded })
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    triggerMode: "hover"
    onOpenChanged: {
      if (root.popupOpen !== open) root.popupOpen = open
      if (!open && root.testDimActive) root.restore()
    }
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight)

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(4)

      RowLayout {
        width: parent.width
        spacing: Style.space(10)
        Text {
          text: "󰃞"
          color: Commons.Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          Layout.alignment: Qt.AlignVCenter
        }
        Column {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: strings.t("panel.title")
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: !root.enabled ? strings.t("panel.paused")
              : root.stayAwake ? strings.t("panel.stay_awake")
              : strings.t("panel.after_enabled")
                .arg(root.formatSeconds(root.secondsUntilDim(root.displayDimSeconds)))
                .arg(root.formatSeconds(root.secondsUntilDim(root.barDimSeconds)))
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
        ToggleSwitch {
          id: enabledSwitch
          Layout.alignment: Qt.AlignVCenter
          checked: root.enabled
          interactive: true
          foreground: Commons.Color.popups.text
          accent: Commons.Color.accent
          onToggled: { root.enabled = !root.enabled; root.saveConfig() }
        }
      }

      PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)
        Column {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(1)
          Text {
            textFormat: Text.PlainText
            text: strings.t("panel.omarchy_idle")
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Text {
            visible: root.omarchyIdleEnabled || !!root.omarchyIdleToggleError || !root.omarchyIdleStatusLoaded
            textFormat: Text.PlainText
            text: root.omarchyIdleToggleError ? root.omarchyIdleToggleError
              : !root.omarchyIdleStatusLoaded ? strings.t("panel.idle_status_loading")
              : strings.t("panel.idle_enabled_hint")
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
        ToggleSwitch {
          id: idlePluginSwitch
          Layout.alignment: Qt.AlignVCenter
          checked: root.omarchyIdleEnabled
          interactive: root.omarchyIdleStatusLoaded && !root.omarchyIdleTogglePending
          busy: root.omarchyIdleTogglePending
          onToggled: root.setOmarchyIdlePluginEnabled(!root.omarchyIdleEnabled)
        }
      }

      PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }

      TimerSetting {
        bar: root.bar
        label: strings.t("panel.bar_timer")
        displayValue: root.formatTimeout(root.barDimSeconds)
        value: root.barDimSeconds
        minimum: 5
        maximum: 45
        step: 1
        onSettingChanged: function(nextValue) { root.selectBarTimeout(nextValue) }
      }

      Column {
        width: parent.width
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          text: strings.t("panel.foreground")
          color: Commons.Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Row {
          spacing: Style.space(7)
          Button {
            text: strings.t("panel.dark_gray")
            selected: root.foregroundMode === "very-dark"
            active: selected
            bordered: true
            foreground: Commons.Color.popups.text
            onClicked: { root.foregroundMode = "very-dark"; root.settingsDirty = true }
          }
          Button {
            text: strings.t("panel.black")
            selected: root.foregroundMode === "black"
            active: selected
            bordered: true
            foreground: Commons.Color.popups.text
            onClicked: { root.foregroundMode = "black"; root.settingsDirty = true }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: (parent.width - Style.space(8)) / 2
          spacing: Style.space(4)
          Text {
            width: parent.width - playbackTimerSwitch.width - Style.space(4)
            textFormat: Text.PlainText
            text: strings.t("panel.bar_playback")
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            wrapMode: Text.WordWrap
            anchors.verticalCenter: parent.verticalCenter
          }
          ToggleSwitch {
            id: playbackTimerSwitch
            checked: root.barColorDuringPlayback
            anchors.verticalCenter: parent.verticalCenter
            onToggled: { root.barColorDuringPlayback = !root.barColorDuringPlayback; root.settingsDirty = true }
          }
        }

        Row {
          width: (parent.width - Style.space(8)) / 2
          spacing: Style.space(4)
          Text {
            width: parent.width - blinkClockSwitch.width - Style.space(4)
            textFormat: Text.PlainText
            text: strings.t("panel.blink_clock")
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            wrapMode: Text.WordWrap
            anchors.verticalCenter: parent.verticalCenter
          }
          ToggleSwitch {
            id: blinkClockSwitch
            checked: root.blinkClockEnabled
            anchors.verticalCenter: parent.verticalCenter
            onToggled: { root.blinkClockEnabled = !root.blinkClockEnabled; root.settingsDirty = true }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        TimerSetting {
          bar: root.bar
          settingWidth: (parent.width - Style.space(8)) / 2
          label: strings.t("panel.display_timer")
          displayValue: root.formatTimeout(root.displayDimSeconds)
          value: root.displayDimSeconds
          minimum: 5
          maximum: 300
          step: 5
          onSettingChanged: function(nextValue) { root.selectDisplayTimeout(nextValue) }
        }
        TimerSetting {
          bar: root.bar
          settingWidth: (parent.width - Style.space(8)) / 2
          label: strings.t("panel.brightness")
          displayValue: root.dimPercentage + "%"
          value: root.dimPercentage
          minimum: 1
          maximum: 100
          step: 1
          onSettingChanged: function(nextValue) { root.selectLevel(nextValue) }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        TimerSetting {
          bar: root.bar
          settingWidth: (parent.width - Style.space(8)) / 2
          label: strings.t("panel.screensaver_timer")
          displayValue: root.formatTimeout(root.screensaverSeconds)
          value: root.screensaverSeconds
          minimum: 0
          maximum: 1800
          step: 15
          onSettingChanged: function(nextValue) { root.selectScreensaverTimeout(nextValue) }
        }
        TimerSetting {
          bar: root.bar
          settingWidth: (parent.width - Style.space(8)) / 2
          label: strings.t("panel.monitor_off_timer")
          displayValue: root.formatTimeout(root.monitorOffSeconds)
          value: root.monitorOffSeconds
          minimum: 0
          maximum: 3600
          step: 15
          onSettingChanged: function(nextValue) { root.selectMonitorOffTimeout(nextValue) }
        }
      }

      TimerSetting {
        bar: root.bar
        label: strings.t("panel.omarchy_lock_timer")
        displayValue: root.formatTimeout(root.lockSeconds)
        value: root.lockSeconds
        minimum: 0
        maximum: 10800
        step: 30
        onSettingChanged: function(nextValue) { root.selectLockTimeout(nextValue) }
      }

      Text {
        width: parent.width
        visible: root.stayAwake || root.saveError
        textFormat: Text.PlainText
        text: root.stayAwake
          ? strings.t("panel.stay_awake")
          : strings.t("panel.save_error")
        color: Commons.Color.popups.text
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)
        Button {
          iconText: "󰆓"
          tooltipText: strings.t("panel.save")
          Layout.minimumWidth: Style.space(34)
          Layout.preferredWidth: Style.space(34)
          Layout.maximumWidth: Style.space(34)
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.saveSettings()
        }
        Button {
          iconText: "󰑐"
          tooltipText: strings.t("panel.restart_shell")
          Layout.minimumWidth: Style.space(34)
          Layout.preferredWidth: Style.space(34)
          Layout.maximumWidth: Style.space(34)
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.restartShell()
        }
        Button {
          iconText: "󰐊"
          tooltipText: strings.t("panel.test")
          Layout.minimumWidth: Style.space(34)
          Layout.preferredWidth: Style.space(34)
          Layout.maximumWidth: Style.space(34)
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.testDim()
        }
        Button {
          iconText: "󰓛"
          tooltipText: strings.t("panel.restore")
          Layout.minimumWidth: Style.space(34)
          Layout.preferredWidth: Style.space(34)
          Layout.maximumWidth: Style.space(34)
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.restore()
        }
        Item { Layout.fillWidth: true }
        Button {
          iconText: "×"
          tooltipText: strings.t("panel.close")
          Layout.minimumWidth: Style.space(34)
          Layout.preferredWidth: Style.space(34)
          Layout.maximumWidth: Style.space(34)
          bordered: true
          foreground: Commons.Color.popups.text
          onClicked: root.close()
        }
      }
    }
  }

  Component.onDestruction: {
    if (root.testDimActive)
      Quickshell.execDetached(["omarchy-shell", "dim-it.service", "triggerActive"])
    Quickshell.execDetached(["python3", root.foregroundScript, "restore"])
  }
}
