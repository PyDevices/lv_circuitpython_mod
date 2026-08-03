# lv_circuitpython_mod

CircuitPython integration for LVGL: tree patches, build glue, spike templates, and tests.

This repo is a consumer/build repo for the LVGL stack. It consumes generated bindings from lv_bindings and rebuilds CircuitPython targets, but it does not publish its own package to TestPyPI; lv_cpython_mod is the publishing endpoint for the family.

Requires sibling clones of [lv_bindings](https://github.com/PyDevices/lv_bindings) (generated `lvcp.c`) and [circuitpython](https://github.com/adafruit/circuitpython). Check out a [stable release tag](https://github.com/adafruit/circuitpython/releases) — pick the version yourself; this repo does not track a specific CircuitPython version.

## Workspace layout

Place this repo as a sibling of `lv_bindings/` and `circuitpython/`:

```
workspace/
  lv_circuitpython_mod/     ← this repo
  lv_bindings/
  circuitpython/
```

([cmods](https://github.com/PyDevices/cmods) is an optional convenience workspace that sets up this same sibling layout — not required.)

For day-to-day work, this repo is the place to patch CircuitPython’s LVGL integration, not the place to author the generator itself. The common loop is to change the patch set or the spike templates under **`src/`**, rebuild a target port with **`build_cp.sh`**, and then smoke-test with the shared LVGL smoke script. If the underlying binding shape changed, regenerate **`lv_bindings`** first so the generated `lvcp.c` and header files stay in sync.

## 🚀 First-time setup

```bash
# Pick a stable release tag from https://github.com/adafruit/circuitpython/releases
git clone --branch 10.2.1 https://github.com/adafruit/circuitpython.git circuitpython
cd circuitpython
make fetch-all-submodules
cd ..

git clone https://github.com/PyDevices/lv_bindings.git lv_bindings
cd lv_bindings
git submodule update --init lvgl
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
./regenerate_lvcp.sh
cd ..
```

## Build environment

Install system build tools and cross-compilers **before** using `build_cp.sh`. Follow CircuitPython’s own documentation — this repo does not install compilers or apt packages for you.

- [circuitpython/BUILDING.md](https://github.com/adafruit/circuitpython/blob/main/BUILDING.md) in your clone
- Adafruit Learn: [Building CircuitPython on Linux](https://learn.adafruit.com/building-circuitpython/linux) (or macOS / WSL as appropriate)

Typical Linux setup includes packages such as `build-essential`, `cmake`, `python3`, and port-specific tools (for example `gcc-arm-none-eabi` and related newlib packages for `raspberrypi`). Exact packages depend on the port you build.

Current stable CircuitPython releases require **GCC 14** or newer when compiling firmware. Check the compiler your port uses (for embedded boards, usually `arm-none-eabi-gcc --version`). Ubuntu’s `gcc-arm-none-eabi` package is often GCC 13 — too old for current CircuitPython.

Install a **system-wide** Arm GNU Toolchain 14+ (not under your home directory or this repo). Example on Linux:

```bash
# Download (or use an existing .tar.xz)
curl -fLO https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi.tar.xz

# Install under /opt and expose to all users
sudo tar -xJf arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi.tar.xz -C /opt
printf '%s\n' 'export PATH="/opt/arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi/bin:$PATH"' \
  | sudo tee /etc/profile.d/arm-gnu-toolchain.sh
sudo chmod 644 /etc/profile.d/arm-gnu-toolchain.sh

# Activate in the current shell, then verify
source /etc/profile.d/arm-gnu-toolchain.sh
arm-none-eabi-gcc --version   # should report GCC 14.x
which arm-none-eabi-gcc       # should be under /opt/..., not /usr/bin
```

Open a new terminal (or `source /etc/profile.d/arm-gnu-toolchain.sh`) before running `build_cp.sh`.

`build_cp.sh` only manages a local Python venv (`.venv/`) and installs `circuitpython/requirements-dev.txt`. If `minify_html` fails to install, you may need Rust (see CircuitPython `BUILDING.md`).

## Patch and build

```bash
cd lv_circuitpython_mod
./apply_cp_lvgl_patches.sh --dry-run --port unix --variant coverage
./apply_cp_lvgl_patches.sh --apply --port unix --variant coverage
./apply_cp_lvgl_patches.sh --force-apply --port unix --variant coverage  # reinstall patches
./build_cp.sh --port unix --variant standard   # LVGL dev (no gcov)
./build_cp.sh --port unix --variant coverage   # CP test suite / gcov
```

Examples:

```bash
./build_cp.sh --port espressif --board espressif_esp32p4_function_ev
./build_cp.sh    # interactive port/board/variant selection
```

`build_cp.sh` always runs `apply_cp_lvgl_patches.sh --apply` before make (idempotent).

Smoke test:

```bash
./circuitpython/ports/unix/build-coverage/micropython ./lv_circuitpython_mod/tools/test_lvgl_cp_unix.py
```

Prefer the unified smoke test directly: `lv_bindings/tools/test_lvgl_smoke.py`.

## Environment variables

| Variable | Default |
|----------|---------|
| `WORKSPACE_DIR` | Parent of `lv_circuitpython_mod/` |
| `CP_DIR` | `$WORKSPACE_DIR/circuitpython` |
| `CP_BUILD_VENV` | `$SCRIPT_DIR/.venv` |
| `PORT` | (prompted or pass `--port`) |
| `BOARD` | (prompted or pass `--board`) |
| `VARIANT` | (prompted or pass `--variant`) |

## Files

| Path | Role |
|------|------|
| `circuitpython.mk` | Port Makefile fragment (LVGL + `lvcp.c` + allocator) |
| `apply_cp_lvgl_patches.sh` | Patch CP tree and copy spike templates (`--apply`, `--force-apply`, `--status`) |
| `src/circuitpython_spike/` | Hand-written `shared-bindings/lvgl` module templates |
| `src/lv_mem_core_circuitpython.c` | GC-aware LVGL allocator |
| `tools/test_lvgl_cp_unix.py` | Deprecated wrapper → `lv_bindings/tools/test_lvgl_smoke.py` |
| `build_cp.sh` | Build any port/board/variant (interactive or CLI) |
| `docs/` | Integration notes |

See `docs/circuitpython_spike.md` for architecture details.

## Frozen Python

`manifest.py` freezes `lib/display_driver.py` on unix builds. Sync from lv_bindings with `./scripts/sync_from_lv_bindings.sh`.
