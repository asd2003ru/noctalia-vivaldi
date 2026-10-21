# noctalia-vivaldi

Vivaldi's browser interface uses the colours of the active
[Noctalia](https://noctalia.dev) palette: tab strip, toolbar, address bar and
bottom bar follow the wallpaper, the light/dark mode and the colour scheme of
Noctalia. Synchronisation is one way (Noctalia → Vivaldi): no background
service, no remote debugging, no changes to the Vivaldi profile.

Verified on: Noctalia 5.3.0 · Vivaldi 8.2.4133.89 · Linux/Niri.

## Installation

You need Git, Python 3, Noctalia and Vivaldi. Python is used by the installer to
read Vivaldi's settings and write Noctalia's template cache; Noctalia renders
the CSS itself. Python 3.11 or newer also lets the scripts read Noctalia's
settings to report whether the template is enabled. Clone the repository and
run the installer:

```bash
git clone https://github.com/asd2003ru/noctalia-vivaldi.git
cd noctalia-vivaldi
scripts/install.sh
```

`install.sh` is idempotent and needs no `sudo`. It copies the “Vivaldi” template
into Noctalia's template cache, then prints the CSS output directory and the
remaining setup steps. It reads Vivaldi's settings to reuse an existing Custom
UI Modifications directory, but does not change the Vivaldi profile.

Finish setup in this order:

1. **Enable the template in Noctalia:** *Settings → Templates → “Vivaldi”*
   (open it with `noctalia msg settings-open templates`).
2. **Generate the first stylesheet:** run `noctalia msg templates-apply`.
   This creates `noctalia.css` in the output directory printed by the installer.
3. **Select that directory in Vivaldi:** *Settings → Appearance → Custom UI
   Modifications → Select Folder…*. The default is
   `~/.config/noctalia-vivaldi/css`; use the directory printed by the installer
   if it differs. If the Custom UI Modifications setting is missing, enable
   `VivaldiCssMods` at `vivaldi://experiments/`, restart Vivaldi, then select
   the directory. Restart Vivaldi after selecting it.

To choose another output directory, run `scripts/install.sh --output /absolute/path`.
Use `scripts/install.sh --dry-run` to preview installation or `--help` for all
options.

## Recommended settings

* *Settings → Themes → Accent from Page*: **off** – otherwise the active
  website's colour competes with the palette.
* Keep the Vivaldi theme's light/dark state in sync with the Noctalia mode
  (Vivaldi's default OS-based theme schedule does this automatically). Page
  areas without their own background (`about:blank`, the start page) are filled
  with the Vivaldi theme's background, not with the palette.

## Applying changes

* **Palette changes** (new wallpaper, light/dark switch, another colour scheme):
  nothing to do, Noctalia re-renders the stylesheet. An already open window
  keeps its colours, so press `Ctrl+N`; the new window uses the new ones, no
  browser restart.
* **After editing the styling** (`templates/vivaldi.css`): run
  `scripts/install.sh` again, then `noctalia msg templates-apply`.

## Customising

The styling lives in `templates/vivaldi.css`; edit it and run
`scripts/install.sh` (see above). One-off tweaks can also go into an extra
`*.css` file in `~/.config/noctalia-vivaldi/css`, for example `zz-my-tweaks.css`
– Vivaldi loads the files alphabetically, so it wins over the generated
`noctalia.css`.

## Verify / remove

```bash
scripts/check.sh        # inspect the template, rendered CSS and Vivaldi setting
scripts/uninstall.sh    # remove the installed template and generated CSS
```

`check.sh` cannot tell whether Vivaldi has *loaded* the CSS – that is only
visible in the browser. Use `scripts/check.sh --no-vivaldi` if Vivaldi's
preferences are unavailable. `uninstall.sh` keeps the CSS directory when other
mods live in it and never touches Vivaldi's own settings. Disable “Vivaldi” in
Noctalia and clear Vivaldi's Custom UI Modifications setting if you no longer
need them.

## Limitations

* Vivaldi reads the custom UI CSS only when it creates a window: after a palette
  change press `Ctrl+N` (no browser restart needed).
* Web pages are not styled; Vivaldi's own pages (`vivaldi://settings`, …) do
  follow the palette.
* The browser chrome is painted opaque: the Vivaldi theme's background image and
  transparency are switched off, otherwise strips of the previous theme stay
  visible. A `zz-*.css` file can bring the image back:

  ```css
  #browser { background-image: var(--browserBlurredImage, var(--browserBackgroundImage)) !important; }
  ```

* The tab close button keeps Vivaldi's own grey hover.
