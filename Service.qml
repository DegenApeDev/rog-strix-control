import QtQuick
import Quickshell.Io

Item {
  id: root

  property var shell: null
  readonly property string helperPath: Qt.resolvedUrl("rog-strix-control").toString().replace(/^file:\/\//, "")
  property string lastResult: ""
  property int lastExitCode: 0
  property var device: ({vendor:"",model:"",board:"",profile:"",profiles:[],acProfile:"",batteryProfile:"",ledBrightness:"",auraMode:"",auraModes:[],gpuState:"",gpuWatts:"",gpuTemp:-1,gpuUtil:-1,gpuMemory:-1,gpuClients:0,gpuMode:"",gpuPower:"",gpuPendingAction:"",gpuPendingMode:"",gpuModes:[],cpuFan:-1,gpuFan:-1,cpuTemp:-1,igpuTemp:-1,cpuFreqMHz:-1,cpuEnergyUj:-1,cpuEnergyMaxUj:-1,cpuPowerWatts:-1,sampledMs:-1,igpuWatts:"",batteryWatts:"",batteryMinutes:-1,batteryLimit:-1,batteryPct:-1,batteryStatus:"",acOnline:false,panelOd:false,bootSound:false,dgpuDisabled:false,asusctlReady:false,supergfxInstalled:false,supergfxReady:false,capabilities:{aura:false,auraZones:false,battery:false,panelOd:false,bootSound:false,fans:false,cpuPower:false,supergfx:false},helperVersion:"5.1.0"})
  property var control: ({automation:{enabled:false,quietEnabled:false,thermalEnabled:false,quietStart:22,quietEnd:7,thermalOn:88,thermalOff:78,cooldownSeconds:60,acPreset:"daily",batteryPreset:"battery",manualUntil:0},presets:[],gameRules:[],events:[],runtime:{}})
  property var health: ({asusd:"unknown",supergfxd:"unknown",nvidia:"unknown",sensorCount:0,issues:[],healthy:false})

  function refresh(includeHealth) {
    if (!statusProcess.running) statusProcess.running = true
    if (!controlProcess.running) controlProcess.running = true
    if (includeHealth && !healthProcess.running) healthProcess.running = true
  }

  function tick() {
    if (!automationProcess.running) automationProcess.running = true
  }

  Process {
    id: automationProcess
    command: [root.helperPath, "action", "automation-tick"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastResult = text.trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim()) root.lastResult = text.trim()
    }
    onExited: function(exitCode) { root.lastExitCode = exitCode; root.refresh(false) }
  }

  Process {
    id: statusProcess
    command: [root.helperPath, "status"]
    stdout: StdioCollector { waitForEnd:true; onStreamFinished:{try{root.device=JSON.parse(text)}catch(error){}} }
  }

  Process {
    id: controlProcess
    command: [root.helperPath, "control"]
    stdout: StdioCollector { waitForEnd:true; onStreamFinished:{try{root.control=JSON.parse(text)}catch(error){}} }
  }

  Process {
    id: healthProcess
    command: [root.helperPath, "diagnostics"]
    stdout: StdioCollector { waitForEnd:true; onStreamFinished:{try{root.health=JSON.parse(text)}catch(error){}} }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  Timer { interval:5000; running:true; repeat:true; triggeredOnStart:true; onTriggered:root.refresh(false) }
  Timer { interval:30000; running:true; repeat:true; triggeredOnStart:true; onTriggered:root.refresh(true) }

  IpcHandler {
    target: "xyz.degendev.rog-strix-control.service"
    function tick(): void { root.tick() }
    function status(): string {
      return JSON.stringify({running:automationProcess.running,lastResult:root.lastResult,lastExitCode:root.lastExitCode,device:root.device,control:root.control,health:root.health})
    }
    function refresh(): void { root.refresh(true) }
  }
}
