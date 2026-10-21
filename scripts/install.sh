#!/usr/bin/env bash
# ============================================================================
# noctalia-vivaldi - installer
#
# Adds the "Vivaldi" entry to Noctalia's template list and prints the one
# Vivaldi setting that has to point at the generated CSS.
#
# Idempotent, no sudo, and it never writes to the Vivaldi profile: Vivaldi's
# Preferences are only *read*, to reuse a Custom UI Modifications directory
# that is already configured.
# ============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

PROJECT_NAME="noctalia-vivaldi"
TEMPLATE_ID="vivaldi"
CSS_FILE="noctalia.css"
MARKER="noctalia-vivaldi"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

DEST_DIR="$STATE_HOME/noctalia/community-templates/$TEMPLATE_ID"
SETTINGS_FILE="$STATE_HOME/noctalia/settings.toml"
CSS_DIR_DEFAULT="$CONFIG_HOME/$PROJECT_NAME/css"

DESCRIPTOR_SRC="$REPO_ROOT/integration/v5/template.toml"
TEMPLATE_SRC="$REPO_ROOT/templates/vivaldi.css"

DRY_RUN=0
QUIET=0
FORCE=0
DETECT_VIVALDI=1
OUTPUT_DIR=""

usage() {
    cat <<'EOF'
Install the Noctalia -> Vivaldi theme integration.

Usage: install.sh [options]

Options:
  -n, --dry-run        Print what would be done, change nothing
  -o, --output DIR     Directory Vivaldi reads custom CSS from
                       (default: the directory already configured in Vivaldi,
                       otherwise $XDG_CONFIG_HOME/noctalia-vivaldi/css)
      --no-detect      Do not read Vivaldi's Preferences
  -f, --force          Overwrite a template directory we do not own
  -q, --quiet          Only print warnings and errors
  -h, --help           Show this help
EOF
}

info() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

