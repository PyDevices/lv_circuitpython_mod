#!/usr/bin/env bash
# Apply (or preview) CircuitPython LVGL integration patches.
#
# Usage:
#   ./apply_cp_lvgl_patches.sh --apply --port PORT [--board BOARD] [--variant VARIANT]
#   ./apply_cp_lvgl_patches.sh --force-apply --port PORT ...   # reinstall (user only)
#   ./apply_cp_lvgl_patches.sh --dry-run --port PORT ...
#   ./apply_cp_lvgl_patches.sh --status --port PORT ...
#
# Environment: WORKSPACE_DIR, CP_DIR, PORT, BOARD, VARIANT

set -euo pipefail

LV_CP_MOD_DIR=$(cd "$(dirname "$0")" && pwd)
WORKSPACE_DIR="${WORKSPACE_DIR:-$(cd "$LV_CP_MOD_DIR/.." && pwd)}"
CP_DIR="${CP_DIR:-$WORKSPACE_DIR/circuitpython}"
if [ ! -d "$CP_DIR/.git" ] && [ -d "$HOME/github/circuitpython/.git" ]; then
    CP_DIR="$HOME/github/circuitpython"
fi

PORT="${PORT:-}"
BOARD="${BOARD:-}"
VARIANT="${VARIANT:-}"
MODE=""
SPIKE_DIR="$LV_CP_MOD_DIR/circuitpython_spike"
SPIKE_MANIFEST="$SPIKE_DIR/copy_manifest.txt"

MARKER_TAG="lv-circuitpython-mod begin (apply_cp_lvgl_patches.sh)"
MARKER_BEGIN="# >>> $MARKER_TAG"
MARKER_END="# >>> lv-circuitpython-mod end"

DRY_RUN=0
APPLY=0
FORCE=0
CONFIG_MKS=()
CONFIG_HS=()

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|--apply|--force-apply|--status) MODE="$1"; shift ;;
        --port)    PORT="$2"; shift 2 ;;
        --board)   BOARD="$2"; shift 2 ;;
        --variant) VARIANT="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *) die "Unknown argument: $1 (try --help)" ;;
    esac
done

MODE="${MODE:---dry-run}"
case "$MODE" in
    --dry-run) DRY_RUN=1 ;;
    --apply) APPLY=1 ;;
    --force-apply) APPLY=1; FORCE=1 ;;
    --status) ;;
    *) die "Unknown mode: $MODE" ;;
esac

log() { echo "$*"; }

markers_for_file() {
    local file="$1"
    case "$file" in
        *.h)
            echo "/* >>> $MARKER_TAG */"
            echo "/* >>> lv-circuitpython-mod end */"
            ;;
        *)
            echo "$MARKER_BEGIN"
            echo "$MARKER_END"
            ;;
    esac
}

repair_invalid_header_markers() {
    local file="$1"
    [ -f "$file" ] || return 0
    case "$file" in
        *.h) ;;
        *) return 0 ;;
    esac
    if ! grep -qF "# >>> lv-circuitpython-mod" "$file"; then
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] repair invalid # markers in $file"
        return 0
    fi
    python3 - "$file" "$MARKER_TAG" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
tag = sys.argv[2]
text = path.read_text()
text = text.replace(f"# >>> {tag}", f"/* >>> {tag} */")
text = text.replace("# >>> lv-circuitpython-mod end", "/* >>> lv-circuitpython-mod end */")
path.write_text(text)
PY
    log "  repaired header markers: $file"
}

remove_marked_blocks() {
    local file="$1"
    local tag="$2"
    [ -f "$file" ] || return 0
    if ! grep -qF "$tag" "$file" 2>/dev/null; then
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] remove marked blocks from $file"
        return 0
    fi
    python3 - "$file" "$tag" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
