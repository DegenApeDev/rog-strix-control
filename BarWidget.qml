import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "xyz.degendev.rog-strix-control"

  property var controlService: null
  readonly property var device: controlService ? controlService.device : ({profile:"",gpuState:"",gpuWatts:"",cpuTemp:-1,dgpuDisabled:false})

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function plainText(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function gpuLabel() {
    if (device.dgpuDisabled) return "RTX OFF"
    if (device.gpuState !== "active") return "RTX IDLE"
    return device.gpuWatts ? Number(device.gpuWatts).toFixed(1) + "W" : "RTX ON"
  }

  function refresh() {
    syncService()
    if (controlService && typeof controlService.refresh === "function") controlService.refresh(false)
    if (panelLoader.item && typeof panelLoader.item.refresh === "function") panelLoader.item.refresh()
  }

  function syncService() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
      root.controlService = root.bar.shell.serviceFor(root.moduleName)
    if (panelLoader.item) panelLoader.item.controlService = root.controlService
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.controlService = root.controlService
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: { syncService(); injectPanel() }
  onSettingsChanged: injectPanel()

  Timer { interval:2000; running:true; repeat:true; triggeredOnStart:true; onTriggered:root.syncService() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "xyz.degendev.rog-strix-control"
    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.plainText(root.gpuLabel())
    fontSize: Style.font.caption
    foreground: root.device.gpuState === "active" ? Color.accent : Color.muted
    tooltipText: root.plainText("ROG Strix · " + (root.device.profile || "unknown") + " · " + (root.device.cpuTemp >= 0 ? root.device.cpuTemp + "°C" : "--"))
    onPressed: function(buttonCode) { if (buttonCode === Qt.LeftButton) root.toggle() }
  }
}
