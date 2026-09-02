#!/usr/bin/env bash
set -euo pipefail
trap 'printf "test failed at line %s\n" "$LINENO" >&2' ERR

cd -- "$(dirname -- "$0")"
helper=./rog-strix-control
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
capture="$fixture/actions"
export XDG_CONFIG_HOME="$fixture/config"

printf '%s\n' '#!/usr/bin/env bash' \
  'printf "asusctl %s\n" "$*" >>"$ROG_TEST_CAPTURE"' \
  '[[ -n ${ROG_TEST_FAIL_ON:-} && $* == "$ROG_TEST_FAIL_ON" ]] && exit 9' \
  'case "$*" in' \
  "  'profile get') printf 'Active profile: Balanced\\n' ;;" \
  "  'leds get') printf 'Current keyboard led brightness: Med\\n' ;;" \
  "  'battery info') printf 'Current battery charge limit: 80%%%%\\n' ;;" \
  'esac' >"$fixture/asusctl"
chmod +x "$fixture/asusctl"
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  -s) printf "[Integrated, Hybrid]\n" ;;' \
  '  -m) printf "supergfxctl mode %s\n" "$2" >>"$ROG_TEST_CAPTURE" ;;' \
  '  -g) printf "Hybrid\n" ;;' \
  'esac' >"$fixture/supergfxctl"
chmod +x "$fixture/supergfxctl"
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ ${ROG_TEST_GPU_CLIENTS:-0} == 1 ]]; then printf "4242\n"; fi' >"$fixture/nvidia-smi"
chmod +x "$fixture/nvidia-smi"
printf '%s\n' '#!/usr/bin/env bash' 'exec sleep 300' >"$fixture/systemd-inhibit"
chmod +x "$fixture/systemd-inhibit"

run() { ROG_TEST_CAPTURE="$capture" PATH="$fixture:$PATH" "$helper" action "$@" >/dev/null; }
run profile balanced
run brightness high
run aura-static 39ff14 global
run aura-static ff1818 2
run aura-breathe 39ff14 000000 med
run aura-rainbow right high
run aura-cycle low
run battery-limit 80
run panel-od 0
run boot-sound 1
run preset daily
run gpu-mode Hybrid

grep -Fqx 'asusctl profile set Balanced' "$capture"
grep -Fqx 'asusctl aura effect static --colour 39ff14' "$capture"
grep -Fqx 'asusctl aura effect static --colour ff1818 --zone 2' "$capture"
grep -Fqx 'asusctl aura effect breathe --colour 39ff14 --colour2 000000 --speed med' "$capture"
grep -Fqx 'asusctl aura effect rainbow-wave --direction right --speed high' "$capture"
grep -Fqx 'asusctl battery limit 80' "$capture"
grep -Fqx 'asusctl armoury set panel_overdrive 0' "$capture"
grep -Fqx 'supergfxctl mode Hybrid' "$capture"

if run aura-static 'bad;command' global 2>/dev/null; then printf 'unsafe colour accepted\n' >&2; exit 1; fi
if run aura-rainbow sideways high 2>/dev/null; then printf 'unsafe direction accepted\n' >&2; exit 1; fi
if run battery-limit 55 2>/dev/null; then printf 'unsafe battery limit accepted\n' >&2; exit 1; fi
if ROG_TEST_GPU_CLIENTS=1 run gpu-mode Integrated 2>/dev/null; then printf 'Integrated mode accepted with active NVIDIA clients\n' >&2; exit 1; fi