tag = re.escape(sys.argv[2])
text = path.read_text()
patterns = [
    rf"\n?# >>> {tag}\n.*?\n# >>> lv-circuitpython-mod end\n?",
    rf"\n?/\* >>> {tag} \*/\n.*?\n/\* >>> lv-circuitpython-mod end \*/\n?",
]
for pat in patterns:
    text = re.sub(pat, "\n", text, count=0, flags=re.DOTALL)
path.write_text(text)
PY
}

remove_legacy_patches() {
    remove_marked_blocks "$1" "cmods-lvgl begin (apply_cp_lvgl_patches.sh)"
}

remove_current_patches() {
    remove_marked_blocks "$1" "$MARKER_TAG"
}

remove_raw_lvgl_lines() {
    local file="$1"
    [ -f "$file" ] || return 0
    if ! grep -qF 'lvgl/__init__.c' "$file" 2>/dev/null; then
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] remove raw lvgl source lines from $file"
        return 0
    fi
    python3 - "$file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = [
    line for line in path.read_text().splitlines(keepends=True)
    if "lvgl/__init__.c" not in line
]
path.write_text("".join(lines))
PY
    log "  removed raw lvgl source lines: $file"
}

patch_block_present() {
    local file="$1"
    local needle="${2:-lv-circuitpython-mod begin}"
    [ -f "$file" ] && grep -qF "$needle" "$file"
}

should_skip_patch() {
    local file="$1"
    local needle="${2:-lv-circuitpython-mod begin}"
    [ "$FORCE" = 0 ] && patch_block_present "$file" "$needle"
}

append_marked_block() {
    local file="$1"
    local block="$2"
    local needle="${3:-lv-circuitpython-mod begin}"
    repair_invalid_header_markers "$file"
    if should_skip_patch "$file" "$needle"; then
        log "  skip (already patched): $file"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] append block to $file"
        return 0
    fi
    local begin end
    begin=$(markers_for_file "$file" | sed -n '1p')
    end=$(markers_for_file "$file" | sed -n '2p')
    python3 - "$file" "$begin" "$end" "$block" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
begin = sys.argv[2]
end = sys.argv[3]
block = sys.argv[4]

text = path.read_text()
if not text.endswith("\n"):
    text += "\n"
text += f"{begin}\n{block}\n{end}\n"
path.write_text(text)
PY
    log "  patched: $file"
}

insert_block_before_line() {
    local file="$1"
    local anchor="$2"
    local block="$3"
    local needle="${4:-lv-circuitpython-mod begin}"
    repair_invalid_header_markers "$file"
    if should_skip_patch "$file" "$needle"; then
        log "  skip (already patched): $file"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] insert block into $file before: $anchor"
        return 0
    fi
    local begin end
    begin=$(markers_for_file "$file" | sed -n '1p')
    end=$(markers_for_file "$file" | sed -n '2p')
    python3 - "$file" "$anchor" "$begin" "$end" "$block" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
anchor = sys.argv[2]
begin = sys.argv[3]
end = sys.argv[4]
block = sys.argv[5]

text = path.read_text()
if begin in text:
    sys.exit(0)
if anchor not in text:
    raise SystemExit(f"anchor not found in {path}: {anchor!r}")
insert = f"\n{begin}\n{block}\n{end}\n"
path.write_text(text.replace(anchor, insert + anchor, 1))
PY
    log "  patched: $file"
}

insert_block_after_line() {
    local file="$1"
    local anchor="$2"
    local block="$3"
    local needle="${4:-lv-circuitpython-mod begin}"
    repair_invalid_header_markers "$file"
    if should_skip_patch "$file" "$needle"; then
        log "  skip (already patched): $file"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] insert block into $file after: $anchor"
        return 0
    fi
    local begin end
    begin=$(markers_for_file "$file" | sed -n '1p')
    end=$(markers_for_file "$file" | sed -n '2p')
    python3 - "$file" "$anchor" "$begin" "$end" "$block" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
anchor = sys.argv[2]
begin = sys.argv[3]
end = sys.argv[4]
block = sys.argv[5]

