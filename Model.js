.pragma library

// Pure helpers for the Spaces widget. Nothing here touches QML
// objects beyond plain property reads, so the logic can be exercised with
// node (see tests/model.test.js).

var DEFAULTS = {
  showIcons: true,            // master switch: app icons visible or hidden
  showApps: "hover",          // "all" | "active" | "hover" (active + hovered) | "hoverOnly"
  persistentWorkspaces: 5,    // workspaces 1..N are always shown
  hideEmpty: false,           // hide empty workspaces, even persistent ones
  perMonitor: false,          // only list workspaces on this bar's monitor
  iconSize: 16,
  maxIcons: 8,                // overflow collapses into a "+N" chip
  groupApps: false,           // one icon per app, with a window count
  dimUnfocused: true,         // dim other windows on the active workspace
  focusedTitle: false,        // show the focused window's title next to its icon
  titleLength: 24,
  activeStyle: "subtle",      // "subtle" | "solid" | "accent"
  pillBackground: true,       // quiet fill behind occupied/hovered pills
  labelStyle: "number",       // "number" | "glyph" | "none"
  animations: true,
  animationSpeed: "normal",   // "slow" | "normal" | "fast"
  scrollSwitch: true,
  iconStyle: "color",         // "color" | "mono"
  urgentHighlight: true,      // pulse workspaces whose windows ask for attention
  middleClickClose: false,    // middle-click an icon closes that window
  tooltips: true,
  density: "normal",          // "compact" | "normal" | "roomy"
  activeClick: "none",        // clicking the active pill: "none" | "previous"
  settingsButton: "never",    // gear button: "hover" | "always" | "never"
  previews: true,             // live preview of a workspace on hover
  previewSize: "medium",      // "small" | "medium" | "large"
  previewLive: true,          // keep previews streaming; false = one frame
  agentStatus: true           // badges for coding agents running in terminals
}

var SHOW_APPS = ["all", "active", "hover", "hoverOnly"]
var ICON_STYLES = ["color", "mono"]
var DENSITIES = ["compact", "normal", "roomy"]
var ACTIVE_CLICKS = ["none", "previous"]
var SETTINGS_BUTTONS = ["hover", "always", "never"]
var PREVIEW_SIZES = ["small", "medium", "large"]
var ACTIVE_STYLES = ["subtle", "solid", "accent"]
var LABEL_STYLES = ["number", "glyph", "none"]
var SPEEDS = ["slow", "normal", "fast"]