# -- arguments ---------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -q|--quiet) QUIET=1 ;;
        -f|--force) FORCE=1 ;;
        --no-detect) DETECT_VIVALDI=0 ;;
        -o|--output)
            [ $# -ge 2 ] || die "--output needs a directory"
            OUTPUT_DIR=${2%/}
            shift
            ;;
        -o=*|--output=*) OUTPUT_DIR=${1#*=}; OUTPUT_DIR=${OUTPUT_DIR%/} ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

[ -f "$DESCRIPTOR_SRC" ] || die "missing template descriptor: $DESCRIPTOR_SRC"
[ -f "$TEMPLATE_SRC" ] || die "missing template: $TEMPLATE_SRC"

case "$OUTPUT_DIR" in
    /*) ;;
    "") ;;
    *) die "--output needs an absolute path (got: $OUTPUT_DIR)" ;;
esac

# -- helpers -----------------------------------------------------------------
# Prints the Custom UI Modifications directory Vivaldi is configured with.
vivaldi_css_dir() {
    python3 - <<'PY' 2>/dev/null || true
import glob, json, os

for pref in sorted(glob.glob(os.path.join(os.path.expanduser("~/.config/vivaldi"), "*", "Preferences"))):
    try:
        with open(pref, encoding="utf-8", errors="replace") as handle:
            data = json.load(handle)
    except Exception:
        continue
    value = data.get("vivaldi", {}).get("appearance", {}).get("css_ui_mods_directory")
    if isinstance(value, str) and value.strip():
        print(value.strip())
        break
PY
}

# Prints the folder that holds the Noctalia config, for the enable hint.
noctalia_enabled() {
    [ -f "$SETTINGS_FILE" ] || return 1
    python3 - "$SETTINGS_FILE" "$TEMPLATE_ID" <<'PY' 2>/dev/null || return 1
import sys, tomllib

with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)
ids = data.get("theme", {}).get("templates", {}).get("community_ids", [])
raise SystemExit(0 if sys.argv[2] in ids else 1)
PY
}

# -- 1. output directory -----------------------------------------------------
if [ -z "$OUTPUT_DIR" ] && [ "$DETECT_VIVALDI" -eq 1 ]; then
    OUTPUT_DIR=$(vivaldi_css_dir)
    [ -n "$OUTPUT_DIR" ] && info "Vivaldi already reads custom CSS from $OUTPUT_DIR"
fi
[ -n "$OUTPUT_DIR" ] || OUTPUT_DIR="$CSS_DIR_DEFAULT"

CSS_FILE_PATH="$OUTPUT_DIR/$CSS_FILE"

# -- 2. template directory ---------------------------------------------------
if [ -e "$DEST_DIR/template.toml" ] && ! grep -q "$MARKER" "$DEST_DIR/template.toml" 2>/dev/null && [ "$FORCE" -eq 0 ]; then
    die "$DEST_DIR/template.toml was not installed by this project (use --force to overwrite)"
fi

info "Installing the Noctalia template 'Vivaldi'"
info "  template directory : $DEST_DIR"
info "  generated CSS      : $CSS_FILE_PATH"

run mkdir -p "$DEST_DIR"

# The descriptor is copied with the resolved CSS directory: the `$XDG_CONFIG_HOME`
# token is kept whenever the directory is inside the config home, so the
# installed copy stays portable.
case "$OUTPUT_DIR" in
    "$CONFIG_HOME"/*)
        TOKEN_PATH="\$XDG_CONFIG_HOME/${OUTPUT_DIR#"$CONFIG_HOME"/}/$CSS_FILE" ;;
    *)
        TOKEN_PATH="$CSS_FILE_PATH" ;;
esac

descriptor_tmp=$(mktemp)
sed "s|^output_path = .*|output_path = \"$TOKEN_PATH\"|" "$DESCRIPTOR_SRC" > "$descriptor_tmp"

if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] write %s (output_path = %s)\n' "$DEST_DIR/template.toml" "$TOKEN_PATH"
    printf '[dry-run] copy %s -> %s\n' "$TEMPLATE_SRC" "$DEST_DIR/vivaldi.css"
else
    cmp -s "$descriptor_tmp" "$DEST_DIR/template.toml" || cat "$descriptor_tmp" > "$DEST_DIR/template.toml"
    cmp -s "$TEMPLATE_SRC" "$DEST_DIR/vivaldi.css" || cp "$TEMPLATE_SRC" "$DEST_DIR/vivaldi.css"
fi
rm -f "$descriptor_tmp"

# Noctalia caches the md5 of every file it knows about; without the cache file
# it would try to download the template files from the community catalogue.
if [ "$DRY_RUN" -eq 0 ]; then
    python3 - "$DEST_DIR" <<'PY'
import hashlib, json, os, sys

directory = sys.argv[1]
files = {}
for name in sorted(os.listdir(directory)):
    path = os.path.join(directory, name)
    if name.startswith(".") or not os.path.isfile(path):
        continue
    with open(path, "rb") as handle:
        files[name] = hashlib.md5(handle.read()).hexdigest()
with open(os.path.join(directory, ".noctalia-cache.json"), "w", encoding="utf-8") as handle:
    json.dump({"files": files, "version": 1}, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
fi

# -- 3. what is left to do ---------------------------------------------------
info ""
if noctalia_enabled; then
    info "Noctalia: 'Vivaldi' is enabled - templates/vivaldi.css is rendered into"
    info "          $CSS_FILE_PATH on every palette change."
else
    info "Noctalia: enable the template once - Settings -> Templates -> 'Vivaldi',"
    info "          or run: noctalia msg settings-open templates"
fi

if [ "$DETECT_VIVALDI" -eq 1 ]; then
    configured=$(vivaldi_css_dir)
    if [ "$configured" = "$OUTPUT_DIR" ]; then
        info "Vivaldi : Custom UI Modifications already points at $OUTPUT_DIR"
    else
        info "Vivaldi : set Settings -> Appearance -> Custom UI Modifications ->"
        info "          Select Folder... to"
        info "          $OUTPUT_DIR"
        info "          If that block is missing, enable the 'VivaldiCssMods' flag"
        info "          in vivaldi://experiments/ first. A restart applies both."
    fi
    if [ -f "$CSS_FILE_PATH" ]; then
        info "CSS     : $CSS_FILE_PATH (ready)"
    else
        info "CSS     : not generated yet - it appears after the first palette"
        info "          change (or: noctalia msg templates-apply)"
    fi
fi