text = path.read_text()
if begin in text:
    sys.exit(0)
if anchor not in text:
    raise SystemExit(f"anchor not found in {path}: {anchor!r}")
insert = f"\n{begin}\n{block}\n{end}\n"
path.write_text(text.replace(anchor, anchor + insert, 1))
PY
    log "  patched: $file"
}

insert_raw_after_line() {
    local file="$1"
    local anchor="$2"
    local line="$3"
    if [ "$FORCE" = 0 ] && grep -qF "$line" "$file" 2>/dev/null; then
        log "  skip (already present): $file"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] insert into $file after: $anchor"
        return 0
    fi
    python3 - "$file" "$anchor" "$line" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
anchor = sys.argv[2]
line = sys.argv[3]

text = path.read_text()
if line in text:
    sys.exit(0)
if anchor not in text:
    raise SystemExit(f"anchor not found in {path}: {anchor!r}")
path.write_text(text.replace(anchor, anchor + "\n" + line, 1))
PY
    log "  patched: $file"
}

copy_spike_files() {
    python3 - "$SPIKE_DIR" "$CP_DIR" "$SPIKE_MANIFEST" "$DRY_RUN" <<'PY'
import filecmp
import shutil
import sys
from pathlib import Path

spike_dir, cp_dir, manifest, dry = sys.argv[1:5]
dry_run = dry == "1"

def copy_one(rel_dir: str, filename: str) -> None:
    rel = f"{rel_dir}/{filename}"
    src = Path(spike_dir)
    dst = Path(cp_dir)
    for part in rel_dir.split("/"):
        src /= part
        dst /= part
    src /= filename
    dst /= filename
    if not src.is_file():
        raise SystemExit(f"missing spike file: {src}")
    if dst.is_file() and filecmp.cmp(src, dst, shallow=False):
        print(f"  unchanged: {rel}")
        return
    if dry_run:
        verb = "update" if dst.is_file() else "create"
        print(f"  [dry-run] {verb} {rel}")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    print(f"  copied: {rel}")

for raw in Path(manifest).read_text().splitlines():
    line = raw.split("#", 1)[0].strip()
    if not line:
        continue
    rel_dir, filename = line.split("\t", 1)
    copy_one(rel_dir.strip(), filename.strip())
PY
}