function clampInt(value, min, max, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

function oneOf(value, allowed, fallback) {
  return allowed.indexOf(String(value)) !== -1 ? String(value) : fallback
}

function bool(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

// Normalizes a raw shell.json entry into a complete, valid settings object.
function resolveSettings(raw) {
  var s = raw || {}
  var d = DEFAULTS
  return {
    showIcons: bool(s.showIcons, d.showIcons),
    showApps: oneOf(s.showApps, SHOW_APPS, d.showApps),
    persistentWorkspaces: clampInt(s.persistentWorkspaces, 0, 10, d.persistentWorkspaces),
    hideEmpty: bool(s.hideEmpty, d.hideEmpty),
    perMonitor: bool(s.perMonitor, d.perMonitor),
    iconSize: clampInt(s.iconSize, 12, 24, d.iconSize),
    maxIcons: clampInt(s.maxIcons, 1, 20, d.maxIcons),
    groupApps: bool(s.groupApps, d.groupApps),
    dimUnfocused: bool(s.dimUnfocused, d.dimUnfocused),
    focusedTitle: bool(s.focusedTitle, d.focusedTitle),
    titleLength: clampInt(s.titleLength, 8, 60, d.titleLength),
    activeStyle: oneOf(s.activeStyle, ACTIVE_STYLES, d.activeStyle),
    pillBackground: bool(s.pillBackground, d.pillBackground),
    labelStyle: oneOf(s.labelStyle, LABEL_STYLES, d.labelStyle),
    animations: bool(s.animations, d.animations),
    animationSpeed: oneOf(s.animationSpeed, SPEEDS, d.animationSpeed),
    scrollSwitch: bool(s.scrollSwitch, d.scrollSwitch),
    iconStyle: oneOf(s.iconStyle, ICON_STYLES, d.iconStyle),
    urgentHighlight: bool(s.urgentHighlight, d.urgentHighlight),
    middleClickClose: bool(s.middleClickClose, d.middleClickClose),
    tooltips: bool(s.tooltips, d.tooltips),
    density: oneOf(s.density, DENSITIES, d.density),
    activeClick: oneOf(s.activeClick, ACTIVE_CLICKS, d.activeClick),
    settingsButton: oneOf(s.settingsButton, SETTINGS_BUTTONS, d.settingsButton),
    previews: bool(s.previews, d.previews),
    previewSize: oneOf(s.previewSize, PREVIEW_SIZES, d.previewSize),
    previewLive: bool(s.previewLive, d.previewLive),
    agentStatus: bool(s.agentStatus, d.agentStatus)
  }
}

function durationFor(settings, base) {
  if (!settings.animations) return 0
  var factor = settings.animationSpeed === "slow" ? 1.6 : (settings.animationSpeed === "fast" ? 0.55 : 1)
  return Math.round(base * factor)
}

// Whether a workspace pill should reveal its app icons.
function showsApps(settings, occupied, active, hovered) {
  if (!settings.showIcons || !occupied) return false
  switch (settings.showApps) {
  case "all": return true
  case "active": return active
  case "hoverOnly": return hovered
  default: return active || hovered
  }
}

// Spacing between pills and inside them, in unscaled px.
function densityMetrics(density) {
  if (density === "compact") return { gap: 2, pad: 5, iconGap: 1 }
  if (density === "roomy") return { gap: 7, pad: 10, iconGap: 5 }
  return { gap: 4, pad: 7, iconGap: 3 }
}

// Hyprland reports addresses with or without the 0x prefix depending on source.
function normalizeAddress(address) {
  return String(address || "").toLowerCase().replace(/^0x/, "")
}

// Workspace ids to render. `occupied` maps id -> window count for every
// normal (positive id) workspace Hyprland knows about. `activeIds` are
// workspaces that must stay visible even when empty (focused / on-screen).
function workspaceIds(occupied, activeIds, persistent, hideEmpty) {
  var ids = []
  function add(id) {
    if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
  }

  if (!hideEmpty) for (var p = 1; p <= persistent; p++) add(p)
  for (var key in occupied) {
    var id = Number(key)
    if (occupied[key] > 0 || !hideEmpty) add(id)
  }
  for (var a = 0; a < activeIds.length; a++) add(activeIds[a])

  ids.sort(function(l, r) { return l - r })
  return ids
}

// Label text for a workspace pill.
function workspaceLabel(id, focused, style) {
  if (style === "none") return ""
  if (style === "glyph" && focused) return "󱓻"
  return id === 10 ? "0" : String(id)
}

// Stable key identifying "the same app" across windows.
function appKey(appId) {
  return String(appId || "").toLowerCase()
}

// Orders windows the way they sit on screen: left to right, then top to
// bottom. Windows without a known position keep their relative order.
function sortWindows(windows) {
  var indexed = windows.map(function(w, i) { return { w: w, i: i } })
  indexed.sort(function(l, r) {
    var la = l.w.at, ra = r.w.at
    if (la && ra) {
      if (la[0] !== ra[0]) return la[0] - ra[0]
      if (la[1] !== ra[1]) return la[1] - ra[1]
    } else if (la && !ra) {
      return -1
    } else if (!la && ra) {
      return 1
    }
    return l.i - r.i
  })
  return indexed.map(function(x) { return x.w })
}

// Turns a sorted window list into render items.
//   windows: [{ address, appId, title, focused }]
// Returns { items: [{ key, address, appId, title, focused, count }], overflow }
function iconItems(windows, groupApps, maxIcons) {
  var items = []
  if (groupApps) {
    var byApp = {}
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      var k = appKey(w.appId) || w.address
      var existing = byApp[k]
      if (!existing) {
        existing = { key: k, address: w.address, appId: w.appId, title: w.title, focused: w.focused, count: 1, addresses: [w.address] }
        byApp[k] = existing
        items.push(existing)
      } else {
        existing.count++
        existing.addresses.push(w.address)
        if (w.focused) {
          existing.focused = true
          existing.address = w.address
          existing.title = w.title
        }
      }
    }
  } else {
    for (var j = 0; j < windows.length; j++) {
      var x = windows[j]
      items.push({ key: x.address, address: x.address, appId: x.appId, title: x.title, focused: x.focused, count: 1, addresses: [x.address] })
    }
  }

  var overflow = Math.max(0, items.length - maxIcons)
  if (overflow > 0) {
    // Never hide the focused window behind the overflow chip.
    var visible = items.slice(0, maxIcons)
    var focusedIdx = -1
    for (var f = maxIcons; f < items.length; f++) if (items[f].focused) focusedIdx = f
    if (focusedIdx !== -1) visible[visible.length - 1] = items[focusedIdx]
    items = visible
  }
  return { items: items, overflow: overflow }
}

// Splits text into the characters a reader sees, so an emoji or accented
// letter is never cut in half. Qt's JS engine has no Intl.Segmenter, no \p{}
// regexes, and Array.from walks UTF-16 units, so the common joins are done by
// hand: surrogate pairs, combining marks, kana voicing marks, variation
// selectors, skin tones, keycaps, ZWJ sequences, flag pairs and tag sequences.
// Not full UAX #29: Indic spacing marks and conjoining jamo are not joined.
var JOINING = [
  [0x300, 0x36F], [0x1AB0, 0x1AFF], [0x1DC0, 0x1DFF], [0x200D, 0x200D],
  [0x20D0, 0x20FF], [0x3099, 0x309A], [0xFE00, 0xFE0F], [0xFE20, 0xFE2F],
  [0x1F3FB, 0x1F3FF], [0xE0020, 0xE007F], [0xE0100, 0xE01EF]
]

// Every East_Asian_Width=W or F range from Unicode 18.0 EastAsianWidth.txt
// (merged), so CJK, Hangul, kana, fullwidth forms and wide emoji count as
// two columns.
var WIDE = [
  [0x1100, 0x115F], [0x231A, 0x231B], [0x2329, 0x232A], [0x23E9, 0x23EC],
  [0x23F0, 0x23F0], [0x23F3, 0x23F3], [0x25FD, 0x25FE], [0x2614, 0x2615],
  [0x2630, 0x2637], [0x2648, 0x2653], [0x267F, 0x267F], [0x268A, 0x268F],
  [0x2693, 0x2693], [0x26A1, 0x26A1], [0x26AA, 0x26AB], [0x26BD, 0x26BE],
  [0x26C4, 0x26C5], [0x26CE, 0x26CE], [0x26D4, 0x26D4], [0x26EA, 0x26EA],
  [0x26F2, 0x26F3], [0x26F5, 0x26F5], [0x26FA, 0x26FA], [0x26FD, 0x26FD],
  [0x2705, 0x2705], [0x270A, 0x270B], [0x2728, 0x2728], [0x274C, 0x274C],
  [0x274E, 0x274E], [0x2753, 0x2755], [0x2757, 0x2757], [0x2795, 0x2797],
  [0x27B0, 0x27B0], [0x27BF, 0x27BF], [0x2B1B, 0x2B1C], [0x2B50, 0x2B50],
  [0x2B55, 0x2B55], [0x2E80, 0x2E99], [0x2E9B, 0x2EF3], [0x2F00, 0x2FD5],
  [0x2FF0, 0x303E], [0x3041, 0x3096], [0x3099, 0x30FF], [0x3105, 0x312F],
  [0x3131, 0x318E], [0x3190, 0x31E5], [0x31EF, 0x321E], [0x3220, 0x3247],
  [0x3250, 0xA48C], [0xA490, 0xA4C6], [0xA960, 0xA97C], [0xAC00, 0xD7A3],
  [0xF900, 0xFAFF], [0xFE10, 0xFE19], [0xFE30, 0xFE52], [0xFE54, 0xFE66],
  [0xFE68, 0xFE6B], [0xFF01, 0xFF60], [0xFFE0, 0xFFE6], [0x16FE0, 0x16FE4],
  [0x16FF0, 0x16FF6], [0x17000, 0x18CDA], [0x18CFF, 0x18D20],
  [0x18D80, 0x18DF2], [0x18E00, 0x19191], [0x191A0, 0x191D2],
  [0x1AFF0, 0x1AFF3], [0x1AFF5, 0x1AFFB], [0x1AFFD, 0x1AFFE],
  [0x1B000, 0x1B128], [0x1B132, 0x1B132], [0x1B150, 0x1B152],
  [0x1B155, 0x1B155], [0x1B164, 0x1B168], [0x1B170, 0x1B2FB],
  [0x1D300, 0x1D356], [0x1D360, 0x1D376], [0x1F004, 0x1F004],
  [0x1F0CF, 0x1F0CF], [0x1F18E, 0x1F18E], [0x1F191, 0x1F19A],
  [0x1F1AE, 0x1F1AE], [0x1F200, 0x1F202], [0x1F210, 0x1F23B],
  [0x1F240, 0x1F248], [0x1F250, 0x1F251], [0x1F260, 0x1F265],
  [0x1F300, 0x1F320], [0x1F32D, 0x1F335], [0x1F337, 0x1F37C],
  [0x1F37E, 0x1F393], [0x1F3A0, 0x1F3CA], [0x1F3CF, 0x1F3D3],
  [0x1F3E0, 0x1F3F0], [0x1F3F4, 0x1F3F4], [0x1F3F8, 0x1F43E],
  [0x1F440, 0x1F440], [0x1F442, 0x1F4FC], [0x1F4FF, 0x1F53D],
  [0x1F54B, 0x1F54E], [0x1F550, 0x1F567], [0x1F57A, 0x1F57A],
  [0x1F595, 0x1F596], [0x1F5A4, 0x1F5A4], [0x1F5FB, 0x1F64F],
  [0x1F680, 0x1F6C5], [0x1F6CC, 0x1F6CC], [0x1F6D0, 0x1F6D2],
  [0x1F6D5, 0x1F6D9], [0x1F6DC, 0x1F6DF], [0x1F6EB, 0x1F6EC],
  [0x1F6F4, 0x1F6FC], [0x1F7DA, 0x1F7DA], [0x1F7E0, 0x1F7EB],
  [0x1F7F0, 0x1F7F0], [0x1F90C, 0x1F93A], [0x1F93C, 0x1F945],
  [0x1F947, 0x1F9FF], [0x1FA70, 0x1FA7C], [0x1FA80, 0x1FAC6],
  [0x1FAC8, 0x1FAC8], [0x1FACC, 0x1FADD], [0x1FADF, 0x1FAEB],
  [0x1FAEF, 0x1FAFA], [0x20000, 0x2FFFD], [0x30000, 0x3FFFD]
]

function inRanges(cp, ranges) {
  for (var i = 0; i < ranges.length; i++)
    if (cp >= ranges[i][0] && cp <= ranges[i][1]) return true
  return false
}

function isFlag(cp) { return cp >= 0x1F1E6 && cp <= 0x1F1FF }

function graphemes(text) {
  var s = String(text || "")
  var out = []
  var joinNext = false
  var i = 0
  while (i < s.length) {
    var cp = s.codePointAt(i)
    var ch = String.fromCodePoint(cp)
    i += ch.length
    var prev = out.length - 1
    if (prev >= 0 && (joinNext || inRanges(cp, JOINING))) out[prev] += ch
    else if (prev >= 0 && isFlag(cp) && out[prev].length === 2 && isFlag(out[prev].codePointAt(0))) out[prev] += ch
    else out.push(ch)
    joinNext = cp === 0x200D
  }
  return out
}

// Wide characters and emoji take about two Latin columns, so they count
// double against the title length. U+FE0F and a keycap make any base an emoji.
function graphemeWidth(g) {
  var cp = g.codePointAt(0)
  // Regional indicators are East_Asian_Width=N, but a flag pair draws as an
  // emoji two columns wide.
  var wide = inRanges(cp, WIDE) || isFlag(cp) || g.indexOf("\uFE0F") !== -1 || g.indexOf("\u20E3") !== -1
  return wide ? 2 : 1
}

// Same contract as a plain .length/.slice truncate, measured in columns.
function truncate(text, max) {
  var chars = graphemes(text)
  var width = 0
  for (var i = 0; i < chars.length; i++) width += graphemeWidth(chars[i])
  if (!(width > max)) return chars.join("")
  var budget = Math.max(1, max - 1)
  var out = ""
  width = 0
  for (var j = 0; j < chars.length && width + graphemeWidth(chars[j]) <= budget; j++) {
    out += chars[j]
    width += graphemeWidth(chars[j])
  }
  return out + "…"
}

// Title shown next to the focused icon. The app name when
// the app has a single window in the workspace, else the window title.
function focusedLabel(item, appName, maxLength) {
  if (!item || !item.focused) return ""
  var text = item.count > 1 || !appName ? item.title : appName
  return truncate(text, maxLength)
}

// Lookup keys for an app id, most specific first. Reverse-DNS ids such as
// "dev.example.my-tool" often ship a desktop file named after the last part.
function appIdCandidates(appId) {
  var id = String(appId || "")
  if (id === "") return []
  var out = [id]
  function add(v) { if (v && out.indexOf(v) === -1) out.push(v) }
  add(id.toLowerCase())
  var dot = id.lastIndexOf(".")
  if (dot > 0 && dot < id.length - 1) {
    add(id.slice(dot + 1))
    add(id.slice(dot + 1).toLowerCase())
  }
  return out
}

// The letter to stand in for an app with no resolvable icon. Prefers the
// readable tail of a reverse-DNS class, so org.omarchy.herdr reads "H" and not
// "O" along with everything else sharing that prefix.
function fallbackLetter(name, appId) {
  var label = String(name || "")
  var id = String(appId || "")
  if (label === "" || label === id) {
    var parts = id.split(".")
    label = parts.length > 1 ? parts[parts.length - 1] : id
  }
  return (graphemes(label)[0] || "").toUpperCase()
}

// Chromium-family --app windows use classes like
// "chrome-web.whatsapp.com__-Default" or "brave-app.hey.com__-Profile_1".
// Returns the host ("web.whatsapp.com") or "" when the class is not one.
function webAppHost(appId) {
  var m = /^(?:chrome|chromium|brave|msedge|vivaldi|helium|opera)-([^_]+?)(?:__|_).*-(?:Default|Profile_\d+)$/i.exec(String(appId || ""))
  return m ? m[1] : ""
}

// Icon candidates scanned from disk: prefer scalable, then the largest raster.
function iconPathScore(path) {
  var p = String(path || "")
  if (/\.svg$/i.test(p)) return 100000
  var m = /\/(\d+)x\d+\//.exec(p)
  if (m) return Number(m[1])
  return /\/pixmaps\//.test(p) ? 48 : 1
}

function iconNameFromPath(path) {
  var value = String(path || "")
  var slash = value.lastIndexOf("/")
  var file = slash >= 0 ? value.slice(slash + 1) : value
  var dot = file.lastIndexOf(".")
  return dot > 0 ? file.slice(0, dot) : file
}

// Longest side of the workspace miniature, in unscaled px.
function previewWidth(size) {
  if (size === "small") return 260
  if (size === "large") return 520
  return 380
}

// Usable area of a monitor in logical layout coordinates, i.e. without the
// space reserved by bars. `monitor`: { x, y, width, height, scale, transform, reserved }
// where width/height are physical pixels and reserved is [l, t, r, b].
function monitorArea(monitor) {
  if (!monitor || !monitor.width || !monitor.height) return null
  var scale = monitor.scale > 0 ? monitor.scale : 1
  var r = monitor.reserved && monitor.reserved.length === 4 ? monitor.reserved : [0, 0, 0, 0]
  // Hyprland reports the unrotated mode. Odd Wayland transforms (including
  // flipped rotations) swap its axes; positions and reserved are already logical.
  var rotated = (monitor.transform || 0) % 2 === 1
  var w = (rotated ? monitor.height : monitor.width) / scale
  var h = (rotated ? monitor.width : monitor.height) / scale
  return {
    x: (monitor.x || 0) + r[0],
    y: (monitor.y || 0) + r[1],
    width: Math.max(1, w - r[0] - r[2]),
    height: Math.max(1, h - r[1] - r[3])
  }
}

// Fit the entire workspace without stretching it or cropping the lower windows.
function previewDimensions(area, desiredExtent, maxWidth, maxHeight) {
  var ratio = area && area.width > 0 && area.height > 0 ? area.height / area.width : 9 / 16
  var desiredWidth = desiredExtent / Math.max(1, ratio)
  var width = Math.max(1, Math.min(desiredWidth, maxWidth, maxHeight / ratio))
  return { width: width, height: width * ratio }
}

// Places windows inside a width x height miniature of `area`, where they
// really are on screen. Floating windows come last so they draw on top.
// Windows without a known position are laid out in an even grid instead.
//   windows: [{ address, at: [x, y] | null, size: [w, h] | null, floating }]
function previewLayout(windows, area, width, height) {
  var placed = []
  var known = area && windows.length > 0 && windows.every(function(w) { return w.at && w.size })

  if (known) {
    var sx = width / area.width
    var sy = height / area.height
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      var x = (w.at[0] - area.x) * sx
      var y = (w.at[1] - area.y) * sy
      var ww = w.size[0] * sx
      var hh = w.size[1] * sy
      // Clamp into the miniature; windows can hang off the edge.
      var cx = Math.max(0, Math.min(width - 4, x))
      var cy = Math.max(0, Math.min(height - 4, y))
      placed.push({
        address: w.address,
        x: cx, y: cy,
        width: Math.max(4, Math.min(width - cx, ww - (cx - x))),
        height: Math.max(4, Math.min(height - cy, hh - (cy - y))),
        floating: !!w.floating
      })
    }
  } else {
    var n = windows.length
    var cols = Math.max(1, Math.ceil(Math.sqrt(n)))
    var rows = Math.max(1, Math.ceil(n / cols))
    var gap = 4
    var cw = (width - gap * (cols - 1)) / cols
    var ch = (height - gap * (rows - 1)) / rows
    for (var j = 0; j < n; j++) {
      placed.push({
        address: windows[j].address,
        x: (j % cols) * (cw + gap), y: Math.floor(j / cols) * (ch + gap),
        width: cw, height: ch,
        floating: false
      })
    }
  }

  placed.sort(function(l, r) { return (l.floating ? 1 : 0) - (r.floating ? 1 : 0) })
  return placed
}

