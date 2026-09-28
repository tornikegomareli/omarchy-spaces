<h1 align="center">Spaces</h1>

<h3 align="center">See what runs on every workspace.</h3>

<p align="center">
  <img src=".github/assets/film-apps.png" width="100%" alt="The Omarchy bar with Spaces: five workspaces, each showing the app icons open on it" />
</p>

Spaces is a workspace switcher for the [Omarchy](https://omarchy.org) bar. Each workspace shows the icons of the apps open on it. The active one slides open, and the focused window is highlighted.

## Peek before you jump

Hover another workspace to see it live, laid out the way it is on screen. Click a window in the preview to jump to it.

Previews follow the monitor's orientation, including portrait displays, and shrink to fit the available screen space while keeping the full workspace visible. The size setting controls the longest side, so portrait and landscape previews have a comparable size.

<p align="center">
  <img src=".github/assets/film-preview.png" width="100%" alt="Hovering workspace 2 opens a live preview with omarchy.org and Neovim side by side" />
</p>

## Know when your agent needs you

Terminals running Claude Code get a badge: a spinner while the agent works, a pulsing `!` when it needs your input, and a check mark when it is done. A workspace with an agent waiting on you pulses too.

<p align="center">
  <img src=".github/assets/film-agent.png" width="100%" alt="A terminal icon on workspace 4 with an orange exclamation badge: the agent needs input" />
</p>

To turn it on, add these hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/tornikegomareli.spaces/hooks/claude-hook working", "async": true }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/tornikegomareli.spaces/hooks/claude-hook working", "async": true }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/tornikegomareli.spaces/hooks/claude-hook waiting", "async": true }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/tornikegomareli.spaces/hooks/claude-hook done", "async": true }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/tornikegomareli.spaces/hooks/claude-hook end", "async": true }] }]
  }
}
```

Other agents can report the same way: `omarchy-shell tornikegomareli.spaces agent <session> <working|waiting|done|end> <pids>`, where `<pids>` lists the agent's process and its parents, comma-separated.

## Install

```sh
omarchy plugin add https://github.com/tornikegomareli/omarchy-spaces.git --enable
omarchy plugin disable omarchy.workspaces   # optional: replace the built-in switcher
```

Requirements:

- Omarchy 4 with the Quickshell bar (Hyprland 0.56 or newer)
- `jq` for the agent hook (installed with Omarchy)
- Claude Code, only for agent status

Works with the bar on any edge of the screen. Tested on a single monitor.

To update, then load the new code:

```sh
omarchy plugin update tornikegomareli.spaces
omarchy restart shell
```

## Remove

```sh
omarchy plugin remove tornikegomareli.spaces
omarchy plugin enable omarchy.workspaces   # bring back the built-in switcher
```

If you added the agent hooks or the settings key below, delete those lines from `~/.claude/settings.json` and `~/.config/hypr/bindings.lua`.

## Using it

- Click a workspace to go there. Click an icon to focus that window.
- Scroll over the widget to move between workspaces.
- Hover an icon to see the window title.
- Hover another workspace to preview it. Click a window in the preview to focus it.
- Right-click the widget, or click the gear that shows on hover, to open settings.

## Settings

<img src=".github/assets/settings.png" width="330" align="right" alt="Spaces settings panel" />

Choose when icons show (always, active, on hover, or never), icon style and size, grouping by app, previews, agent status, the active workspace style, density, and more. Settings are saved to `~/.config/omarchy/shell.json`.

To open settings with a key, add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + ALT + S", "Spaces settings", "omarchy-shell tornikegomareli.spaces toggle")
```

To preview a workspace from a key or script, without hovering:

```sh
omarchy-shell tornikegomareli.spaces peek 3
```

Settings can also be set from a script:

```sh
omarchy bar set tornikegomareli.spaces showApps all
```

<br clear="right" />

## Development

From a clone of this repository, link it into Omarchy and run the tests:

```sh
ln -sfn "$PWD" ~/.config/omarchy/plugins/tornikegomareli.spaces
omarchy plugin enable tornikegomareli.spaces
node tests/model.test.js
```

After code changes, run `omarchy restart shell`.

## License

[MIT License](LICENSE).
