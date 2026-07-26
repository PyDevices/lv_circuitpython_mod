# Frozen Python helpers that ship with the LVGL CircuitPython integration.
# Source of truth: PyDevices/lv_bindings python/display_driver.py
# Sync: ./scripts/sync_from_lv_bindings.sh
#
# build_cp.sh wires this for the unix port only (MCU ports keep CircuitPython's
# generated BUILD/manifest.py). It includes the upstream variant manifest via
# FROZEN_MANIFEST_UPSTREAM.

import os

module("display_driver.py", base_path="./lib", opt=3)

_upstream = os.environ.get("FROZEN_MANIFEST_UPSTREAM", "").strip()
if _upstream:
    include(_upstream)
