# Changelog

## 5.1.0 - 2026-08-27

- Add opt-in CPU-watts permission detection and a confirmed Polkit workflow.
- Bundle a narrow root-owned udev rule granting `wheel` read-only `0440`
  access to package RAPL energy counters, with immediate application,
  verification, and a symmetric removal path.

## 5.0.0 - 2026-08-27

- Adopt the Quattro `BarWidget.qml` plus injected `Panel.qml` lifecycle.
- Add a headless service as the shared telemetry and automation owner.
- Redesign the dashboard around Overview, Controls, and Automation views.
- Add explicit action phases, automation simulation, manual pauses, and a
  bounded policy event timeline.
- Discover batteries and AC adapters by sysfs type instead of fixed names.
- Add fake-sysfs testing, configuration v1-to-v2 migration, action locking,
  marketplace documentation, CI, packaging, and a preview image.

## 4.0.1

- Fix the post-game policy transition and preserve useful action output.
- Strengthen configuration validation and AMD CPU-power telemetry.
