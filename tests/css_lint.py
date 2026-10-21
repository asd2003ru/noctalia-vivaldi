#!/usr/bin/env python3
"""Lint a noctalia-vivaldi generated stylesheet.

Exit code 0 = no errors. Warnings do not change the exit code.
Prints one line per check: "ok <msg>", "warn <msg>" or "FAIL <msg>".
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

TEMPLATE_LEFTOVERS = ("{{", "}}", "<*", "*>")

# Properties that would change Vivaldi's UI geometry/layout. The template is
# only allowed to define colours (custom properties) plus a handful of
# colour-only declarations.
GEOMETRY_PROPS = re.compile(
    r"^(width|height|min-width|max-width|min-height|max-height|padding|padding-\w+|"
    r"margin|margin-\w+|gap|row-gap|column-gap|font-size|line-height|border-radius|"
    r"border-\w+-radius|inset|top|right|bottom|left|display|position|z-index|order|"
    r"flex|flex-\w+|grid|grid-\w+|overflow|overflow-\w+|transform|font-family)$"
)

COLOR_VALUE = re.compile(
    r"^(?:"
    r"#[0-9a-fA-F]{3}|#[0-9a-fA-F]{4}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{8}"
    r"|rgba?\([^()]*\)"
    r"|hsla?\([^()]*\)"
    r"|color-mix\(.*\)"
    r"|var\(--[A-Za-z0-9_-]+\)"
    r"|[a-zA-Z]+"          # named colours, transparent, currentColor, ...
    r")$"
)

VARS_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "vivaldi-color-vars.txt"

NON_COLOR_CUSTOM_PROPS = {"--noctalia-mode", "--isDarkTheme", "--radius", "--radiusRounded"}


def is_color_property(name: str) -> bool:
    """Custom properties whose value has to be a colour."""
    if name in NON_COLOR_CUSTOM_PROPS:
        return False
    return (
        name.startswith("--color")
        or name.startswith("--noctalia-")
        or name.startswith("--browserBackground")
    )


def known_vivaldi_vars() -> set[str]:
    if not VARS_FIXTURE.is_file():
        return set()
    return {
        line.strip()
        for line in VARS_FIXTURE.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("FAIL usage: css_lint.py <file.css>")
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"FAIL not a file: {path}")
        return 2
    css = path.read_text(encoding="utf-8", errors="replace")
    # The marker lives in a comment, so keep the raw text for that check and
    # strip comments before analysing declarations.
    body_css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)

    errors: list[str] = []
    warnings: list[str] = []
    oks: list[str] = []

    # 1. template leftovers
    leftovers = [tok for tok in TEMPLATE_LEFTOVERS if tok in body_css]
    if leftovers:
        errors.append(f"unrendered template syntax remains: {', '.join(leftovers)}")
    else:
        oks.append("no unrendered {{ ... }} / <* ... *> constructs")

    # 2. marker
    if "noctalia-vivaldi:generated" in css:
        oks.append("file carries the generated marker")
    else:
        errors.append("missing 'noctalia-vivaldi:generated' marker")

    # 3. mode
    mode_match = re.search(r"--noctalia-mode:\s*([A-Za-z]+)", body_css)
    if mode_match and mode_match.group(1) in {"dark", "light"}:
        oks.append(f"rendered variant: {mode_match.group(1)}")
    else:
        errors.append("--noctalia-mode is missing or not dark/light")

    # 4. braces
    if body_css.count("{") == body_css.count("}"):
        oks.append("balanced braces")
    else:
        errors.append(f"unbalanced braces: {body_css.count('{')} '{{' vs {body_css.count('}')} '}}'")

    # 5. declarations
    defined: set[str] = set()
    referenced: set[str] = set()
    known = known_vivaldi_vars()
    unknown_vivaldi: list[str] = []
    geometry: list[str] = []
    bad_colors: list[str] = []
    missing_important: list[str] = []

    for decl in re.finditer(r"(--[A-Za-z0-9_-]+)\s*:\s*([^;{}]+);", body_css):
        name, raw_value = decl.group(1), decl.group(2).strip()
        defined.add(name)
        referenced.update(re.findall(r"var\((--[A-Za-z0-9_-]+)\)", raw_value))

        body = re.sub(r"\s*!important\s*$", "", raw_value)
        if not body:
            bad_colors.append(f"{name} has an empty value")
            continue
        if not is_color_property(name):
            continue
        if not COLOR_VALUE.match(body):
            bad_colors.append(f"{name}: {body}")

        if name.startswith("--color") and not raw_value.endswith("!important"):
            missing_important.append(name)
        if name.startswith("--color") and known and name not in known:
            unknown_vivaldi.append(name)

    for prop in re.finditer(r"(?<![\w-])([a-z-]+)\s*:\s*[^;{}]+;", body_css):
        candidate = prop.group(1)
        if candidate.startswith("--") or candidate in {"background-color", "color", "border-color", "fill", "fill-opacity", "background"}:
            continue
        if GEOMETRY_PROPS.match(candidate):
            geometry.append(candidate)

    if bad_colors:
        errors.append("invalid or empty colour values: " + "; ".join(bad_colors[:10]))
    else:
        oks.append("all custom-property colour values are syntactically valid")

    if missing_important:
        errors.append("--color* declarations without !important: " + ", ".join(sorted(set(missing_important))[:10]))
    else:
        oks.append("every --color* declaration is !important")

    if geometry:
        errors.append("layout/geometry properties found: " + ", ".join(sorted(set(geometry))))
    else:
        oks.append("no geometry properties (colours only)")

    if unknown_vivaldi:
        warnings.append("--color* names not found in the Vivaldi 8.2 variable list: " + ", ".join(sorted(set(unknown_vivaldi))))
    elif known:
        oks.append(f"all --color* names exist in Vivaldi ({len(known)} known variables)")

    undefined = sorted(v for v in referenced - defined if v not in known)
    if undefined:
        if any(v.startswith("--noctalia") for v in undefined):
            errors.append("undefined --noctalia-* variables: " + ", ".join(undefined))
        else:
            warnings.append("references to variables not defined in this file: " + ", ".join(undefined))
    else:
        oks.append("every var(...) reference resolves")

    for line in oks:
        print(f"ok {line}")
    for line in warnings:
        print(f"warn {line}")
    for line in errors:
        print(f"FAIL {line}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
