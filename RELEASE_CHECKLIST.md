# Release checklist

- [ ] Update `manifest.json`, helper, panel fallback, and changelog versions.
- [ ] Run `shellcheck rog-strix-control test.sh package.sh verify-package.sh`.
- [ ] Run `./test.sh` and `omarchy plugin validate .`.
- [ ] Run `qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Service.qml`.
- [ ] Test click, Escape, summon/hide, panel switching, disable/re-enable, and shell restart.
- [ ] Test every supported hardware action and one forced rollback on real hardware.
- [ ] Test CPU-watts install, immediate read access, reboot persistence, and removal.
- [ ] Inspect `preview.png`, README compatibility notes, and dependency list.
- [ ] Run `./package.sh`, inspect the archive, and publish its SHA-256.
