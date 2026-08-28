import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "xyz.degendev.rog-strix-control"
  ipcTarget: "xyz.degendev.rog-strix-control"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var controlService: null
  readonly property var barIdentity: hostWidget || root

  property string pciAddr: setting("pci", "auto")
  property int pollMs: setting("intervalMs", 5000)
  readonly property string helperPath: Qt.resolvedUrl("rog-strix-control").toString().replace(/^file:\/\//, "")
  readonly property string auraPreset1: setting("auraPreset1", "39ff14")
  readonly property string auraPreset2: setting("auraPreset2", "ff1818")
  readonly property var device: controlService ? controlService.device : emptyDevice()
  property string actionStatus: ""
  property bool busy: false
  property string auraColor: "39ff14"
  property string auraSpeed: "med"
  property string auraDirection: "right"
  property string auraZone: "global"
  property string armedGpuMode: ""
  readonly property var control: controlService ? controlService.control : ({automation:{enabled:false},presets:[],gameRules:[],runtime:{}})
  readonly property var health: controlService ? controlService.health : ({asusd:"unknown",supergfxd:"unknown",nvidia:"unknown",sensorCount:0,cpuPower:"unknown",issues:[],healthy:false})
  property int currentView: 0
  property string actionPhase: "IDLE"
  property var permissions: ({sensor:false,readable:false,ruleInstalled:false,groupExists:false,wheelMember:false,energyPath:"",canInstall:false,needsSetup:false})
  property string permissionArm: ""
  property string permissionMode: ""
  property int permissionStep: 0
  readonly property string ruleSource: Qt.resolvedUrl("70-rog-strix-energy.rules").toString().replace(/^file:\/\//, "")
  readonly property string safeEnergyPath: /^\/sys\/class\/powercap\/intel-rapl\/intel-rapl:[0-9]+\/energy_uj$/.test(String(permissions.energyPath||"")) ? permissions.energyPath : ""
  property string selectedPreset: "daily"
  property string newPresetName: "custom"
  property string gameExecutable: ""
  property bool gameBoostExtras: true
  property var cpuTempHistory: []
  property var gpuTempHistory: []
  property var cpuFanHistory: []
  property var gpuPowerHistory: []
  property var gpuFanHistory: []
  property var cpuPowerHistory: []
  property real cpuPowerWatts: -1
  property real previousCpuEnergy: -1
  property real previousCpuSampleMs: -1
  property int graphEpoch: 0

  function emptyDevice() {
    return {vendor:"",model:"",board:"",profile:"",profiles:[],acProfile:"",batteryProfile:"",ledBrightness:"",auraMode:"",auraModes:[],gpuState:"",gpuWatts:"",gpuTemp:-1,gpuUtil:-1,gpuMemory:-1,gpuClients:0,gpuMode:"",gpuPower:"",gpuPendingAction:"",gpuPendingMode:"",gpuModes:[],cpuFan:-1,gpuFan:-1,cpuTemp:-1,igpuTemp:-1,cpuFreqMHz:-1,cpuEnergyUj:-1,cpuEnergyMaxUj:-1,cpuPowerWatts:-1,sampledMs:-1,igpuWatts:"",batteryWatts:"",batteryMinutes:-1,batteryLimit:-1,batteryPct:-1,batteryStatus:"",acOnline:false,panelOd:false,bootSound:false,dgpuDisabled:false,asusctlReady:false,supergfxInstalled:false,supergfxReady:false,capabilities:{aura:false,auraZones:false,battery:false,panelOd:false,bootSound:false,fans:false,cpuPower:false,supergfx:false},helperVersion:"5.1.0"}
  }
  function richTextEscape(value) { return String(value).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/\"/g,"&quot;").replace(/'/g,"&#39;") }
  function open() { refresh(); root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function closeForPopoutSwitch() { root.close() }
  function refresh() { if (controlService && typeof controlService.refresh === "function") controlService.refresh(opened); if(!permissionProbe.running)permissionProbe.running=true }
  function presetNames() { var out=[]; for(var i=0;i<(control.presets||[]).length;i++) out.push(control.presets[i].name); return out }
  function selectedPresetData() { for(var i=0;i<(control.presets||[]).length;i++) if(control.presets[i].name===selectedPreset)return control.presets[i]; return ({}) }
  function runAction(name, args) {
    if (busy) return
    busy = true; actionPhase = "APPLYING"; actionStatus = "working…"
    actionProc.command = [helperPath, "action", name].concat(args || [])
    actionProc.running = true
  }
  function pushHistory(values, value) {
    var next = values.slice(Math.max(0, values.length - 59))
    next.push(Number(value) >= 0 ? Number(value) : 0)
    return next
  }
  function sampleHistory() {
    if (device.cpuPowerWatts >= 0) {
      cpuPowerWatts = device.cpuPowerWatts
    } else if (device.cpuEnergyUj >= 0 && previousCpuEnergy >= 0 && device.sampledMs > previousCpuSampleMs) {
      var delta = device.cpuEnergyUj - previousCpuEnergy
      if (delta < 0 && device.cpuEnergyMaxUj > 0) delta += device.cpuEnergyMaxUj
      cpuPowerWatts = delta / (device.sampledMs - previousCpuSampleMs) / 1000
    } else cpuPowerWatts = -1
    previousCpuEnergy = device.cpuEnergyUj; previousCpuSampleMs = device.sampledMs
    cpuTempHistory = pushHistory(cpuTempHistory, device.cpuTemp)
    gpuTempHistory = pushHistory(gpuTempHistory, device.gpuTemp)
    cpuFanHistory = pushHistory(cpuFanHistory, device.cpuFan)
    gpuFanHistory = pushHistory(gpuFanHistory, device.gpuFan)
    cpuPowerHistory = pushHistory(cpuPowerHistory, cpuPowerWatts)
    gpuPowerHistory = pushHistory(gpuPowerHistory, Number(device.gpuWatts || 0))
    graphEpoch++
  }
  function gpuLabel() {
    if (device.dgpuDisabled) return "RTX OFF"
    if (device.gpuState !== "active") return "RTX IDLE"
    return device.gpuWatts ? Number(device.gpuWatts).toFixed(1) + "W" : "RTX ON"
  }
  function boolLabel(value) { return value ? "ON" : "OFF" }
  function batteryTimeLabel() {
    if (device.acOnline) return "AC"
    if (device.batteryMinutes < 0) return "--"
    return Math.floor(device.batteryMinutes / 60) + "h " + (device.batteryMinutes % 60) + "m"
  }
  function validColor(value) { return /^[0-9a-fA-F]{6}$/.test(String(value || "")) }
  function setPluginSetting(key, value) {
    var next = ({})
    for (var current in settings) next[current] = settings[current]
    next[key] = value; settings = next
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, settings)
    actionStatus = key + " saved"; statusTimer.restart()
  }
  function requestGpuMode(mode) {
    if (armedGpuMode !== mode) { armedGpuMode = mode; gpuArmTimer.restart(); actionStatus = "press " + mode.toUpperCase() + " again to confirm"; statusTimer.restart(); return }
    armedGpuMode = ""; runAction("gpu-mode", [mode])
  }
  function requestPermissionChange(mode) {
    if (permissionArm !== mode) { permissionArm=mode; permissionArmTimer.restart(); actionStatus=(mode==="install"?"Grant wheel read access":"Remove CPU-power permission")+" — press again to confirm"; return }
    permissionArm=""; permissionMode=mode; permissionStep=0; busy=true; actionPhase="AUTHORIZING"; runPermissionStep()
  }
  function permissionCommand() {
    if(permissionMode==="install") {
      if(permissionStep===0)return ["pkexec","/usr/bin/install","-o","root","-g","root","-m","0644",ruleSource,"/etc/udev/rules.d/70-rog-strix-energy.rules"]
      if(permissionStep===1)return ["pkexec","/usr/bin/udevadm","control","--reload-rules"]
      if(permissionStep===2&&safeEnergyPath)return ["pkexec","/usr/bin/chgrp","wheel",safeEnergyPath]
      if(permissionStep===3&&safeEnergyPath)return ["pkexec","/usr/bin/chmod","0440",safeEnergyPath]
    } else {
      if(permissionStep===0)return ["pkexec","/usr/bin/unlink","/etc/udev/rules.d/70-rog-strix-energy.rules"]
      if(permissionStep===1)return ["pkexec","/usr/bin/udevadm","control","--reload-rules"]
      if(permissionStep===2&&safeEnergyPath)return ["pkexec","/usr/bin/chgrp","root",safeEnergyPath]
      if(permissionStep===3&&safeEnergyPath)return ["pkexec","/usr/bin/chmod","0400",safeEnergyPath]
    }
    return []
  }
  function runPermissionStep() {
    var next=permissionCommand()
    if(next.length===0){finishPermissionWorkflow();return}
    permissionProcess.command=next; permissionProcess.running=true
  }
  function finishPermissionWorkflow() {
    actionPhase="VERIFYING"; actionStatus="Re-checking CPU-power permissions"; if(!permissionProbe.running)permissionProbe.running=true
  }
  function completePermissionVerification(result) {
    if(!permissionMode)return
    var success=permissionMode==="install"?(result.ruleInstalled&&result.readable):(!result.ruleInstalled&&!result.readable)
    busy=false; actionPhase=success?"VERIFIED":"FAILED"
    actionStatus=success?(permissionMode==="install"?"CPU watts enabled with wheel read-only access":"CPU-watts rule removed and root-only access restored"):(permissionMode==="install"?"Rule installed but the energy counter is still unreadable":"Rule removal could not be fully verified")
    permissionMode=""; statusTimer.restart(); if(controlService&&typeof controlService.refresh==="function")controlService.refresh(true)
  }

  onDeviceChanged: sampleHistory()
  Process {
    id: actionProc
    command: []
    stdout: SplitParser { onRead: function(line) { if (String(line).trim()) root.actionStatus = String(line) } }
    stderr: SplitParser { onRead: function(line) { if (String(line).indexOf("[WARN") !== 0) root.actionStatus = String(line) } }
    onExited: function(code) { root.busy = false; root.actionPhase = code === 0 ? "APPLIED" : "FAILED"; root.actionStatus = code === 0 ? (root.actionStatus === "working…" ? "setting applied" : root.actionStatus) : (root.actionStatus === "working…" ? "action failed; inspect the message and current state" : root.actionStatus); statusTimer.restart(); Qt.callLater(root.refresh) }
  }
  Process {
    id:permissionProbe; command:[root.helperPath,"permissions"]
    stdout:StdioCollector { waitForEnd:true; onStreamFinished:{try{var result=JSON.parse(text);root.permissions=result;root.completePermissionVerification(result)}catch(error){}} }
  }
  Process {
    id:permissionProcess; command:[]
    stderr:SplitParser { onRead:function(line){if(String(line).trim())root.actionStatus=String(line)} }
    onExited:function(code){if(code!==0){root.busy=false;root.actionPhase="FAILED";root.actionStatus=root.actionStatus||"Permission change was cancelled or failed";root.permissionMode="";statusTimer.restart();return}root.permissionStep++;root.runPermissionStep()}
  }
  Timer { id: statusTimer; interval: 5000; onTriggered: { root.actionStatus = ""; root.actionPhase = "IDLE" } }
  Timer { id: gpuArmTimer; interval: 5000; onTriggered: root.armedGpuMode = "" }
  Timer { id:permissionArmTimer; interval:8000; onTriggered:root.permissionArm="" }
  KeyboardPanel {
    id: panel; anchorItem: root.anchorItem; owner: root.barIdentity; bar: root.bar; open: root.opened; focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(590)); contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(780))
    PanelKeyCatcher { id: keyCatcher; anchors.fill: parent; onCloseRequested: root.close(); onTabRequested:function(direction){root.switchPanel(direction)}; onActivateRequested: root.refresh() }

    Flickable {
      anchors.fill: parent; contentWidth: width; contentHeight: content.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      Column {
        id: content; width: parent.width; spacing: Style.space(12)

        Rectangle {
          width: parent.width; implicitHeight: hero.implicitHeight + Style.space(26); radius: Style.cornerRadius
          color: Qt.rgba(Color.accent.r,Color.accent.g,Color.accent.b,0.08); border.width: 1; border.color: Color.accent
          Column { id: hero; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: Style.space(14); spacing: Style.space(4)
            Text { textFormat: Text.PlainText; text: "ROG STRIX // CONTROL DECK"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; font.letterSpacing: 2 }
            Text { textFormat: Text.PlainText; text: (root.device.model || "ASUS laptop") + " · " + (root.device.profile || "profile unavailable") + " · " + (root.device.acOnline ? "AC" : "BATTERY"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { textFormat: Text.PlainText; visible: !root.device.asusctlReady; text: "asusd unavailable — controls disabled"; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }
        }

        Row {
          width:parent.width; spacing:Style.space(6)
          Repeater { model:["OVERVIEW","CONTROLS","AUTOMATION"]; delegate:Button { required property string modelData; required property int index; text:modelData; foreground:root.currentView===index?Color.accent:Color.muted; bordered:true; onClicked:root.currentView=index } }
        }

        Grid {
          visible:root.currentView===0; width: parent.width; columns: 4; columnSpacing: Style.space(6); rowSpacing: Style.space(6)
          Repeater {
            model: [
              {label:"GPU",value:root.gpuLabel()},{label:"LOAD",value:root.device.gpuUtil>=0?root.device.gpuUtil+"%":"--"},{label:"RTX TEMP",value:root.device.gpuTemp>=0?root.device.gpuTemp+"°C":"--"},{label:"VRAM",value:root.device.gpuMemory>=0?root.device.gpuMemory+" MiB":"--"},
              {label:"CPU",value:root.device.cpuTemp>=0?root.device.cpuTemp+"°C":"--"},{label:"CPU CLOCK",value:root.device.cpuFreqMHz>=0?(root.device.cpuFreqMHz/1000).toFixed(2)+" GHz":"--"},{label:"CPU PWR",value:root.cpuPowerWatts>=0?root.cpuPowerWatts.toFixed(1)+"W":"LOCKED"},{label:"iGPU PWR",value:root.device.igpuWatts?root.device.igpuWatts+"W":"--"},
              {label:"CPU FAN",value:root.device.cpuFan>=0?root.device.cpuFan+" RPM":"--"},{label:"GPU FAN",value:root.device.gpuFan>=0?root.device.gpuFan+" RPM":"--"},{label:"BATTERY",value:root.device.batteryPct>=0?root.device.batteryPct+"%":"--"},{label:"RUNTIME",value:root.batteryTimeLabel()}
            ]
            delegate: Rectangle {
              required property var modelData; width:(content.width-Style.space(18))/4; height:Style.space(50); radius:Style.cornerRadius; color:Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.06)
              Column { anchors.centerIn:parent; spacing:Style.space(2)
                Text { textFormat:Text.PlainText; anchors.horizontalCenter:parent.horizontalCenter; text:modelData.value; color:Color.accent; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true }
                Text { textFormat:Text.PlainText; anchors.horizontalCenter:parent.horizontalCenter; text:modelData.label; color:Color.muted; font.family:Style.font.family; font.pixelSize:Math.max(8,Style.font.caption-2) }
              }
            }
          }
        }

        Text { visible:root.currentView===0; textFormat:Text.PlainText; text:"60-SAMPLE HISTORY"; color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Grid {
          visible:root.currentView===0; width:parent.width; columns:2; columnSpacing:Style.space(6); rowSpacing:Style.space(6)
          Repeater {
            model:[{label:"CPU °C",values:root.cpuTempHistory},{label:"RTX °C",values:root.gpuTempHistory},{label:"CPU FAN",values:root.cpuFanHistory},{label:"GPU FAN",values:root.gpuFanHistory},{label:"CPU WATTS",values:root.cpuPowerHistory},{label:"RTX WATTS",values:root.gpuPowerHistory}]
            delegate:Rectangle {
              required property var modelData; width:(content.width-Style.space(6))/2; height:Style.space(72); radius:Style.cornerRadius; color:Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.045)
              Text { textFormat:Text.PlainText; anchors.left:parent.left; anchors.top:parent.top; anchors.margins:Style.space(6); text:modelData.label; color:Color.muted; font.family:Style.font.family; font.pixelSize:Math.max(8,Style.font.caption-2) }
              Canvas {
                id:chart; anchors.fill:parent; anchors.margins:Style.space(7); anchors.topMargin:Style.space(20)
                onPaint:function(){var ctx=getContext("2d");ctx.clearRect(0,0,width,height);var v=modelData.values;if(!v||v.length<2)return;var max=1;for(var i=0;i<v.length;i++)max=Math.max(max,Number(v[i]));ctx.strokeStyle=Color.accent;ctx.lineWidth=1.5;ctx.beginPath();for(var j=0;j<v.length;j++){var x=j*width/Math.max(1,v.length-1);var y=height-(Number(v[j])/max)*height;if(j===0)ctx.moveTo(x,y);else ctx.lineTo(x,y)}ctx.stroke()}
                Connections { target:root; function onGraphEpochChanged(){chart.requestPaint()} }
              }
            }
          }
        }

        Text { visible:root.currentView===1; textFormat:Text.PlainText; text:"EDITABLE PRESETS"; color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Flow { visible:root.currentView===1; width:parent.width; spacing:Style.space(6)
          Repeater { model:root.control.presets||[]; delegate:Button { required property var modelData; text:modelData.name.toUpperCase(); foreground:root.selectedPreset===modelData.name?Color.accent:Color.muted; bordered:true; enabled:!root.busy; tooltipText:root.richTextEscape(modelData.profile+" · "+modelData.brightness+" keys · "+modelData.batteryLimit+"% · #"+modelData.auraColor.toUpperCase()); onClicked:{root.selectedPreset=modelData.name;root.runAction("preset",[modelData.name])} } }
        }
        Text { visible:root.currentView===1; textFormat:Text.PlainText; text:"EDIT "+root.selectedPreset.toUpperCase(); color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Flow { visible:root.currentView===1; width:parent.width; spacing:Style.space(6)
          Repeater { model:["Quiet","Balanced","Performance"]; delegate:Button { required property string modelData; text:modelData.toUpperCase(); foreground:root.selectedPresetData().profile===modelData?Color.accent:Color.muted; bordered:true; onClicked:root.runAction("preset-update",[root.selectedPreset,"profile",modelData]) } }
          Repeater { model:["off","low","med","high"]; delegate:Button { required property string modelData; text:"KEYS "+modelData.toUpperCase(); foreground:root.selectedPresetData().brightness===modelData?Color.accent:Color.muted; bordered:true; onClicked:root.runAction("preset-update",[root.selectedPreset,"brightness",modelData]) } }
        }
        Flow { visible:root.currentView===1; width:parent.width; spacing:Style.space(6)
          Repeater { model:[60,80,100]; delegate:Button { required property int modelData; text:"LIMIT "+modelData+"%"; foreground:root.selectedPresetData().batteryLimit===modelData?Color.accent:Color.muted; bordered:true; onClicked:root.runAction("preset-update",[root.selectedPreset,"batteryLimit",modelData]) } }
          Button { text:"PANEL OD "+(root.selectedPresetData().panelOd?"ON":"OFF"); foreground:root.selectedPresetData().panelOd?Color.accent:Color.muted; bordered:true; onClicked:root.runAction("preset-update",[root.selectedPreset,"panelOd",root.selectedPresetData().panelOd?0:1]) }
          Button { text:"SAVE #"+root.auraColor.toUpperCase(); foreground:root.validColor(root.auraColor)?Color.accent:Color.urgent; bordered:true; enabled:root.validColor(root.auraColor); onClicked:root.runAction("preset-update",[root.selectedPreset,"auraColor",root.auraColor]) }
        }
        Row { visible:root.currentView===1; spacing:Style.space(6)
          Rectangle { width:Style.space(112); height:Style.space(30); radius:Style.cornerRadius; color:Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.06); border.width:1; border.color:Color.muted
            TextInput { anchors.fill:parent; anchors.margins:Style.space(6); text:root.newPresetName; color:Color.foreground; font.family:Style.font.family; font.pixelSize:Style.font.caption; maximumLength:32; onTextChanged:root.newPresetName=text }
          }
          Button { text:"SAVE CURRENT"; foreground:Color.accent; bordered:true; enabled:!root.busy; tooltipText:"Save current profile, lighting, panel and battery settings under this name"; onClicked:{root.selectedPreset=root.newPresetName;root.runAction("preset-save",[root.newPresetName,root.auraColor])} }
          Button { text:"DUPLICATE"; foreground:Color.muted; bordered:true; enabled:!root.busy; onClicked:root.runAction("preset-duplicate",[root.selectedPreset,root.newPresetName]) }
          Button { text:"RENAME"; foreground:Color.muted; bordered:true; enabled:!root.busy; onClicked:{root.runAction("preset-rename",[root.selectedPreset,root.newPresetName]);root.selectedPreset=root.newPresetName} }
          Button { text:"DELETE"; foreground:Color.urgent; bordered:true; enabled:!root.busy; onClicked:root.runAction("preset-delete",[root.selectedPreset]) }
        }
        Flow { visible:root.currentView===1; width:parent.width; spacing:Style.space(6)
          Button { text:"MOVE UP"; foreground:Color.muted; bordered:true; onClicked:root.runAction("preset-move",[root.selectedPreset,"up"]) }
          Button { text:"MOVE DOWN"; foreground:Color.muted; bordered:true; onClicked:root.runAction("preset-move",[root.selectedPreset,"down"]) }
          Button { text:"EXPORT"; foreground:Color.muted; bordered:true; tooltipText:"Write a portable preset file in ~/.config/rog-strix-control"; onClicked:root.runAction("config-export",[]) }
          Button { text:"IMPORT"; foreground:Color.muted; bordered:true; tooltipText:"Validate and import ~/.config/rog-strix-control/import.json"; onClicked:root.runAction("config-import",[]) }
        }
        Text { visible:root.currentView===1; textFormat:Text.PlainText; text:"POLICY // AC " + (root.device.acProfile||"--") + " · BATTERY " + (root.device.batteryProfile||"--") + (root.device.profile && ((root.device.acOnline?root.device.acProfile:root.device.batteryProfile)!==root.device.profile)?" · ACTIVE OVERRIDE":""); color:((root.device.acOnline?root.device.acProfile:root.device.batteryProfile)!==root.device.profile)?Color.urgent:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption }

        Text { visible:root.currentView===2; textFormat:Text.PlainText; text:"ADAPTIVE AUTOMATION"; color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Flow { visible:root.currentView===2; width:parent.width; spacing:Style.space(6)
          Button { text:"AUTO "+(root.control.automation&&root.control.automation.enabled?"ON":"OFF"); foreground:root.control.automation&&root.control.automation.enabled?Color.accent:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["enabled",root.control.automation.enabled?"false":"true"]) }
          Button { text:"QUIET HOURS "+(root.control.automation&&root.control.automation.quietEnabled?"ON":"OFF"); foreground:root.control.automation&&root.control.automation.quietEnabled?Color.accent:Color.muted; bordered:true; tooltipText:"Uses the configured 22:00–07:00 window"; onClicked:root.runAction("automation-set",["quietEnabled",root.control.automation.quietEnabled?"false":"true"]) }
          Button { text:"THERMAL RULE "+(root.control.automation&&root.control.automation.thermalEnabled?"ON":"OFF"); foreground:root.control.automation&&root.control.automation.thermalEnabled?Color.urgent:Color.muted; bordered:true; tooltipText:"At 88°C apply Gaming, with cooldown protection"; onClicked:root.runAction("automation-set",["thermalEnabled",root.control.automation.thermalEnabled?"false":"true"]) }
          Button { text:"SET AC → "+root.selectedPreset.toUpperCase(); foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["acPreset",root.selectedPreset]) }
          Button { text:"SET BATTERY → "+root.selectedPreset.toUpperCase(); foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["batteryPreset",root.selectedPreset]) }
          Button { text:"PAUSE 15M"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["manualUntil",String(Math.floor(Date.now()/1000)+900)]) }
          Button { text:"PAUSE 1H"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["manualUntil",String(Math.floor(Date.now()/1000)+3600)]) }
          Button { text:"RESUME"; foreground:Color.accent; bordered:true; onClicked:root.runAction("automation-set",["manualUntil","0"]) }
        }
        Flow { visible:root.currentView===2; width:parent.width; spacing:Style.space(6)
          Button { text:"START −"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["quietStart",String((root.control.automation.quietStart+23)%24)]) }
          Button { text:"START +"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["quietStart",String((root.control.automation.quietStart+1)%24)]) }
          Button { text:String(root.control.automation.quietStart).padStart(2,"0")+":00 → "+String(root.control.automation.quietEnd).padStart(2,"0")+":00"; foreground:Color.accent; bordered:true; enabled:false }
          Button { text:"END −"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["quietEnd",String((root.control.automation.quietEnd+23)%24)]) }
          Button { text:"END +"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["quietEnd",String((root.control.automation.quietEnd+1)%24)]) }
          Button { text:"ON −"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["thermalOn",String(Math.max(root.control.automation.thermalOff,root.control.automation.thermalOn-1))]) }
          Button { text:root.control.automation.thermalOn+"°C ON / "+root.control.automation.thermalOff+"°C OFF"; foreground:Color.urgent; bordered:true; enabled:false }
          Button { text:"ON +"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["thermalOn",String(Math.min(120,root.control.automation.thermalOn+1))]) }
          Button { text:"OFF −"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["thermalOff",String(Math.max(40,root.control.automation.thermalOff-1))]) }
          Button { text:"OFF +"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["thermalOff",String(Math.min(root.control.automation.thermalOn,root.control.automation.thermalOff+1))]) }
          Button { text:"COOLDOWN −"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["cooldownSeconds",String(Math.max(30,root.control.automation.cooldownSeconds-30))]) }
          Button { text:root.control.automation.cooldownSeconds+"S"; foreground:Color.accent; bordered:true; enabled:false }
          Button { text:"COOLDOWN +"; foreground:Color.muted; bordered:true; onClicked:root.runAction("automation-set",["cooldownSeconds",String(Math.min(9999,root.control.automation.cooldownSeconds+30))]) }
        }
        Text { visible:root.currentView===2; textFormat:Text.PlainText; width:parent.width; wrapMode:Text.Wrap; text:"ACTIVE // "+(root.control.runtime&&root.control.runtime.activeReason?root.control.runtime.activeReason+" → "+root.control.runtime.activePreset:"manual")+" · AC "+(root.control.automation.acPreset||"daily")+" · BATTERY "+(root.control.automation.batteryPreset||"battery"); color:root.control.runtime&&root.control.runtime.activeGame?Color.urgent:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption }

        Text { visible:root.currentView===2; textFormat:Text.PlainText; text:"PER-GAME PROFILES"; color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Row { visible:root.currentView===2; spacing:Style.space(6)
          Rectangle { width:Style.space(150); height:Style.space(30); radius:Style.cornerRadius; color:Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.06); border.width:1; border.color:Color.muted
            TextInput { anchors.fill:parent; anchors.margins:Style.space(6); text:root.gameExecutable; color:Color.foreground; font.family:Style.font.family; font.pixelSize:Style.font.caption; maximumLength:64; onTextChanged:root.gameExecutable=text }
          }
          Button { text:"ADD → "+root.selectedPreset.toUpperCase(); foreground:Color.accent; bordered:true; enabled:root.gameExecutable.length>0; tooltipText:"Match an exact Linux process name from Steam, Heroic, Lutris, or a native game"; onClicked:root.runAction("game-add",[root.gameExecutable,root.selectedPreset,root.gameBoostExtras?"full":"safe"]) }
          Button { text:"BOOST EXTRAS "+(root.gameBoostExtras?"ON":"OFF"); foreground:root.gameBoostExtras?Color.accent:Color.muted; bordered:true; tooltipText:"Prevent sleep and force panel overdrive while the game runs"; onClicked:root.gameBoostExtras=!root.gameBoostExtras }
        }
        Flow { visible:root.currentView===2; width:parent.width; spacing:Style.space(6)
          Repeater { model:root.control.gameRules||[]; delegate:Button { required property var modelData; text:modelData.exe+" → "+modelData.preset+"  ×"; foreground:root.control.runtime&&root.control.runtime.activeGame===modelData.exe?Color.urgent:Color.muted; bordered:true; tooltipText:"Remove this game rule"; onClicked:root.runAction("game-remove",[modelData.exe]) } }
        }
        Text { visible:root.currentView===2; textFormat:Text.PlainText; text:"RECENT POLICY EVENTS"; color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Column { visible:root.currentView===2; width:parent.width; spacing:Style.space(4)
          Repeater { model:(root.control.events||[]).slice(0,6); delegate:Text { required property var modelData; textFormat:Text.PlainText; width:parent.width; text:modelData.at+" · "+modelData.reason+" → "+modelData.preset+" · "+modelData.outcome.toUpperCase(); color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption } }
          Button { text:"SIMULATE NOW"; foreground:Color.accent; bordered:true; onClicked:root.runAction("automation-simulate",[]) }
        }

        Text { visible:root.currentView===1; textFormat:Text.PlainText; text:"PERFORMANCE PROFILE"; color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Flow { visible:root.currentView===1; width:parent.width; spacing:Style.space(6)
          Repeater { model:root.device.profiles||[]; delegate:Button { required property string modelData; text:modelData.toUpperCase(); foreground:root.device.profile===modelData?Color.accent:Color.muted; bordered:true; enabled:root.device.asusctlReady&&!root.busy; onClicked:root.runAction("profile",[modelData.toLowerCase()]) } }
        }

        Item { visible:root.currentView===1&&root.device.capabilities.aura; width:parent.width; implicitHeight:visible?auraControls.implicitHeight:0
          Column { id:auraControls; width:parent.width; spacing:Style.space(7)
            Text { textFormat:Text.PlainText; text:"AURA LIGHTING · " + (root.device.auraMode||"--"); color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
            Flow { width:parent.width; spacing:Style.space(6)
              Repeater { model:["off","low","med","high"]; delegate:Button { required property string modelData; text:modelData.toUpperCase(); foreground:String(root.device.ledBrightness).toLowerCase()===modelData?Color.accent:Color.muted; bordered:true; enabled:!root.busy; onClicked:root.runAction("brightness",[modelData]) } }
            }
            Row { spacing:Style.space(6)
              Rectangle { width:Style.space(104); height:Style.space(30); radius:Style.cornerRadius; color:Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.06); border.width:1; border.color:root.validColor(root.auraColor)?Color.accent:Color.urgent
                TextInput { anchors.fill:parent; anchors.margins:Style.space(6); text:root.auraColor; color:Color.foreground; font.family:Style.font.family; font.pixelSize:Style.font.caption; maximumLength:6; onTextChanged:root.auraColor=text }
              }
              Button { text:"APPLY COLOR"; foreground:Color.accent; bordered:true; enabled:root.validColor(root.auraColor)&&!root.busy; onClicked:root.runAction("aura-static",[root.auraColor,root.auraZone]) }
              Button { text:"SAVE P1"; foreground:Color.muted; bordered:true; enabled:root.validColor(root.auraColor); onClicked:root.setPluginSetting("auraPreset1",root.auraColor) }
              Button { text:"SAVE P2"; foreground:Color.muted; bordered:true; enabled:root.validColor(root.auraColor); onClicked:root.setPluginSetting("auraPreset2",root.auraColor) }
            }
            Flow { width:parent.width; spacing:Style.space(6)
              Button { text:"P1 #"+root.auraPreset1.toUpperCase(); foreground:Color.accent; bordered:true; onClicked:root.runAction("aura-static",[root.auraPreset1,root.auraZone]) }
              Button { text:"P2 #"+root.auraPreset2.toUpperCase(); foreground:Color.urgent; bordered:true; onClicked:root.runAction("aura-static",[root.auraPreset2,root.auraZone]) }
              Button { visible:(root.device.auraModes||[]).indexOf("Breathe")>=0; text:"BREATHE"; foreground:Color.muted; bordered:true; onClicked:root.runAction("aura-breathe",[root.auraColor,"000000",root.auraSpeed]) }
              Button { visible:(root.device.auraModes||[]).indexOf("RainbowWave")>=0; text:"RAINBOW"; foreground:Color.muted; bordered:true; onClicked:root.runAction("aura-rainbow",[root.auraDirection,root.auraSpeed]) }
              Button { visible:(root.device.auraModes||[]).indexOf("RainbowCycle")>=0; text:"CYCLE"; foreground:Color.muted; bordered:true; onClicked:root.runAction("aura-cycle",[root.auraSpeed]) }
            }
            Flow { width:parent.width; spacing:Style.space(6)
              Repeater { model:["low","med","high"]; delegate:Button { required property string modelData; text:"SPEED "+modelData.toUpperCase(); foreground:root.auraSpeed===modelData?Color.accent:Color.muted; bordered:true; onClicked:root.auraSpeed=modelData } }
              Repeater { model:["left","right","up","down"]; delegate:Button { required property string modelData; text:modelData.toUpperCase(); foreground:root.auraDirection===modelData?Color.accent:Color.muted; bordered:true; onClicked:root.auraDirection=modelData } }
            }
            Flow { visible:root.device.capabilities.auraZones; width:parent.width; spacing:Style.space(6)
              Repeater { model:["global","1","2","3","4"]; delegate:Button { required property string modelData; text:modelData==="global"?"ALL ZONES":"ZONE "+modelData; foreground:root.auraZone===modelData?Color.accent:Color.muted; bordered:true; onClicked:root.auraZone=modelData } }
            }
            Text { textFormat:Text.PlainText; text:"Aura state is persisted and restored by asusd across reboot/resume"; color:Color.muted; opacity:0.7; font.family:Style.font.family; font.pixelSize:Math.max(8,Style.font.caption-2) }
          }
        }

        Text { textFormat:Text.PlainText; visible:root.currentView===1&&(root.device.capabilities.battery||root.device.capabilities.panelOd||root.device.capabilities.bootSound); text:"BATTERY CARE + FIRMWARE"; color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Flow { visible:root.currentView===1; width:parent.width; spacing:Style.space(6)
          Repeater { model:root.device.capabilities.battery?[60,80,100]:[]; delegate:Button { required property int modelData; text:modelData+"%"; foreground:root.device.batteryLimit===modelData?Color.accent:Color.muted; bordered:true; enabled:!root.busy; onClicked:root.runAction("battery-limit",[modelData]) } }
          Button { visible:root.device.capabilities.panelOd; text:"PANEL OD "+root.boolLabel(root.device.panelOd); foreground:root.device.panelOd?Color.accent:Color.muted; bordered:true; enabled:!root.busy; onClicked:root.runAction("panel-od",[root.device.panelOd?0:1]) }
          Button { visible:root.device.capabilities.bootSound; text:"BOOT SOUND "+root.boolLabel(root.device.bootSound); foreground:root.device.bootSound?Color.accent:Color.muted; bordered:true; enabled:!root.busy; onClicked:root.runAction("boot-sound",[root.device.bootSound?0:1]) }
        }

        Text { textFormat:Text.PlainText; visible:root.currentView===1&&root.device.supergfxInstalled; text:"GPU MODE · "+(root.device.gpuMode||"DAEMON OFFLINE"); color:root.device.supergfxReady?Color.muted:Color.urgent; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Flow { visible:root.currentView===1&&root.device.supergfxReady; width:parent.width; spacing:Style.space(6)
          Repeater { model:root.device.gpuModes||[]; delegate:Button { required property string modelData; text:root.armedGpuMode===modelData?"CONFIRM "+modelData.toUpperCase():modelData.toUpperCase(); foreground:root.device.gpuMode===modelData?Color.accent:Color.urgent; bordered:true; enabled:!root.busy; tooltipText:"May require logout or reboot; active NVIDIA clients block Integrated mode"; onClicked:root.requestGpuMode(modelData) } }
        }
        Text { textFormat:Text.PlainText; visible:root.currentView===1&&root.device.supergfxInstalled&&!root.device.supergfxReady; text:"supergfxctl is installed; enable supergfxd to activate safe GPU switching"; color:Color.urgent; font.family:Style.font.family; font.pixelSize:Style.font.caption }
        Text { textFormat:Text.PlainText; visible:root.currentView===1&&(root.device.gpuPendingAction||root.device.gpuPendingMode); text:"PENDING // "+root.device.gpuPendingMode+" · "+root.device.gpuPendingAction; color:Color.urgent; font.family:Style.font.family; font.pixelSize:Style.font.caption }

        Text { visible:root.currentView===0; textFormat:Text.PlainText; text:"SYSTEM HEALTH"; color:root.health.healthy?Color.muted:Color.urgent; font.family:Style.font.family; font.pixelSize:Style.font.caption; font.bold:true; font.letterSpacing:2 }
        Flow { visible:root.currentView===0; width:parent.width; spacing:Style.space(6)
          Button { text:"ASUSD "+String(root.health.asusd).toUpperCase(); foreground:root.health.asusd==="active"?Color.accent:Color.urgent; bordered:true; enabled:false }
          Button { text:"SUPERGFXD "+String(root.health.supergfxd).toUpperCase(); foreground:root.health.supergfxd==="active"?Color.accent:Color.urgent; bordered:true; enabled:false }
          Button { text:"NVIDIA "+String(root.health.nvidia).toUpperCase(); foreground:root.health.nvidia==="available"?Color.accent:Color.muted; bordered:true; enabled:false }
          Button { text:"SENSORS "+root.health.sensorCount; foreground:root.health.sensorCount>0?Color.accent:Color.urgent; bordered:true; enabled:false }
          Button { text:"COPY-SAFE REPORT"; foreground:Color.muted; bordered:true; tooltipText:"Writes a privacy-conscious report without usernames, serials, paths, or process arguments"; onClicked:root.runAction("diagnostics-report",[]) }
          Button { visible:root.permissions.needsSetup&&root.permissions.canInstall; text:root.permissionArm==="install"?"CONFIRM CPU WATTS":"ENABLE CPU WATTS"; foreground:Color.urgent; bordered:true; tooltipText:"Installs an opt-in root-owned udev rule granting wheel read-only access to the package energy counter"; onClicked:root.requestPermissionChange("install") }
          Button { visible:root.permissions.ruleInstalled; text:root.permissionArm==="remove"?"CONFIRM REMOVE":"REMOVE CPU WATTS RULE"; foreground:Color.urgent; bordered:true; tooltipText:"Removes the udev rule and restores root-only access to the live counter"; onClicked:root.requestPermissionChange("remove") }
        }
        Text { visible:root.currentView===0&&root.permissions.needsSetup; textFormat:Text.PlainText; width:parent.width; wrapMode:Text.Wrap; text:root.permissions.canInstall?"CPU watts are optional. Enabling them requires administrator authentication and grants read-only RAPL energy access to wheel users.":"CPU energy exists but is restricted. Setup requires pkexec and membership in the wheel group."; color:Color.urgent; font.family:Style.font.family; font.pixelSize:Style.font.caption }
        Text { textFormat:Text.PlainText; visible:root.currentView===0&&(root.health.issues||[]).length>0; width:parent.width; wrapMode:Text.Wrap; text:(root.health.issues||[]).join(" · "); color:Color.urgent; font.family:Style.font.family; font.pixelSize:Style.font.caption }
        Text { textFormat:Text.PlainText; visible:root.currentView===0&&(root.health.recentErrors||[]).length>0; width:parent.width; wrapMode:Text.Wrap; text:"RECENT SERVICE WARNINGS // "+(root.health.recentErrors||[]).join(" · "); color:Color.muted; font.family:Style.font.family; font.pixelSize:Style.font.caption }

        Text { textFormat:Text.PlainText; width:parent.width; wrapMode:Text.Wrap; text:(root.actionPhase!=="IDLE"?root.actionPhase+" // ":"")+(root.actionStatus||"R refresh · capability-driven ASUS controls · no arbitrary command execution"); color:root.actionPhase==="FAILED"?Color.urgent:(root.actionStatus?Color.accent:Color.muted); font.family:Style.font.family; font.pixelSize:Style.font.caption }
        Text { textFormat:Text.PlainText; text:"v"+root.device.helperVersion+" · "+(root.device.board||"ROG")+" · local control only"; color:Color.muted; opacity:0.6; font.family:Style.font.family; font.pixelSize:Math.max(8,Style.font.caption-2) }
      }
    }
  }
}
