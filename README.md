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

## Build environment

Install system build tools and cross-compilers **before** using `build_cp.sh`. Follow CircuitPython’s own documentation — this repo does not install compilers or apt packages for you.

- [circuitpython/BUILDING.md](https://github.com/adafruit/circuitpython/blob/main/BUILDING.md) in your clone
- Adafruit Learn: [Building CircuitPython on Linux](https://learn.adafruit.com/building-circuitpython/linux) (or macOS / WSL as appropriate)

Typical Linux setup includes packages such as `build-essential`, `cmake`, `python3`, and port-specific tools (for example `gcc-arm-none-eabi` and related newlib packages for `raspberrypi`). Exact packages depend on the port you build.

CircuitPython **10.2.x** requires **GCC 14** or newer when compiling firmware. Check the compiler your port uses (for embedded boards, usually `arm-none-eabi-gcc --version`). Ubuntu’s `gcc-arm-none-eabi` package is often GCC 13 — too old for current CircuitPython.

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
./circuitpython/ports/unix/build-coverage/micropython ./lv_circuitpython_mod/test_lvgl_cp_unix.py
```

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
| `circuitpython_spike/` | Hand-written `shared-bindings/lvgl` module templates |
| `lv_mem_core_circuitpython.c` | GC-aware LVGL allocator |
| `build_cp.sh` | Build any port/board/variant (interactive or CLI) |
| `docs/` | Integration notes |

See `docs/circuitpython_spike.md` for architecture details.