// Maps window PIDs to agent states. `agents`: { session: { state, pids } }
// where pids run from the agent up to init. The nearest ancestor that is a
// window owns the agent, since terminals can be nested in other terminals.
// When several agents share a window, "waiting" beats "working" beats "done".
var AGENT_RANK = { waiting: 3, working: 2, done: 1 }

function agentStates(agents, windowPids) {
  var out = {}
  for (var session in agents) {
    var agent = agents[session]
    var rank = AGENT_RANK[agent.state] || 0
    if (!rank) continue
    for (var i = 0; i < agent.pids.length; i++) {
      var pid = agent.pids[i]
      if (!windowPids[pid]) continue
      if (!out[pid] || AGENT_RANK[out[pid]] < rank) out[pid] = agent.state
      break
    }
  }
  return out
}

function parsePids(csv) {
  return String(csv || "").split(",").map(function(v) { return Number(v) }).filter(function(n) { return n > 1 })
}

// Only these reporter states can produce a badge. Anything else is rejected at
// the IPC boundary. "end" is handled separately: it deletes the session.
var AGENT_REPORT_STATES = { working: true, waiting: true, done: true, idle: true }
var AGENT_LIVE_STATES = { working: true, waiting: true }

function normalizeAgentState(state) {
  var value = String(state || "")
  return AGENT_REPORT_STATES[value] ? value : ""
}

