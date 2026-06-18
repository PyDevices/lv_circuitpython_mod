# lv_circuitpython_mod

CircuitPython integration for LVGL: tree patches, build glue, spike templates, and tests.

Requires sibling clones of [lv_bindings](https://github.com/PyDevices/lv_bindings) (generated `lvcp.c`) and [circuitpython](https://github.com/adafruit/circuitpython) (pin **10.2.1**).

## Workspace layout

Place this repo as a sibling of `lv_bindings/` and `circuitpython/`:

```
workspace/
  lv_circuitpython_mod/     ← this repo
  lv_bindings/
  circuitpython/
```

Or clone into [cmods](https://github.com/PyDevices/cmods) when using the optional MP wrapper (`cmods/` becomes the workspace).

## First-time setup

```bash
git clone git@github.com:adafruit/circuitpython.git circuitpython
cd circuitpython
git fetch --tags
git checkout -B circuitpython-10.2.1 10.2.1
make fetch-all-submodules
cd ..

git clone git@github.com:PyDevices/lv_bindings.git lv_bindings
cd lv_bindings
git submodule update --init lvgl
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
./regenerate_lvcp.sh
cd ..
```

## Patch and build

```bash
cd lv_circuitpython_mod
./apply_cp_lvgl_patches.sh --dry-run    # preview
./apply_cp_lvgl_patches.sh --apply      # write patches + copy spike
./build_cp_unix.sh
```

Smoke test:

```bash
./circuitpython/ports/unix/build-coverage/micropython ./lv_circuitpython_mod/test_lvgl_cp_unix.py
```

## Environment variables

| Variable | Default |
|----------|---------|
| `WORKSPACE_DIR` | Parent of `lv_circuitpython_mod/` |
| `CP_DIR` | `$WORKSPACE_DIR/circuitpython` |
| `PORT` | `unix` |
| `VARIANT` | `coverage` |

## Files

| Path | Role |
|------|------|
| `circuitpython.mk` | Port Makefile fragment (LVGL + `lvcp.c` + allocator) |
| `apply_cp_lvgl_patches.sh` | Patch CP tree and copy spike templates |
| `circuitpython_spike/` | Hand-written `shared-bindings/lvgl` module templates |
| `lv_mem_core_circuitpython.c` | GC-aware LVGL allocator |
| `build_cp_unix.sh` | Build unix coverage variant |
| `docs/` | Integration notes |

See `docs/circuitpython_spike.md` for architecture details.
