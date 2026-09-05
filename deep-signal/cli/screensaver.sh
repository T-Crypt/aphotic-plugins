#!/usr/bin/env bash
# `aphotic screensaver` -- what the Deep Signal screensaver spells out.
#
# Sourced by core's plugin CLI dispatch (aphotic_plugin_cli_run), not
# executed, so aphotic_err/aphotic_warn/aphotic_log and the XDG paths are
# already in scope exactly as they are for a core cmd_*.sh.
#
# Writes one file. The shell watches it and picks up a change with no
# restart, so there is nothing to reload after any of these.

_ds_file="${XDG_CONFIG_HOME:-$HOME/.config}/aphotic/branding/screensaver.txt"

_ds_usage() {
    cat <<'USAGE'
aphotic screensaver <command>

  text <words>            Spell out <words> instead of the wordmark
  import <image> [cols]   Render an image as ASCII (default 78 columns)
  show                    Print what the screensaver currently shows
  reset                   Go back to the wordmark
USAGE
}

_ds_write() {
    mkdir -p "$(dirname "$_ds_file")" || return 1
    printf '%s\n' "$1" > "$_ds_file"
}

case "${1:-}" in
    text)
        shift
        [[ $# -gt 0 ]] || { aphotic_err "nothing to spell out"; _ds_usage; return 1; }
        _ds_write "$*" || return 1
        aphotic_log "screensaver text set"
        ;;
    import)
        _ds_image="${2:-}"
        _ds_cols="${3:-78}"
        [[ -f "$_ds_image" ]] || { aphotic_err "no such image: ${_ds_image:-<none>}"; return 1; }
        [[ "$_ds_cols" =~ ^[0-9]+$ ]] || { aphotic_err "columns must be a number: $_ds_cols"; return 1; }

        # python-pillow is already a base dependency (it is in every
        # install profile's prep set), so this needs nothing new. Kept in
        # Python rather than shelling out to an ASCII-art binary because
        # that would be a dependency for one command.
        if ! python3 -c 'import PIL' >/dev/null 2>&1; then
            aphotic_err "python-pillow is not installed; cannot convert an image"
            return 1
        fi

        _ds_art="$(APHOTIC_DS_IMAGE="$_ds_image" APHOTIC_DS_COLS="$_ds_cols" python3 - <<'PY'
import os
import sys

from PIL import Image, ImageOps

# Darkest to lightest. The screensaver draws light on near-black, so the
# ramp is inverted against the usual print convention.
RAMP = " .:-=+*#%@"

cols = max(8, min(200, int(os.environ["APHOTIC_DS_COLS"])))

try:
    img = ImageOps.exif_transpose(Image.open(os.environ["APHOTIC_DS_IMAGE"]))
except Exception as exc:
    print(f"could not read the image: {exc}", file=sys.stderr)
    raise SystemExit(1)

img = ImageOps.autocontrast(img.convert("L"))
# A terminal cell is roughly twice as tall as it is wide.
rows = max(1, round(cols * img.height / img.width * 0.5))
img = img.resize((cols, rows))

pixels = img.load()
lines = []
for y in range(rows):
    lines.append("".join(RAMP[pixels[x, y] * (len(RAMP) - 1) // 255] for x in range(cols)).rstrip())

print("\n".join(line for line in lines).strip("\n"))
PY
        )" || { aphotic_err "image conversion failed"; return 1; }

        [[ -n "$_ds_art" ]] || { aphotic_err "that image converted to nothing"; return 1; }
        _ds_write "$_ds_art" || return 1
        aphotic_log "screensaver art imported from $(basename "$_ds_image") at ${_ds_cols} columns"
        ;;
    show)
        if [[ -f "$_ds_file" ]]; then
            cat "$_ds_file"
        else
            echo "APHOTIC (default wordmark)"
        fi
        ;;
    reset)
        rm -f "$_ds_file"
        aphotic_log "screensaver back to the wordmark"
        ;;
    ""|-h|--help|help)
        _ds_usage
        ;;
    *)
        aphotic_err "unknown screensaver command: $1"
        _ds_usage
        return 1
        ;;
esac