control=$(ROG_TEST_CAPTURE="$capture" PATH="$fixture:$PATH" "$helper" control)
jq -e '.version==2 and .automation.enabled == false and .automation.manualUntil==0 and (.presets|length)==4 and .presets[0].auraColor=="ff1818" and .presets[1].auraColor=="39ff14"' <<<"$control" >/dev/null
run preset-save custom 39ff14
run preset-update custom profile Performance
run preset-update custom brightness low
run preset-update custom batteryLimit 100
run preset-update custom panelOd 1
run preset-update custom auraColor aabbcc
run preset-duplicate custom custom2
run preset-move custom2 up
run preset-rename custom2 renamed
run game-add testgame custom full
run automation-set enabled true
run automation-set quietEnabled true
control=$(ROG_TEST_CAPTURE="$capture" PATH="$fixture:$PATH" "$helper" control)
jq -e '.automation.enabled and .automation.quietEnabled and (.presets|any(.name=="custom" and .profile=="Performance" and .brightness=="low" and .batteryLimit==100 and .panelOd==1 and .auraColor=="aabbcc")) and (.presets|any(.name=="renamed")) and (.gameRules|any(.exe=="testgame" and .preset=="custom" and .preventSleep and .panelOverride))' <<<"$control" >/dev/null
# Editing the preset currently held active by automation applies it immediately.
jq -cn '{activeReason:"ac",activePreset:"custom",activeGame:"",lastSwitch:1,previousSnapshot:null,inhibitPid:0}' >"$XDG_CONFIG_HOME/rog-strix-control/runtime-state.json"
before_count=$(grep -Fc 'asusctl battery limit 80' "$capture")
run preset-update custom batteryLimit 80
after_count=$(grep -Fc 'asusctl battery limit 80' "$capture")
((after_count == before_count + 1))
run preset-update custom batteryLimit 100
if run automation-set thermalOff 100 2>/dev/null; then printf 'invalid thermal hysteresis accepted\n' >&2; exit 1; fi
ln -s /usr/bin/sleep "$fixture/testgame"
"$fixture/testgame" 30 & game_pid=$!
ROG_CONTROL_NOW=100 run automation-tick
jq -e '.activeReason=="game:testgame" and .activeGame=="testgame" and .previousSnapshot!=null and .inhibitPid>1' "$XDG_CONFIG_HOME/rog-strix-control/runtime-state.json" >/dev/null
kill "$game_pid"; wait "$game_pid" 2>/dev/null || true
ROG_CONTROL_NOW=200 run automation-tick
jq -e '.activeGame=="" and .previousSnapshot==null and .inhibitPid==0' "$XDG_CONFIG_HOME/rog-strix-control/runtime-state.json" >/dev/null
[[ $(grep -Fc 'asusctl aura effect static --colour 39ff14' "$capture") -ge 2 ]]
"$fixture/testgame" 30 & game_pid=$!
ROG_CONTROL_NOW=300 run automation-tick
run automation-set enabled false
jq -e '.activeReason=="" and .previousSnapshot==null and .inhibitPid==0' "$XDG_CONFIG_HOME/rog-strix-control/runtime-state.json" >/dev/null
kill "$game_pid"; wait "$game_pid" 2>/dev/null || true
run game-remove testgame
run preset-delete renamed
if ROG_TEST_FAIL_ON='battery limit 80' run preset daily 2>/dev/null; then printf 'failed transactional preset accepted\n' >&2; exit 1; fi
[[ $(grep -Fc 'asusctl profile set Balanced' "$capture") -ge 2 ]]
run config-export
[[ -s "$XDG_CONFIG_HOME/rog-strix-control/export.json" ]]
ROG_TEST_CAPTURE="$capture" PATH="$fixture:$PATH" "$helper" diagnostics | jq -e 'has("issues") and has("healthy")' >/dev/null
ROG_TEST_CAPTURE="$capture" PATH="$fixture:$PATH" "$helper" report >/dev/null
[[ -s "$XDG_CONFIG_HOME/rog-strix-control/diagnostics.txt" ]]
! grep -Eq "$USER|/home/" "$XDG_CONFIG_HOME/rog-strix-control/diagnostics.txt"
printf '{"bad":true}\n' >"$XDG_CONFIG_HOME/rog-strix-control/import.json"
if run config-import 2>/dev/null; then printf 'invalid config import accepted\n' >&2; exit 1; fi
cp "$XDG_CONFIG_HOME/rog-strix-control/control.json" "$fixture/control-good.json"
jq 'del(.automation.cooldownSeconds)' "$fixture/control-good.json" >"$XDG_CONFIG_HOME/rog-strix-control/control.json"
if ROG_TEST_CAPTURE="$capture" PATH="$fixture:$PATH" "$helper" control >/dev/null 2>&1; then printf 'incomplete live config accepted\n' >&2; exit 1; fi
cp "$fixture/control-good.json" "$XDG_CONFIG_HOME/rog-strix-control/control.json"

# Version-one configurations migrate in place without losing presets.
jq '.version=1 | del(.automation.manualUntil)' "$fixture/control-good.json" >"$XDG_CONFIG_HOME/rog-strix-control/control.json"
control=$(ROG_TEST_CAPTURE="$capture" PATH="$fixture:$PATH" "$helper" control)
jq -e '.version==2 and .automation.manualUntil==0 and (.presets|length)>0' <<<"$control" >/dev/null

