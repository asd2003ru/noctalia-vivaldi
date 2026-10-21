#!/usr/bin/env bash
# ============================================================================
# noctalia-vivaldi - diagnostics
#
# Verifies every installed piece and the generated stylesheet. It never claims
# that Vivaldi actually loaded the CSS: Custom UI CSS is read at start-up only
# and cannot be observed from outside the browser.
# ============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

PROJECT_NAME="noctalia-vivaldi"
TEMPLATE_ID="vivaldi"
CSS_FILE_NAME="noctalia.css"
MARKER="noctalia-vivaldi"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

DEST_DIR="$STATE_HOME/noctalia/community-templates/$TEMPLATE_ID"
SETTINGS_FILE="$STATE_HOME/noctalia/settings.toml"
CSS_DIR_DEFAULT="$CONFIG_HOME/$PROJECT_NAME/css"

QUIET=0
CHECK_VIVALDI=1
OUTPUT_DIR=""

FAILURES=0
WARNINGS=0

usage() {
    cat <<'EOF'
Check the Noctalia -> Vivaldi theme integration.

Usage: check.sh [options]

Options:
  -o, --output DIR     Directory holding the generated noctalia.css
                       (default: read from the installed template)
      --no-vivaldi     Do not read Vivaldi's Preferences
  -q, --quiet          Only print failures and warnings
  -h, --help           Show this help
EOF
}

