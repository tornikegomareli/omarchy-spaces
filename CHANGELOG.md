# Changelog

## 1.8.0

- Hovering an app icon highlights all its windows in the preview and brings
  its floating thumbnail to the front. It stays in front while you move into
  the preview, so you can click it. Clicking an app icon closes the preview
  (#58, from #35, @rugobal)
- Previews → Preview current workspace, off by default, previews the
  workspace you are on too (#58, @rugobal)
- Behaviour → Keep an open scratchpad, off by default: while a scratchpad has
  focus, clicking a window switches the workspace under it and keeps the
  scratchpad open. Scratchpad windows also stay out of the previous-window
  history (#59, @rugobal)
- Previous window: switching to a window on another workspace no longer makes
  that workspace's last window "previous", so a second click goes back to
  where you came from (#57, @rugobal)
- Previous window: a grouped app icon cycles its windows, as in Cycles
  windows. Previous window applies to icons with one window
  (#56, @rugobal)
- Clicking a window focuses it in one Hyprland call and raises it only if it
  floats

## 1.7.0

- Clicking an app icon or a preview thumbnail raises the window above other
  floating windows. Before, a window behind a maximized floating one got
  focus but stayed hidden (from #35, @rugobal; tested by @felipecpaiva)
- Agent status for OpenCode 2.x: its server plugins run outside your
  terminal, so a TUI plugin, `hooks/opencode-tui.js`, reports instead. See the
  README for the two links. OpenCode 1.4 and newer 1.x keep the existing
  plugin (#26, @imranZERO)
- Pill shape: Appearance → Pill shape → Oval gives the pills round ends
  whatever your window rounding (#43, @DukeOfContention)
- Focused app: Appearance → Focused app → Dot drops the tiles behind app
  icons and marks the focused app with a small dot under it, like a dock
  (#46, @DukeOfContention)
- Behaviour → Move pointer to clicked window: turn it off and clicking an app
  icon or thumbnail leaves the pointer where you clicked (#38, @alanhogan)
- Opt-in pill border, and opt-in Chromium tab favicons for plain Chromium
  windows, read from Chromium's own history and favicon files
  (#29, @JuanSombrero23)
- Custom workspace labels sit in two collapsible groups, with the ten
  workspaces in a grid instead of a long scrolling list (#53, @pwn27sbx)
- App icons follow your icon theme. Before, any SVG in any installed theme
  won over the theme's own icon, so Yaru showed hicolor's Nautilus
  (#44, @DukeOfContention)
- Previews show floating windows where they are now, not where they were
  before you moved or resized them (#52, @felipecpaiva)
- The focused title shows the window title for apps with no desktop entry,
  such as Omarchy's terminal apps, instead of their class, `TUI.tile`
  (#51, @felipecpaiva)
- Per-monitor workspaces: a workspace switch on a monitor without focus
  shows on its own bar, and a monitor switched off and on again gets its own
  workspaces back instead of every monitor's (#42, @G-Pappas;
  #48, @VulpesZerda27)

## 1.6.0

- Agent logos: a terminal running Claude Code, Codex or Grok shows that
  agent's logo instead of the terminal icon, told apart by the title each
  agent sets. Only terminal windows are checked, and Settings → App icons →
  Agent icons turns it off (#27, @tcballard)
- Pill height and padding: set under Appearance → Pill size, with a preview of
  the bar as you change them. Both stay automatic until you set them, so
  nothing changes by default (#33, @pwn27sbx)
- Clicking the focused app icon can return to the window you used before it,
  even on another workspace: Behaviour → Clicking the focused app icon →
  Previous window. Cycling a grouped app's windows stays the default
  (#34, @rugobal)
- Web apps that share a host, such as iCloud Reminders and Numbers, each show
  their own icon instead of whichever was installed first (#32, @gjouret)

## 1.5.0

- Custom workspace labels: pick Custom under Appearance → Workspace label,
  then give each workspace its own text, emoji or Nerd Font glyph, and
  optionally one for whichever workspace is focused. An empty field keeps the
  number, and holding Super still shows numbers (#28, @TMartinPPC)
- Omarchy 4.5 gives every monitor its own workspaces 1–10. With "Only this
  monitor's workspaces" on, each bar numbers its monitor's workspaces 1–10,
  keeps that monitor's empty slots, and clicking one goes to it on that
  monitor. Workspaces visiting from an unplugged monitor follow with their
  global numbers. Older Omarchy versions are unchanged (#2, #30, @pomartel)
- A newly installed app, such as an Omarchy web app, shows its icon right
  away instead of a letter until the shell restarts (#31, @dev-learner-supreme)

## 1.4.0

- Show workspace numbers while holding Super: an opt-in setting under
  Workspaces for people who hide numbers with the None or Glyph label style.
  It needs two Hyprland bindings, listed in the README, and every other Super
  shortcut works as before (#16, #21, @mshareef-git)
- Pushing the pointer to the screen edge still hovers and selects the
  workspace under it: each workspace's target now spans the full bar
  thickness, while the pill looks the same (#25, @afrojun)
- Windows the shell itself hosts, such as Omamail, show their own app icon
  instead of the shell's, and each keeps its own icon instead of collapsing
  into one (#23, @FarzadHayat)

## 1.3.0

- Agent status for Cursor: register `hooks/cursor-reporter.js` in
  `~/.cursor/hooks.json` and Cursor windows, or terminals running
  `cursor-agent`, get a spinner while the agent works and a check mark when it
  stops. Cursor has no hook for "needs your input", so there is no `!` badge.
  Needs Node.js (#5, @FarzadHayat)
- An agent badge stays on its own window when several windows share one
  process, as Ghostty does in single-instance mode. Before, every window of
  that terminal showed it (#22, @FarzadHayat)
- Long titles no longer cut an emoji or an accented letter in half, and
  Korean, Japanese and Chinese characters count double toward the title
  length. The placeholder letter keeps a whole emoji or syllable too
  (#17, @seunghan91)
- Sharper icons at whole-number scales such as 1 and 2. Fractional scales
  such as 1.25 are unchanged (#19, @imranZERO)
- Much lower CPU use while an agent works: the spinner, the waiting pulse and
  the urgent glow no longer redraw the whole bar every frame. One working
  agent took the shell from about 1% to 19% CPU; it now steps a few times a
  second instead

## 1.2.0

- Agent status for omp (oh-my-pi): add `hooks/omp-extension.js` to your omp
  config and its terminals get the same badges as Claude Code. An approval
  prompt waits 1.5s before showing `!`, so a quick answer never flashes
  (#14, @a-lang)
- A "Pill background" setting under Appearance hides the faint fill behind
  occupied and hovered workspaces. The active workspace keeps its highlight
  (#1, @tseluka)
- A workspace that shows a single icon no longer highlights it as focused
  (#12, #13, @tseluka)
- Sharper app icons, and an app with no icon shows the first letter of its own
  name instead of a shared prefix, so `org.omarchy.herdr` reads "H", not "O"
  (#10, @Natetgmaxwell)
- Security: window titles in the bar and in previews render as plain text, so
  a title with markup can no longer load remote images in the shell

## 1.1.0

- Settings are organised into six pages: App icons, Windows, Appearance,
  Workspaces, Previews, and Behaviour. They work from the keyboard, the
  focused title length can be set, and resetting asks first (#8, @tcballard)
- The settings gear is off by default. Right-click the widget to open
  settings, or turn the gear on under Appearance; it now sits in a fixed slot
  before the workspaces (#8)
- Agent status for OpenCode: link `hooks/opencode-plugin.js` into OpenCode and
  its terminals get the same badges as Claude Code. A permission prompt waits
  1.5s before showing `!`, so `--auto` never flashes (#4, @FarzadHayat)
- Agent status: a `working` or `waiting` badge left behind by a crashed agent
  clears within a minute (#3, @FarzadHayat)
- Previews fit portrait and rotated monitors (#6, @VulpesZerda27)
- Fixed: changing the animation speed, or turning animations off and on, hid
  every workspace pill until the shell restarted (#9, reported by @movshuri,
  fix by @Coding-Sparrow)

## 1.0.0

First stable release, ready for the Omarchy plugin marketplace.

- The plugin ID is now `tornikegomareli.spaces`, matching the repository owner.
  If you installed an earlier version, remove `insanearts.spaces`, add the plugin
  again, and update the hook paths in `~/.claude/settings.json`.
- README: screenshots from the product film, requirements, and update and
  removal instructions
- Marketplace preview image
- Verified with the bar on the top, bottom, left and right edges

## 0.3.0

- Agent status: terminals running Claude Code show a spinner while the agent
  works, a pulsing `!` when it needs input, and a check mark when it is done.
  Workspaces with a waiting agent pulse
- `hooks/claude-hook` reports agent state; see the README for setup
- Setting to turn agent status off

## 0.2.0

- Live workspace previews: hover another workspace to see a miniature of it,
  with each window where it really is. Click a window to jump to it
- The preview slides between workspaces as you move along the bar
- Hovering an app icon highlights its window in the preview
- `peek` command to open a preview from a keybinding:
  `omarchy-shell insanearts.spaces peek 3`
- Settings: turn previews on or off, preview size, live video or still frame
- Icons for apps with reverse-DNS ids, such as `dev.example.tool`
- Fix: workspaces could stay half faded after appearing

## 0.1.0

First release.

- Workspace pills that show the icons of the apps open on each workspace
- The active workspace slides open; the focused window is highlighted
- Click a workspace or an icon to focus it; scroll to switch workspaces
- Settings panel: when icons show, icon style and size, grouping by app,
  active style, labels, density, urgent highlights, tooltips, animations
- Icons for Chromium web apps and apps missing from the icon theme