// The first PID in a report is the agent process itself; the rest are its
// ancestors. Collect one probe PID per live session.
function agentProcessIds(agents) {
  var out = []
  for (var session in agents) {
    var agent = agents[session]
    if (!agent || !AGENT_LIVE_STATES[agent.state]) continue
    var pid = Number(agent.pids && agent.pids[0])
    if (!isFinite(pid) || Math.floor(pid) !== pid || pid <= 1) continue
    if (out.indexOf(pid) === -1) out.push(pid)
  }
  out.sort(function(a, b) { return a - b })
  return out
}

// Drop live claims whose agent process is gone. Finished and malformed entries
// are preserved: this is crash cleanup, not state validation.
function pruneDeadAgents(agents, alivePids) {
  var alive = {}
  var list = alivePids || []
  for (var i = 0; i < list.length; i++) alive[String(Number(list[i]))] = true

  var pruned = false
  var out = {}
  for (var session in agents) {
    var agent = agents[session]
    var pid = Number(agent && agent.pids && agent.pids[0])
    if (agent && AGENT_LIVE_STATES[agent.state] && pid > 1 && !alive[String(pid)]) {
      pruned = true
      continue
    }
    out[session] = agent
  }
  return pruned ? out : agents
}

// Next workspace id when scrolling; wraps around.
function stepWorkspace(ids, current, delta) {
  if (!ids.length) return current
  var idx = ids.indexOf(current)
  if (idx === -1) return ids[0]
  var next = (idx + (delta > 0 ? 1 : -1) + ids.length) % ids.length
  return ids[next]
}