# Hardware discovery accepts nonstandard power-supply names through fake sysfs.
mkdir -p "$fixture/sys/class/power_supply/CMB1" "$fixture/sys/class/power_supply/ACX" "$fixture/sys/class/dmi/id" "$fixture/sys/class/powercap/intel-rapl/intel-rapl:0"
printf 'Battery\n' >"$fixture/sys/class/power_supply/CMB1/type"
printf '73\n' >"$fixture/sys/class/power_supply/CMB1/capacity"
printf 'Discharging\n' >"$fixture/sys/class/power_supply/CMB1/status"
printf 'Mains\n' >"$fixture/sys/class/power_supply/ACX/type"
printf '0\n' >"$fixture/sys/class/power_supply/ACX/online"
printf '123456\n' >"$fixture/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj"
status=$(ROG_TEST_CAPTURE="$capture" ROG_SYSFS_ROOT="$fixture/sys" PATH="$fixture:$PATH" "$helper" status)
jq -e '.batteryPct==73 and .acOnline==false and .helperVersion=="5.1.0"' <<<"$status" >/dev/null
permissions=$(ROG_SYSFS_ROOT="$fixture/sys" "$helper" permissions)
jq -e '.sensor and .readable and (.energyPath|endswith("intel-rapl:0/energy_uj")) and .ruleTarget=="/etc/udev/rules.d/70-rog-strix-energy.rules"' <<<"$permissions" >/dev/null

# Simulation explains policy without mutating hardware or runtime state.
run automation-set enabled true
run automation-set quietEnabled false
before_actions=$(wc -l <"$capture")
simulation=$(ROG_TEST_CAPTURE="$capture" ROG_SYSFS_ROOT="$fixture/sys" ROG_CONTROL_NOW=500 PATH="$fixture:$PATH" "$helper" action automation-simulate)
jq -e '.dryRun and .reason=="battery" and .preset=="battery"' <<<"$simulation" >/dev/null
[[ $(wc -l <"$capture") -eq $before_actions ]]

bash -n "$helper"
jq -e '.version == "5.1.0" and .id == "xyz.degendev.rog-strix-control" and (.kinds|index("bar-widget")) and (.kinds|index("service"))' manifest.json >/dev/null
! grep -UPq 'Text\s*\{(?!\s*textFormat:\s*Text\.PlainText)' Panel.qml
grep -Fq 'function requestGpuMode(mode)' Panel.qml
grep -Fq 'property var cpuTempHistory: []' Panel.qml
grep -Fq 'root.device.capabilities.auraZones' Panel.qml
grep -Fq 'active NVIDIA clients block Integrated mode' Panel.qml
grep -Fq 'ADAPTIVE AUTOMATION' Panel.qml
grep -Fq 'PER-GAME PROFILES' Panel.qml
grep -Fq 'SYSTEM HEALTH' Panel.qml
grep -Fq 'COPY-SAFE REPORT' Panel.qml
grep -Fq '["OVERVIEW","CONTROLS","AUTOMATION"]' Panel.qml
grep -Fq 'SIMULATE NOW' Panel.qml
grep -Fq 'ENABLE CPU WATTS' Panel.qml
grep -Fq '["pkexec","/usr/bin/install"' Panel.qml
grep -Fq '["pkexec","/usr/bin/unlink"' Panel.qml
grep -Fq 'chmod","0440"' Panel.qml
grep -Fq 'chmod","0400"' Panel.qml
grep -Fq 'result.ruleInstalled&&result.readable' Panel.qml
grep -Fq '!result.ruleInstalled&&!result.readable' Panel.qml
grep -Fq 'KERNEL=="intel-rapl:[0-9]"' 70-rog-strix-energy.rules
grep -Fq '/usr/bin/chgrp wheel /sys%p/energy_uj' 70-rog-strix-energy.rules
grep -Fq '/usr/bin/chmod 0440 /sys%p/energy_uj' 70-rog-strix-energy.rules
! grep -Eq '0444|066|077|chmod [^ ]*\+w|GROUP=' 70-rog-strix-energy.rules
grep -Fq 'BarWidget {' BarWidget.qml
grep -Fq 'source: Qt.resolvedUrl("Panel.qml")' BarWidget.qml
grep -Fq 'command: [root.helperPath, "action", "automation-tick"]' Service.qml
grep -Fq 'serviceFor(root.moduleName)' BarWidget.qml
if command -v omarchy >/dev/null 2>&1; then omarchy plugin validate .; fi
printf 'all ROG control tests passed\n'