resolve_config_files() {
    PORT_DIR="$CP_DIR/ports/$PORT"
    [[ -n "$PORT" ]] || die "PORT is required (--port or env)"
    [[ -f "$PORT_DIR/Makefile" ]] || die "Invalid port: $PORT"

    CONFIG_MKS=()
    CONFIG_HS=()

    if [[ -n "$BOARD" && -f "$PORT_DIR/boards/$BOARD/mpconfigboard.mk" ]]; then
        CONFIG_MKS+=("$PORT_DIR/boards/$BOARD/mpconfigboard.mk")
        [[ -f "$PORT_DIR/boards/$BOARD/mpconfigboard.h" ]] && \
            CONFIG_HS+=("$PORT_DIR/boards/$BOARD/mpconfigboard.h")
    fi

    local vdir=""
    if [[ -n "$BOARD" && -n "$VARIANT" && -f "$PORT_DIR/boards/$BOARD/variants/$VARIANT/mpconfigvariant.mk" ]]; then
        vdir="$PORT_DIR/boards/$BOARD/variants/$VARIANT"
    elif [[ -n "$VARIANT" && -f "$PORT_DIR/variants/$VARIANT/mpconfigvariant.mk" ]]; then
        vdir="$PORT_DIR/variants/$VARIANT"
    fi
    if [[ -n "$vdir" ]]; then
        CONFIG_MKS+=("$vdir/mpconfigvariant.mk")
        [[ -f "$vdir/mpconfigvariant.h" ]] && CONFIG_HS+=("$vdir/mpconfigvariant.h")
    fi

    [[ ${#CONFIG_MKS[@]} -gt 0 ]] || \
        die "No mpconfig makefiles for PORT=$PORT BOARD=${BOARD:-} VARIANT=${VARIANT:-}"
}

port_makefile_anchor() {
    if grep -qF 'include ../../py/mkenv.mk' "$PORT_MK"; then
        echo 'include ../../py/mkenv.mk'
    elif grep -qF 'include ../../py/circuitpy_mkenv.mk' "$PORT_MK"; then
        echo 'include ../../py/circuitpy_mkenv.mk'
    else
        die "No known mkenv include anchor in $PORT_MK"
    fi
}

patch_config_header() {
    local h="$1"
    local block="#ifndef CIRCUITPY_LVGL
#define CIRCUITPY_LVGL (0)
#endif"
    if grep -qF '#pragma once' "$h"; then
        insert_block_after_line "$h" '#pragma once' "$block"
    elif grep -qF '#include "../mpconfigvariant_common.h"' "$h"; then
        insert_block_after_line "$h" '#include "../mpconfigvariant_common.h"' "$block"
    else
        log "  skip header (no known anchor): $h"
    fi
}

patch_module_sources_if_present() {
    local mk="$1"
    if grep -qF 'shared-bindings/jpegio/JpegDecoder.c \' "$mk"; then
        insert_raw_after_line "$mk" $'shared-bindings/jpegio/JpegDecoder.c \\' \
            $'\tshared-bindings/lvgl/__init__.c \\'
        insert_raw_after_line "$mk" $'shared-module/jpegio/JpegDecoder.c \\' \
            $'\tshared-module/lvgl/__init__.c \\'
    else
        log "  skip module sources (no jpegio list in $mk)"
    fi
}

build_next_cmd() {
    local -a cmd=("$LV_CP_MOD_DIR/build_cp.sh" --port "$PORT")
    [[ -n "$BOARD" ]] && cmd+=(--board "$BOARD")
    [[ -n "$VARIANT" ]] && cmd+=(--variant "$VARIANT")
    printf '%q ' "${cmd[@]}"
}

collect_patch_files() {
    ALL_PATCH_FILES=("$PORT_MK" "$MPCONFIG_MK" "$DEFNS_MK")
    ALL_PATCH_FILES+=("${CONFIG_MKS[@]}")
    ALL_PATCH_FILES+=("${CONFIG_HS[@]}")
}

# --- main ---

[ -d "$CP_DIR/.git" ] || die "CircuitPython tree not found at $CP_DIR"
[ -f "$SPIKE_MANIFEST" ] || die "Missing spike manifest: $SPIKE_MANIFEST"

resolve_config_files

DEFNS_MK="$CP_DIR/py/circuitpy_defns.mk"
MPCONFIG_MK="$CP_DIR/py/circuitpy_mpconfig.mk"
PORT_MK="$PORT_DIR/Makefile"
LV_CP_MOD_REL=$(python3 -c "import os; print(os.path.relpath('$LV_CP_MOD_DIR', '$PORT_DIR'))")
collect_patch_files

log "CircuitPython: $CP_DIR"
log "workspace:     $WORKSPACE_DIR"
log "lv_circuitpython_mod: $LV_CP_MOD_DIR (as $LV_CP_MOD_REL from port)"
log "port:            $PORT"
[[ -n "$BOARD" ]] && log "board:           $BOARD"
[[ -n "$VARIANT" ]] && log "variant:         $VARIANT"
log "mode:            $MODE"
log

if [ "$MODE" = "--status" ]; then
    SPIKE_INIT_C=$(python3 - "$SPIKE_MANIFEST" "$CP_DIR" <<'PY'
import sys
from pathlib import Path
manifest, cp_dir = sys.argv[1:3]
rel_dir, filename = Path(manifest).read_text().splitlines()[0].split("\t", 1)
p = Path(cp_dir)
for part in rel_dir.split("/"):
    p /= part
p /= filename.strip()
print(p)
PY
)
    report() {
        local label="$1"
        local file="$2"
        if [ ! -e "$file" ]; then
            echo "missing  $file"
        elif [ "$label" = "spike" ]; then
            echo "ok       $file"
        elif patch_block_present "$file"; then
            echo "patched  $file"
        else
            echo "pending  $file"
        fi
    }
    report spike "$SPIKE_INIT_C"
    for mk in "${CONFIG_MKS[@]}"; do report patch "$mk"; done
    for h in "${CONFIG_HS[@]}"; do report patch "$h"; done
    report patch "$DEFNS_MK"
    report patch "$MPCONFIG_MK"
    report patch "$PORT_MK"
    exit 0
fi

if [ "$FORCE" = 1 ]; then
    log "==> Remove existing LVGL patches (force reinstall)"
    for _f in "${ALL_PATCH_FILES[@]}"; do
        remove_current_patches "$_f"
        remove_legacy_patches "$_f"
        remove_raw_lvgl_lines "$_f"
    done
    log
fi

log "==> Copy spike templates"
copy_spike_files
log

if [ "$APPLY" = 1 ] || [ "$DRY_RUN" = 1 ]; then
    log "==> Remove legacy cmods-lvgl patches (if present)"
    for _legacy in "${ALL_PATCH_FILES[@]}"; do
        remove_legacy_patches "$_legacy"
    done
    log
fi

LVGL_ENABLE_BLOCK="CIRCUITPY_LVGL = 1
CFLAGS += -DCIRCUITPY_LVGL=1
CFLAGS += -DLVGL_GENERATED_PHASE1=1"

for mk in "${CONFIG_MKS[@]}"; do
    log "==> Patch $(basename "$(dirname "$mk")")/$(basename "$mk")"
    append_marked_block "$mk" "$LVGL_ENABLE_BLOCK"
    patch_module_sources_if_present "$mk"
    log
done

for h in "${CONFIG_HS[@]}"; do
    log "==> Patch $(basename "$h")"
    patch_config_header "$h"
    log
done

log "==> Patch py/circuitpy_mpconfig.mk (default off)"
MPCONFIG_BLOCK="CIRCUITPY_LVGL ?= 0
CFLAGS += -DCIRCUITPY_LVGL=\$(CIRCUITPY_LVGL)"
insert_block_after_line "$MPCONFIG_MK" "CFLAGS += -DCIRCUITPY_LOCALE=\$(CIRCUITPY_LOCALE)" "$MPCONFIG_BLOCK"
log

log "==> Patch py/circuitpy_defns.mk"
DEFNS_PATTERNS_BLOCK="ifeq (\$(CIRCUITPY_LVGL),1)
SRC_PATTERNS += lvgl/%
endif"
insert_block_before_line "$DEFNS_MK" "ifeq (\$(CIRCUITPY_MATH),1)" "$DEFNS_PATTERNS_BLOCK" "SRC_PATTERNS += lvgl/%"
insert_raw_after_line "$DEFNS_MK" $'\tjpegio/JpegDecoder.c \\' $'\tlvgl/__init__.c \\'
log

log "==> Patch port Makefile (circuitpython.mk)"
PORT_BLOCK="LV_CP_MOD_DIR := \$(abspath $LV_CP_MOD_REL)
include \$(LV_CP_MOD_DIR)/circuitpython.mk"
insert_block_after_line "$PORT_MK" "$(port_makefile_anchor)" "$PORT_BLOCK"
log

if [ "$DRY_RUN" = 1 ]; then
    log "Dry run complete. Re-run with --apply to write changes."
elif [ "$APPLY" = 1 ]; then
    log "Patches applied."
    log
    log "Next:"
    log "  $WORKSPACE_DIR/lv_bindings/regenerate_lvcp.sh"
    log "  $(build_next_cmd)"
fi