ok()   { [ "$QUIET" -eq 1 ] || printf 'ok    %s\n' "$*"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL  %s\n' "$*" >&2; }
warn() { WARNINGS=$((WARNINGS + 1)); printf 'warn  %s\n' "$*" >&2; }

expand_xdg_token() {
    local path=$1
    path=${path/#\$XDG_CONFIG_HOME/${XDG_CONFIG_HOME:-$HOME/.config}}
    path=${path/#\$XDG_DATA_HOME/${XDG_DATA_HOME:-$HOME/.local/share}}
    path=${path/#\$XDG_STATE_HOME/${XDG_STATE_HOME:-$HOME/.local/state}}
    path=${path/#\$XDG_CACHE_HOME/${XDG_CACHE_HOME:-$HOME/.cache}}
    # shellcheck disable=SC2088
    case "$path" in "~/"*) path="$HOME/${path#\~/}" ;; esac
    printf '%s' "$path"
}

css_dir_from_descriptor() {
    [ -r "$DEST_DIR/template.toml" ] || return 1
    local raw
    raw=$(sed -n 's/^[[:space:]]*output_path[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$DEST_DIR/template.toml" | head -n1)
    [ -n "$raw" ] || return 1
    dirname -- "$(expand_xdg_token "$raw")"
}

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

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)   [ $# -ge 2 ] || { echo "--output needs an argument" >&2; exit 2; }; OUTPUT_DIR=$2; shift ;;
        -o=*|--output=*) OUTPUT_DIR=${1#*=} ;;
        --no-vivaldi)  CHECK_VIVALDI=0 ;;
        -q|--quiet)    QUIET=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

main() {
    ok "project : $PROJECT_NAME"
    if command -v noctalia >/dev/null 2>&1; then
        ok "noctalia : $(noctalia --version 2>/dev/null | head -n1)"
    else
        fail "noctalia is not in PATH"
    fi

    # --- 1. template descriptor ------------------------------------------
    local descriptor="$DEST_DIR/template.toml"
    if [ -r "$descriptor" ]; then
        ok "descriptor: $descriptor"
        if grep -qF "$MARKER" "$descriptor"; then
            ok "descriptor is owned by $PROJECT_NAME"
        else
            warn "descriptor does not carry the $PROJECT_NAME marker"
        fi
        grep -q "^\[catalog\.$TEMPLATE_ID\]" "$descriptor" \
            && ok "catalog entry: $TEMPLATE_ID" \
            || fail "descriptor has no [catalog.$TEMPLATE_ID] section"
        if grep -q "^\[templates\.$TEMPLATE_ID\]" "$descriptor"; then
            ok "template entry: $TEMPLATE_ID"
        else
            fail "descriptor has no [templates.$TEMPLATE_ID] section"
        fi
    else
        fail "template not installed: $descriptor (run scripts/install.sh)"
    fi

    # --- 2. the stylesheet template --------------------------------------
    local template="$DEST_DIR/vivaldi.css"
    if [ -r "$template" ]; then
        ok "template  : $template"
        grep -q '{{' "$template" \
            && ok "template contains template expressions" \
            || fail "template has no {{ ... }} expressions - wrong file?"
    elif [ -r "$REPO_ROOT/templates/vivaldi.css" ]; then
        fail "template not installed: $template (run scripts/install.sh)"
    else
        fail "template not found: $template"
    fi

    # --- 3. cache file ----------------------------------------------------
    if [ -r "$DEST_DIR/.noctalia-cache.json" ]; then
        ok "cache     : $DEST_DIR/.noctalia-cache.json"
    else
        warn "no .noctalia-cache.json - Noctalia may try to re-download the template"
    fi

    # --- 4. generated stylesheet -----------------------------------------
    if [ -z "$OUTPUT_DIR" ]; then
        OUTPUT_DIR=$(css_dir_from_descriptor || true)
        [ -n "$OUTPUT_DIR" ] || OUTPUT_DIR="$CSS_DIR_DEFAULT"
    fi
    OUTPUT_DIR=$(expand_xdg_token "${OUTPUT_DIR%/}")
    local css="$OUTPUT_DIR/$CSS_FILE_NAME"

    if [ -r "$css" ]; then
        ok "css       : $css"
        grep -qF "noctalia-vivaldi:generated" "$css" \
            && ok "css carries the generated marker" \
            || fail "css has no generated marker - is it our file?"
        if grep -q '{{' "$css"; then
            fail "css still contains {{ ... }} - the template was copied, not rendered"
        else
            ok "css is rendered (no template expressions left)"
        fi
        python3 - "$css" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()


def var(name):
    match = re.search(rf"--{name}:\s*(var\([^)]*\)|[^;]+);", text)
    return match.group(1).strip() if match else "?"


def rule(selector, prop):
    """Value of `prop` in the first rule whose selector is exactly `selector`."""
    match = re.search(
        rf"^{re.escape(selector)} \{{[^}}]*?{prop}:\s*([^;]+);", text, re.M | re.S
    )
    return match.group(1).strip() if match else "?"


print(f"      mode        : {var('noctalia-mode')}")
print(f"      surface/bg  : {var('noctalia-bg')}")
print(f"      strip bar   : {var('colorTabBar')}")
print(f"      active tab  : {rule('#browser .tab.active', 'background-color')}")
print(f"      tab hover   : {rule('#browser .tab:not(.active):hover', 'background-color')}")
print(f"      hover role  : {var('noctalia-hover')}")
print(f"      accent      : {var('noctalia-accent')}")
PY
    else
        fail "generated css not found: $css"
        fail "  enable the template in Noctalia (Settings -> Templates) or run:"
        fail "  noctalia msg templates-apply"
    fi

    # --- 5. is the template enabled in Noctalia? --------------------------
    if [ -r "$SETTINGS_FILE" ]; then
        if python3 - "$SETTINGS_FILE" "$TEMPLATE_ID" <<'PY'
import sys, tomllib

with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)
ids = data.get("theme", {}).get("templates", {}).get("community_ids", [])
raise SystemExit(0 if sys.argv[2] in ids else 1)
PY
        then
            ok "noctalia  : '$TEMPLATE_ID' is enabled"
        else
            warn "'$TEMPLATE_ID' is not in theme.templates.community_ids -"
            warn "  enable it in Settings -> Templates (Noctalia)"
        fi
    else
        warn "no $SETTINGS_FILE - cannot tell whether the template is enabled"
    fi

    # --- 6. Vivaldi side (read-only) --------------------------------------
    if [ "$CHECK_VIVALDI" -eq 1 ]; then
        local configured
        configured=$(vivaldi_css_dir)
        if [ -z "$configured" ]; then
            warn "Vivaldi has no Custom UI Modifications directory yet:"
            warn "  vivaldi://experiments/ -> enable 'VivaldiCssMods'"
            warn "  Settings -> Appearance -> Custom UI Modifications -> $OUTPUT_DIR"
        elif [ "$configured" = "$OUTPUT_DIR" ]; then
            ok "vivaldi   : Custom UI Modifications -> $configured"
        else
            warn "Vivaldi reads custom CSS from $configured, not $OUTPUT_DIR"
        fi
    fi

    printf '\n'
    if [ "$FAILURES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        printf 'all checks passed (%s)\n' "$PROJECT_NAME"
        return 0
    fi
    printf '%d failure(s), %d warning(s)\n' "$FAILURES" "$WARNINGS"
    [ "$FAILURES" -eq 0 ]
}

main "$@"
