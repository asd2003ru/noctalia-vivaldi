# noctalia-vivaldi

Vivaldi's browser interface uses the colours of the active
[Noctalia](https://noctalia.dev) palette: tab strip, toolbar, address bar and
bottom bar follow the wallpaper, the light/dark mode and the colour scheme of
Noctalia. Synchronisation is one way (Noctalia → Vivaldi): no background
service, no remote debugging, no changes to the Vivaldi profile.

Verified on: Noctalia 5.3.0 · Vivaldi 8.2.4133.89 · Linux/Niri.

## Installation

```bash
cd ~/Projects/noctalia-vivaldi
scripts/install.sh
```

`install.sh` is idempotent, needs no `sudo` and never writes to the Vivaldi
profile. It registers the stylesheet as the “Vivaldi” entry in Noctalia's
template cache and prints what is still missing. Two one-time steps remain, both
outside this repository:

1. **Enable the template in Noctalia** – *Settings → Templates → “Vivaldi”*
   (or `noctalia msg settings-open templates`).
2. **Point Vivaldi at the generated CSS** – *Settings → Appearance → Custom UI
   Modifications → Select Folder…* → `~/.config/noctalia-vivaldi/css`, then
   restart Vivaldi. If that block does not exist, enable the `VivaldiCssMods`
   flag on `vivaldi://experiments/` first, restart Vivaldi once and repeat this
   step.

Install options: `--output DIR` renders the CSS somewhere else, `--dry-run`
previews, `--help` lists everything.

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
scripts/check.sh        # files, descriptor, rendered CSS, Vivaldi setting
scripts/uninstall.sh    # removes only what this project installed
```

`check.sh` cannot tell whether Vivaldi has *loaded* the CSS – that is only
visible in the browser. `uninstall.sh` keeps the CSS directory when other mods
live in it and never touches Vivaldi's own settings.

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