// Merges a settings delta into an entry for shell.json.
function mergedEntry(moduleName, current, delta) {
  var entry = { id: moduleName }
  for (var k in current) if (k !== "id") entry[k] = current[k]
  for (var d in delta) entry[d] = delta[d]
  return entry
}

// node / CommonJS export for tests; ignored by QML.
if (typeof module !== "undefined") {
  module.exports = {
    DEFAULTS: DEFAULTS, resolveSettings: resolveSettings, showsApps: showsApps,
    densityMetrics: densityMetrics, normalizeAddress: normalizeAddress,
    agentStates: agentStates, parsePids: parsePids, normalizeAgentState: normalizeAgentState,
    agentProcessIds: agentProcessIds, pruneDeadAgents: pruneDeadAgents,
    previewWidth: previewWidth, previewDimensions: previewDimensions, monitorArea: monitorArea, previewLayout: previewLayout, durationFor: durationFor,
    workspaceIds: workspaceIds, workspaceLabel: workspaceLabel, appKey: appKey,
    sortWindows: sortWindows, iconItems: iconItems, truncate: truncate,
    focusedLabel: focusedLabel, webAppHost: webAppHost, appIdCandidates: appIdCandidates, iconPathScore: iconPathScore,
    iconNameFromPath: iconNameFromPath, stepWorkspace: stepWorkspace, mergedEntry: mergedEntry,
    fallbackLetter: fallbackLetter
  }
}
