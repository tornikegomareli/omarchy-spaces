// Run: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const mod = { exports: {} }
new Function("module", src)(mod)
const M = mod.exports

let failed = 0
function test(name, fn) {
  try { fn(); console.log("ok   " + name) } catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message) }
}

test("resolveSettings fills defaults and clamps", () => {
  const s = M.resolveSettings({ iconSize: 99, showApps: "bogus", persistentWorkspaces: -3, groupApps: "yes" })
  assert.strictEqual(s.iconSize, 24)
  assert.strictEqual(s.showApps, "hover")
  assert.strictEqual(s.persistentWorkspaces, 0)
  assert.strictEqual(s.groupApps, false)
})

test("focused icon click settings preserve cycling unless previous is selected", () => {
  assert.strictEqual(M.resolveSettings({}).activeIconClick, "cycle")
  assert.strictEqual(M.resolveSettings({activeIconClick: "previous"}).activeIconClick, "previous")
  assert.strictEqual(M.resolveSettings({activeIconClick: "invalid"}).activeIconClick, "cycle")
})

test("focus history ignores shell layers, removes closed windows and normalizes addresses", () => {
  let history = M.rememberWindowFocus([], "0xA", ["a", "b"])
  history = M.rememberWindowFocus(history, "0xB", ["a", "b"])
  assert.deepStrictEqual(history, ["b", "a"])
  assert.deepStrictEqual(M.rememberWindowFocus(history, "", []), history)
  assert.deepStrictEqual(M.rememberWindowFocus(history, "0xb", ["a", "b"]), history)
  assert.deepStrictEqual(M.rememberWindowFocus(history, "c", ["b", "c"]), ["c", "b"])
})

test("repeated icon clicks toggle back to the previous window", () => {
  const open = ["a", "b", "c"]
  const icon = {address: "b", addresses: ["b"], focused: false}
  let history = M.rememberWindowFocus([], "a", open)
  assert.strictEqual(M.iconClickTarget(icon, "previous", history, open), "b")
  history = M.rememberWindowFocus(history, "b", open)
  icon.focused = true
  assert.strictEqual(M.iconClickTarget(icon, "previous", history, open), "a")
  history = M.rememberWindowFocus(history, "a", open)
  icon.focused = false
  assert.strictEqual(M.iconClickTarget(icon, "previous", history, open), "b")
})

test("focused icon skips closed history and stays put without another window", () => {
  const icon = {address: "b", addresses: ["b"], focused: true}
  assert.strictEqual(M.iconClickTarget(icon, "previous", ["b", "a", "c"], ["b", "c"]), "c")
  assert.strictEqual(M.iconClickTarget(icon, "previous", ["b", "a"], ["b"]), "b")
  assert.strictEqual(M.iconClickTarget(icon, "previous", [], ["b"]), "b")
})

test("previous window mode takes precedence over grouped cycling", () => {
  const icon = {address: "b", addresses: ["b", "c"], focused: true}
  assert.strictEqual(M.iconClickTarget(icon, "previous", ["b", "a"], ["a", "b", "c"]), "a")
  assert.strictEqual(M.iconClickTarget(icon, "cycle", ["b", "a"], ["a", "b", "c"]), "c")
  icon.address = "c"
  assert.strictEqual(M.iconClickTarget(icon, "cycle", [], ["b", "c"]), "b")
})

test("workspaceIds keeps persistent, adds occupied and active, sorted", () => {
  assert.deepStrictEqual(M.workspaceIds({ 7: 2, 2: 0 }, [9], 3, false), [1, 2, 3, 7, 9])
})

test("workspaceIds hideEmpty keeps only occupied and active", () => {
  assert.deepStrictEqual(M.workspaceIds({ 1: 0, 4: 1 }, [2], 5, true), [2, 4])
})

test("workspaceLabel", () => {
  assert.strictEqual(M.workspaceLabel(10, false, "number"), "0")
  assert.strictEqual(M.workspaceLabel(3, true, "none"), "")
  assert.notStrictEqual(M.workspaceLabel(3, true, "glyph"), "3")
  assert.strictEqual(M.workspaceLabel(3, false, "glyph"), "3")
})

test("sortWindows orders by x then y, unknown last", () => {
  const w = [{ id: "a", at: [500, 0] }, { id: "b" }, { id: "c", at: [10, 300] }, { id: "d", at: [10, 5] }]
  assert.deepStrictEqual(M.sortWindows(w).map(x => x.id), ["d", "c", "a", "b"])
})

test("minimizing keeps the workspace icon and the exact floating preview rectangle", () => {
  const floating = { address: "0xA", appId: "editor", title: "Draft", workspaceId: 2,
    workspaceName: "2", at: [320, 140], size: [900, 640], floating: true, monitor: 0 }
  const neighbor = { address: "b", appId: "browser", workspaceId: 2,
    workspaceName: "2", at: [100, 40], size: [800, 500], floating: true, monitor: 0 }
  const area = {x: 0, y: 0, width: 2400, height: 1320}
  const visible = M.windowPlacements([floating, neighbor], {})
  const before = M.sortWindows(Object.values(visible))
  let hidden = M.windowPlacements([{...floating, workspaceId: -99, workspaceName: "special:minimized",
    at: [0, 0], size: [1, 1], tags: ["omarchy-minimized-from-2"], focused: false}, neighbor], visible)
  assert.strictEqual(hidden.a.workspaceId, 2)
  assert.strictEqual(hidden.a.minimized, true)
  assert.deepStrictEqual(M.iconItems(M.sortWindows(Object.values(hidden)), false, 8).items.map(w => w.address),
    M.iconItems(before, false, 8).items.map(w => w.address))
  assert.deepStrictEqual(M.previewLayout(M.sortWindows(Object.values(hidden)), area, 260, 143),
    M.previewLayout(before, area, 260, 143))
  hidden = M.windowPlacements([{...hidden.a, title: "Updated", at: [12, 12]}], hidden)
  assert.deepStrictEqual(hidden.a.at, floating.at)
  assert.strictEqual(hidden.a.title, "Updated")
  assert.strictEqual(hidden.b, undefined, "closed windows must be pruned")
})

test("startup finds minimized origins but excludes scratchpads and unclaimed special windows", () => {
  const placements = M.windowPlacements([
    {address: "a", workspaceId: -99, workspaceName: "special:minimized", tags: ["omarchy-minimized-from-12"],
      at: [30, 50], size: [500, 300], floating: true},
    {address: "b", workspaceId: -98, workspaceName: "special:scratchpad", tags: ["omarchy-minimized-from-2"]},
    {address: "c", workspaceId: -99, workspaceName: "special:minimized", tags: ["omarchy-minimized-from-0"]},
    {address: "d", workspaceId: 3, workspaceName: "3", tags: ["omarchy-minimized-from-2"]}
  ], {})
  assert.deepStrictEqual(Object.keys(placements), ["a", "d"])
  assert.strictEqual(placements.a.workspaceId, 12)
  assert.deepStrictEqual(placements.a.at, [30, 50])
  assert.strictEqual(placements.d.workspaceId, 3, "restored windows ignore old origin tags")
  assert.strictEqual(placements.d.minimized, false)
})

test("fresh minimized IPC includes a move made since the last visible snapshot", () => {
  const visible = {address: "a", workspaceId: 2, workspaceName: "2", ipcWorkspaceName: "2",
    at: [310, 180], size: [800, 500], floating: true, monitor: 0}
  let placements = M.windowPlacements([visible], {})
  const hidden = {...visible, workspaceId: -99, workspaceName: "special:minimized",
    tags: ["omarchy-minimized-from-2"]}
  placements = M.windowPlacements([hidden], placements)
  assert.deepStrictEqual(placements.a.at, [310, 180], "workspace changes can precede fresh IPC")
  placements = M.windowPlacements([{...hidden, ipcWorkspaceName: "special:minimized", at: [430, 230], monitor: 1}], placements)
  assert.deepStrictEqual(placements.a.at, [430, 230], "the refreshed compositor geometry is authoritative")
  assert.strictEqual(placements.a.monitor, 0, "the shared minimized workspace must not change the origin monitor")
})

test("restoring and minimizing elsewhere replaces the previous workspace and geometry", () => {
  const first = {address: "a", workspaceId: 2, workspaceName: "2", at: [10, 20], size: [500, 300], floating: true}
  let placements = M.windowPlacements([first], {})
  placements = M.windowPlacements([{...first, workspaceId: -99, workspaceName: "special:minimized"}], placements)
  assert.strictEqual(placements.a.workspaceId, 2, "cached origin covers minimizers without tags")
  const restored = {...first, workspaceId: 3, workspaceName: "3", at: [600, 80], tags: ["omarchy-minimized-from-2"]}
  placements = M.windowPlacements([restored], placements)
  placements = M.windowPlacements([{...restored, workspaceId: -99, workspaceName: "special:minimized",
    tags: ["omarchy-minimized-from-3"], at: [0, 0]}], placements)
  assert.strictEqual(placements.a.workspaceId, 3)
  assert.deepStrictEqual(placements.a.at, [600, 80])
  const cold = M.windowPlacements([{...restored, workspaceId: -99, workspaceName: "special:minimized",
    tags: ["omarchy-minimized-from-4"], at: [100, 100]}], placements)
  assert.strictEqual(cold.a.workspaceId, 4)
  assert.deepStrictEqual(cold.a.at, [100, 100], "a different origin must not inherit old geometry")
})

test("iconItems groups same app and keeps focused address", () => {
  const r = M.iconItems([
    { address: "1", appId: "foot", title: "a", focused: false },
    { address: "2", appId: "zen", title: "b", focused: false },
    { address: "3", appId: "Foot", title: "c", focused: true }
  ], true, 8)
  assert.strictEqual(r.items.length, 2)
  assert.strictEqual(r.items[0].count, 2)
  assert.strictEqual(r.items[0].address, "3")
  assert.strictEqual(r.items[0].focused, true)
})

test("iconItems leaves shell-hosted windows ungrouped", () => {
  const r = M.iconItems([
    { address: "1", appId: "org.quickshell", title: "Omamail", focused: false },
    { address: "2", appId: "org.quickshell", title: "Omarchy", focused: false }
  ], true, 8)
  assert.strictEqual(r.items.length, 2)
})

test("iconItems overflow never hides focused", () => {
  const ws = [1, 2, 3, 4, 5].map(i => ({ address: String(i), appId: "a" + i, title: "", focused: i === 5 }))
  const r = M.iconItems(ws, false, 3)
  assert.strictEqual(r.overflow, 2)
  assert.deepStrictEqual(r.items.map(i => i.address), ["1", "2", "5"])
})

test("focusedLabel uses app name for single window, title for many", () => {
  assert.strictEqual(M.focusedLabel({ focused: true, count: 1, title: "t" }, "Foot", 20), "Foot")
  assert.strictEqual(M.focusedLabel({ focused: true, count: 2, title: "long title here" }, "Foot", 6), "long …")
  assert.strictEqual(M.focusedLabel({ focused: false, count: 1 }, "Foot", 20), "")
})

test("truncate keeps ASCII behaviour unchanged", () => {
  const legacy = (t, max) => t.length > max ? t.slice(0, Math.max(1, max - 1)) + "…" : t
  const maxes = [NaN, undefined]
  for (let max = -2; max <= 30; max++) maxes.push(max)
  for (const t of ["", "a", "foot", "long title here", "~/code/omarchy-spaces — nvim"])
    for (const max of maxes) assert.strictEqual(M.truncate(t, max), legacy(t, max), t + " @ " + max)
  assert.strictEqual(M.truncate("", -1), "…")
  assert.strictEqual(M.truncate(null, -1), "…")
  assert.strictEqual(M.truncate("abc", NaN), "abc")
  assert.strictEqual(M.truncate("abc", undefined), "abc")
})

test("truncate counts wide characters double", () => {
  assert.strictEqual(M.truncate("한국어", 8), "한국어")
  assert.strictEqual(M.truncate("터미널 설정 열기", 8), "터미널 …")
  assert.strictEqual(M.truncate("日本語のタイトル", 8), "日本語…")
  assert.strictEqual(M.truncate("Vim 설정 파일", 7), "Vim 설…")
  assert.strictEqual(M.truncate("☕".repeat(8), 8), "☕☕☕…")
  assert.strictEqual(M.truncate("\uFE50".repeat(8), 8), "\uFE50\uFE50\uFE50…")
  assert.strictEqual(M.truncate("\u2329abc", 4), "\u2329a…")
  assert.strictEqual(M.truncate("❤\uFE0F❤\uFE0Fab", 5), "❤\uFE0F❤\uFE0F…")
  assert.strictEqual(M.truncate("1\uFE0F\u20E3abcd", 5), "1\uFE0F\u20E3ab…")
  assert.strictEqual(M.truncate("❤\uFE0Fab", 4), "❤\uFE0Fab")
  // A wide first character that does not fit the budget leaves only the ellipsis.
  assert.strictEqual(M.truncate("한국", 1), "…")
})

test("truncate never splits an emoji or accented letter", () => {
  assert.strictEqual(M.truncate("👍🏽👍🏽👍🏽👍🏽👍🏽", 8), "👍🏽👍🏽👍🏽…")
  assert.strictEqual(M.truncate("ab👨‍👩‍👧‍👦cd", 5), "ab👨‍👩‍👧‍👦…")
  assert.strictEqual(M.truncate("🇰🇷🇯🇵🇺🇸", 5), "🇰🇷🇯🇵…")
  assert.strictEqual(M.truncate("🇰🇷🇯🇵🇺🇸", 6), "🇰🇷🇯🇵🇺🇸")
  assert.strictEqual(M.truncate("e\u0301e\u0301e\u0301e\u0301e\u0301", 4), "e\u0301e\u0301e\u0301…")
  assert.strictEqual(M.truncate("Cafe\u0301", 4), "Cafe\u0301")
  assert.strictEqual(M.truncate("aaaaaがxxxx", 8), "aaaaaが…")
  assert.strictEqual(M.truncate("aaaaaか\u3099xxxx", 8), "aaaaaか\u3099…")
  assert.strictEqual(M.truncate("葛\uDB40\uDD00葛\uDB40\uDD00葛", 5), "葛\uDB40\uDD00葛\uDB40\uDD00…")
})

test("webAppHost parses chromium app classes", () => {
  assert.strictEqual(M.webAppHost("chrome-web.whatsapp.com__-Default"), "web.whatsapp.com")
  assert.strictEqual(M.webAppHost("brave-app.hey.com__-Profile_1"), "app.hey.com")
  assert.strictEqual(M.webAppHost("chrome-x.com__home-Default"), "x.com")
  assert.strictEqual(M.webAppHost("foot"), "")
})

test("webAppKey keeps the path of chromium app classes", () => {
  assert.strictEqual(M.webAppKey("chrome-www.icloud.com__reminders_-Default"), "www.icloud.com__reminders_")
  assert.strictEqual(M.webAppKey("brave-app.hey.com__-Profile_1"), "app.hey.com__")
  assert.strictEqual(M.webAppKey("chrome-X.com__Home-Default"), "x.com__home")
  assert.strictEqual(M.webAppKey("foot"), "")
  assert.strictEqual(M.webAppKey("chrome-Default"), "")
})

test("chromiumAppKey builds the class key from a URL", () => {
  assert.strictEqual(M.chromiumAppKey("https://www.icloud.com/reminders/"), "www.icloud.com__reminders_")
  assert.strictEqual(M.chromiumAppKey("https://web.whatsapp.com/"), "web.whatsapp.com__")
  assert.strictEqual(M.chromiumAppKey("https://web.whatsapp.com"), "web.whatsapp.com__")
  assert.strictEqual(M.chromiumAppKey("https://x.com/home?lang=en#top"), "x.com__home")
  assert.strictEqual(M.chromiumAppKey("http://user@Example.com:8080/a/b"), "example.com__a_b")
  assert.strictEqual(M.chromiumAppKey("file:///home/me/index.html"), "")
  assert.strictEqual(M.execUrl('omarchy-launch-webapp "https://www.icloud.com/pages/"'), "https://www.icloud.com/pages/")
  assert.strictEqual(M.execUrl("chromium --app=https://x.com/home --flag"), "https://x.com/home")
  assert.strictEqual(M.execUrl("foot"), "")
})

test("webAppEntryIndex tells apart web apps sharing a host", () => {
  const execs = [
    'omarchy-launch-webapp "https://www.icloud.com/numbers/"',
    "foot",
    'omarchy-launch-webapp "https://www.icloud.com/reminders/"',
    'omarchy-launch-webapp "https://www.icloud.com/pages/"',
    'omarchy-launch-webapp "https://web.whatsapp.com/"',
  ]
  assert.strictEqual(M.webAppEntryIndex("chrome-www.icloud.com__reminders_-Default", execs), 2)
  assert.strictEqual(M.webAppEntryIndex("chrome-www.icloud.com__numbers_-Default", execs), 0)
  assert.strictEqual(M.webAppEntryIndex("chromium-www.icloud.com__pages_-Profile_2", execs), 3)
  // No exact match and several entries on the host: no guess.
  assert.strictEqual(M.webAppEntryIndex("chrome-www.icloud.com__keynote_-Default", execs), -1)
  // No exact match and one entry on the host (e.g. a different start path).
  assert.strictEqual(M.webAppEntryIndex("chrome-web.whatsapp.com__send-Default", execs), 4)
  assert.strictEqual(M.webAppEntryIndex("chrome-web.whatsapp.com__-Default", execs), 4)
  assert.strictEqual(M.webAppEntryIndex("chrome-app.hey.com__-Default", execs), -1)
  assert.strictEqual(M.webAppEntryIndex("foot", execs), -1)
  // A host that merely starts with another host is not the same host.
  assert.strictEqual(M.webAppEntryIndex("chrome-x.com__home-Default", ['omarchy-launch-webapp "https://x.community/"']), -1)
})

test("iconPathScore prefers svg then larger png", () => {
  assert.ok(M.iconPathScore("/a/scalable/apps/x.svg") > M.iconPathScore("/a/128x128/apps/x.png"))
  assert.ok(M.iconPathScore("/a/128x128/apps/x.png") > M.iconPathScore("/a/16x16/apps/x.png"))
  assert.strictEqual(M.iconNameFromPath("/a/b/zen-browser.png"), "zen-browser")
})

test("stepWorkspace wraps", () => {
  assert.strictEqual(M.stepWorkspace([1, 2, 5], 5, 1), 1)
  assert.strictEqual(M.stepWorkspace([1, 2, 5], 1, -1), 5)
  assert.strictEqual(M.stepWorkspace([1, 2, 5], 2, 1), 5)
})

test("mergedEntry keeps id first and applies delta", () => {
  assert.deepStrictEqual(M.mergedEntry("x.y", { id: "old", a: 1 }, { b: 2 }), { id: "x.y", a: 1, b: 2 })
})

test("showsApps respects master switch and modes", () => {
  const s = (o) => M.resolveSettings(o)
  assert.strictEqual(M.showsApps(s({ showIcons: false, showApps: "all" }), true, true, true), false)
  assert.strictEqual(M.showsApps(s({ showApps: "all" }), true, false, false), true)
  assert.strictEqual(M.showsApps(s({ showApps: "all" }), false, true, true), false)
  assert.strictEqual(M.showsApps(s({ showApps: "active" }), true, false, true), false)
  assert.strictEqual(M.showsApps(s({ showApps: "hover" }), true, false, true), true)
  assert.strictEqual(M.showsApps(s({ showApps: "hoverOnly" }), true, true, false), false)
  assert.strictEqual(M.showsApps(s({ showApps: "hoverOnly" }), true, false, true), true)
})

test("new settings validate", () => {
  const s = M.resolveSettings({ density: "huge", iconStyle: "mono", activeClick: "previous", settingsButton: "x" })
  assert.strictEqual(s.density, "normal")
  assert.strictEqual(s.iconStyle, "mono")
  assert.strictEqual(s.activeClick, "previous")
  assert.strictEqual(s.settingsButton, "never")
  assert.strictEqual(s.showIcons, true)
  assert.strictEqual(s.pillBackground, true)
  assert.strictEqual(M.resolveSettings({ pillBackground: false }).pillBackground, false)
})

test("pillHeight and pillPadding default to automatic", () => {
  const s = M.resolveSettings({})
  assert.strictEqual(s.pillHeight, 0)
  assert.strictEqual(s.pillPadding, 0)
  assert.strictEqual(M.resolveSettings({ pillHeight: "13" }).pillHeight, 13)
  assert.strictEqual(M.resolveSettings({ pillHeight: -5 }).pillHeight, 0)
  assert.strictEqual(M.resolveSettings({ pillHeight: 500 }).pillHeight, 64)
  assert.strictEqual(M.resolveSettings({ pillPadding: 6 }).pillPadding, 6)
  assert.strictEqual(M.resolveSettings({ pillPadding: 99 }).pillPadding, 24)
  assert.strictEqual(M.resolveSettings({ pillPadding: -1 }).pillPadding, 0)
})

test("automatic pill height is exactly the old expression", () => {
  // No rounding of barSize and no change to the floor: 0 means today's pill.
  for (const bar of [18, 20, 26, 28, 30]) {
    assert.strictEqual(M.pillThickness(bar, 0, 6), Math.max(16, bar - 6))
  }
  assert.strictEqual(M.pillThickness(27.5, 0, 6), 21.5)
  // The spacing scale still reaches the inset, as it always did.
  assert.strictEqual(M.pillThickness(30, 0, 11), 19)
})

test("an explicit pillHeight wins, capped to the bar, 8 px floor", () => {
  assert.strictEqual(M.pillThickness(28, 13, 6), 13)
  assert.strictEqual(M.pillThickness(28, 40, 6), 28)
  assert.strictEqual(M.pillThickness(28, 5, 6), 8)
})

test("pillPadding replaces the density padding only when set", () => {
  assert.strictEqual(M.pillPad(0, 7), 7)
  assert.strictEqual(M.pillPad(6, 7), 6)
  assert.strictEqual(M.pillPad(0, 3), 3)
})

test("the pill limits are stated once", () => {
  assert.strictEqual(M.PILL_LIMITS.heightMin, 8)
  assert.strictEqual(M.PILL_LIMITS.heightMax, 64)
  assert.strictEqual(M.PILL_LIMITS.paddingMax, 24)
  assert.strictEqual(M.PILL_LIMITS.autoFloor, 16)
  assert.strictEqual(M.PILL_LIMITS.autoInset, 6)
  assert.strictEqual(M.PILL_LIMITS.radiusRatio, 0.32)
  // resolveSettings clamps to the same numbers the settings panel shows.
  assert.strictEqual(M.resolveSettings({ pillHeight: 999 }).pillHeight, M.PILL_LIMITS.heightMax)
  assert.strictEqual(M.resolveSettings({ pillPadding: 999 }).pillPadding, M.PILL_LIMITS.paddingMax)
})

test("the bar caps the pill before the floor applies", () => {
  // A bar shorter than the 8 px floor wins: the pill never leaves the bar.
  assert.strictEqual(M.pillThickness(6, 18, 6), 6)
  assert.strictEqual(M.pillThickness(6, 5, 6), 6)
  assert.strictEqual(M.pillThickness(0, 18, 6), 0)
})

test("pillRadius and pillGap carry the widget rules", () => {
  assert.strictEqual(M.pillRadius(20, true), 6)
  assert.strictEqual(M.pillRadius(17, true), 5)
  assert.strictEqual(M.pillRadius(20, false), 0)
  assert.strictEqual(M.pillGap("compact"), 2)
  assert.strictEqual(M.pillGap("roomy"), 7)
  assert.strictEqual(M.pillGap("normal"), 4)
  assert.strictEqual(M.pillGap("junk"), 4)
})

test("normalizeAddress strips 0x and lowercases", () => {
  assert.strictEqual(M.normalizeAddress("0x624FAC"), "624fac")
  assert.strictEqual(M.normalizeAddress("624fac"), "624fac")
})

test("monitorArea removes reserved space in logical coords", () => {
  const a = M.monitorArea({ x: 0, y: 0, width: 3440, height: 1440, scale: 1.25, reserved: [0, 35, 0, 0] })
  assert.deepStrictEqual(a, { x: 0, y: 35, width: 2752, height: 1117 })
  assert.strictEqual(M.monitorArea(null), null)
})

test("previewLayout scales real positions and puts floating last", () => {
  const area = { x: 0, y: 0, width: 1000, height: 500 }
  const out = M.previewLayout([
    { address: "f", at: [100, 100], size: [200, 100], floating: true },
    { address: "a", at: [0, 0], size: [500, 500] },
    { address: "b", at: [500, 0], size: [500, 500] }
  ], area, 100, 50)
  assert.deepStrictEqual(out.map(p => p.address), ["a", "b", "f"])
  assert.deepStrictEqual(out[1], { address: "b", x: 50, y: 0, width: 50, height: 50, floating: false })
  assert.deepStrictEqual([out[2].x, out[2].y, out[2].width, out[2].height], [10, 10, 20, 10])
})

test("monitorArea handles every rotation before scale and logical reservations", () => {
  for (let transform = 0; transform < 8; transform++) {
    const area = M.monitorArea({ x: -1200, y: -400, width: 2560, height: 1440,
      scale: 1.25, transform, reserved: [10, 20, 30, 40] })
    assert.deepStrictEqual(area, { x: -1190, y: -380,
      width: (transform % 2 ? 1152 : 2048) - 40,
      height: (transform % 2 ? 2048 : 1152) - 60 })
  }
})

test("portrait preview keeps both stacked windows fully visible", () => {
  const area = M.monitorArea({ x: -1440, y: -480, width: 2560, height: 1440,
    transform: 1, scale: 1, reserved: [0, 0, 0, 26] })
  const size = M.previewDimensions(area, 380, 1000, 900)
  assert.strictEqual(size.height, 380)
  assert.ok(size.height > size.width)
  const windows = [
    { address: "top", at: [-1440, -480], size: [1440, 1267] },
    { address: "bottom", at: [-1440, 787], size: [1440, 1267] }
  ]
  const out = M.previewLayout(windows, area, size.width, size.height)
  assert.strictEqual(out[0].height, out[1].height)
  assert.strictEqual(out[1].y + out[1].height, size.height)
  assert.strictEqual(out[1].width, size.width)
})

test("previewDimensions fits portrait workspaces on short or narrow screens", () => {
  const area = { width: 1440, height: 2534 }
  for (const bounds of [[1000, 400], [200, 900]]) {
    const size = M.previewDimensions(area, 520, ...bounds)
    assert.ok(size.width <= bounds[0])
    assert.ok(size.height <= bounds[1])
    assert.ok(Math.abs(size.width / size.height - area.width / area.height) < 1e-10)
  }
  assert.deepStrictEqual(M.previewDimensions({ width: 1600, height: 900 }, 380, 1000, 900),
    { width: 380, height: 213.75 })
  assert.deepStrictEqual(M.previewDimensions(null, 380, 1000, 900),
    { width: 380, height: 213.75 })
})

test("preview size has the same longest side and area in either orientation", () => {
  for (const preset of ["small", "medium", "large"]) {
    const extent = M.previewWidth(preset)
    const landscape = M.previewDimensions({ width: 1600, height: 900 }, extent, 2000, 2000)
    const portrait = M.previewDimensions({ width: 900, height: 1600 }, extent, 2000, 2000)
    assert.strictEqual(portrait.height, landscape.width)
    assert.strictEqual(portrait.width, landscape.height)
  }
})

test("previewLayout clamps windows hanging off screen", () => {
  const out = M.previewLayout([{ address: "a", at: [-100, 0], size: [300, 100] }], { x: 0, y: 0, width: 1000, height: 1000 }, 100, 100)
  assert.deepStrictEqual([out[0].x, out[0].width], [0, 20])
})

test("previewLayout falls back to a grid without positions", () => {
  const out = M.previewLayout([{ address: "a" }, { address: "b" }, { address: "c" }], null, 100, 100)
  assert.strictEqual(out.length, 3)
  assert.strictEqual(out[0].x, 0)
  assert.ok(out[1].x > 0)
  assert.ok(out[2].y > 0)
})

test("preview settings validate", () => {
  const s = M.resolveSettings({ previewSize: "huge", previews: false })
  assert.strictEqual(s.previewSize, "medium")
  assert.strictEqual(s.previews, false)
  assert.strictEqual(s.previewLive, true)
  assert.strictEqual(M.previewWidth("large"), 520)
})

test("appIdCandidates adds the last reverse-DNS segment", () => {
  assert.deepStrictEqual(M.appIdCandidates("dev.tgomareli.logi-kvm-console"), ["dev.tgomareli.logi-kvm-console", "logi-kvm-console"])
  assert.deepStrictEqual(M.appIdCandidates("Slack"), ["Slack", "slack"])
  assert.deepStrictEqual(M.appIdCandidates(""), [])
})

test("fallbackLetter prefers the readable tail of a reverse-DNS class", () => {
  // Without this every org.omarchy.* app shares the letter "O".
  assert.strictEqual(M.fallbackLetter("", "org.omarchy.herdr"), "H")
  assert.strictEqual(M.fallbackLetter("", "org.omarchy.agent"), "A")
  // A real desktop-entry name always wins.
  assert.strictEqual(M.fallbackLetter("Zen Browser", "zen"), "Z")
  // appId echoed back as the name is not a real name.
  assert.strictEqual(M.fallbackLetter("org.kde.dolphin", "org.kde.dolphin"), "D")
  assert.strictEqual(M.fallbackLetter("", "foot"), "F")
  assert.strictEqual(M.fallbackLetter("", ""), "")
  // A whole emoji or syllable, never half of a surrogate pair.
  assert.strictEqual(M.fallbackLetter("😀 Smile", "smile"), "😀")
  assert.strictEqual(M.fallbackLetter("👍🏽 Thumbs", "thumbs"), "👍🏽")
  assert.strictEqual(M.fallbackLetter("🇰🇷 Korea", "korea"), "🇰🇷")
  assert.strictEqual(M.fallbackLetter("한글 메모", "memo"), "한")
  assert.strictEqual(M.fallbackLetter("éclair", "eclair"), "É")
  assert.strictEqual(M.fallbackLetter("か\u3099", ""), "か\u3099")
  assert.strictEqual(M.fallbackLetter("が", ""), "が")
})

test("agentWindowStates picks the nearest window and the most urgent state", () => {
  const windows = [
    { address: "0x1", pid: 100 },
    { address: "0x2", pid: 200 },
    { address: "0x3", pid: 300 }
  ]
  const agents = {
    a: { state: "working", pids: [5, 6, 100, 200] },
    b: { state: "waiting", pids: [7, 100] },
    c: { state: "done", pids: [8, 300] },
    d: { state: "idle", pids: [9, 300] },
    e: { state: "working", pids: [10, 11] }
  }
  assert.deepStrictEqual(M.agentWindowStates(agents, windows), { "0x1": "waiting", "0x3": "done" })
})

test("agentWindowStates keeps a shared-PID badge in its pinned window", () => {
  const windows = [
    { address: "0xa", pid: 400 },
    { address: "0xb", pid: 400 },
    { address: "0xc", pid: 400 }
  ]
  // No pin: the PID is ambiguous, so every window with it is badged.
  assert.deepStrictEqual(
    M.agentWindowStates({ s: { state: "working", pids: [9, 400] } }, windows),
    { "0xa": "working", "0xb": "working", "0xc": "working" })
  // Pinned: only the owning window.
  assert.deepStrictEqual(
    M.agentWindowStates({ s: { state: "working", pids: [9, 400], address: "0xb" } }, windows),
    { "0xb": "working" })
  // A pin to a gone window falls back to the ambiguous set.
  assert.deepStrictEqual(
    M.agentWindowStates({ s: { state: "working", pids: [9, 400], address: "0xdead" } }, windows),
    { "0xa": "working", "0xb": "working", "0xc": "working" })
})

test("agentPinAddress pins an ambiguous PID to the focused window", () => {
  const windows = [
    { address: "0xa", pid: 400 },
    { address: "0xb", pid: 400 },
    { address: "0xc", pid: 500 }
  ]
  // Focused window owns the agent: pin it.
  assert.strictEqual(M.agentPinAddress([9, 400], windows, "0xb"), "0xb")
  // Focused window is not an owner: no pin (avoids badging the wrong window).
  assert.strictEqual(M.agentPinAddress([9, 400], windows, "0xc"), "")
  // A unique PID needs no focus.
  assert.strictEqual(M.agentPinAddress([9, 500], windows, "0xa"), "0xc")
  // No window in the chain.
  assert.strictEqual(M.agentPinAddress([9, 10], windows, "0xa"), "")
})

test("normalizeAgentState accepts only badge states", () => {
  assert.strictEqual(M.normalizeAgentState("waiting"), "waiting")
  assert.strictEqual(M.normalizeAgentState("end"), "")
  assert.strictEqual(M.normalizeAgentState("exploding"), "")
  assert.strictEqual(M.normalizeAgentState(undefined), "")
})

test("agentProcessIds collects one live process per active session", () => {
  const agents = {
    a: { state: "working", pids: [101, 1] },
    b: { state: "waiting", pids: [202, 101] },
    c: { state: "waiting", pids: [101, 303] },
    d: { state: "done", pids: [404, 1] },
    e: { state: "working", pids: ["nope", 1] }
  }
  assert.deepStrictEqual(M.agentProcessIds(agents), [101, 202])
})

test("pruneDeadAgents removes only dead live claims", () => {
  const agents = {
    live: { state: "working", pids: [101, 1] },
    dead: { state: "waiting", pids: [202, 1] },
    finished: { state: "done", pids: [303, 1] },
    malformed: { state: "working", pids: [] }
  }
  assert.deepStrictEqual(M.pruneDeadAgents(agents, [101]), {
    live: { state: "working", pids: [101, 1] },
    finished: { state: "done", pids: [303, 1] },
    malformed: { state: "working", pids: [] }
  })
  assert.strictEqual(M.pruneDeadAgents(agents, [101, 202]), agents)
})

test("parsePids drops junk and init", () => {
  assert.deepStrictEqual(M.parsePids("12,abc,1,,34"), [12, 34])
})

// Apps and web pages set their own window titles. Qt guesses rich text by
// default, so a title with markup could load remote images in the shell.
test("window titles and workspace labels render as plain text", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Spaces.qml"), "utf8")
  const blocks = []
  const re = /^\s*Text\s*\{/gm
  let m
  while ((m = re.exec(qml))) {
    let depth = 0, i = qml.indexOf("{", m.index)
    const start = i
    for (; i < qml.length; i++) {
      if (qml[i] === "{") depth++
      else if (qml[i] === "}" && --depth === 0) break
    }
    blocks.push(qml.slice(start, i + 1))
  }
  const titled = blocks.filter((b) => /^\s*text:.*(title|label)/im.test(b))
  assert.ok(titled.length >= 3, "expected the workspace label, the focused title and the preview footer")
  for (const b of titled) assert.match(b, /textFormat:\s*Text\.PlainText/, b.split("\n").find((l) => /text:/.test(l)).trim())
})

test("agentAppId recognises Claude Code, Codex and Grok terminals", () => {
  const g = "com.mitchellh.ghostty"
  assert.strictEqual(M.agentAppId(g, "\u25d1 Omarchy plugin skills"), "agent.claude")
  assert.strictEqual(M.agentAppId(g, "\u2733 Fix the bar"), "agent.claude")
  assert.strictEqual(M.agentAppId(g, "Claude Code"), "agent.claude")
  assert.strictEqual(M.agentAppId(g, "\u2838 Add snapping and dock controls | tcballard"), "agent.codex")
  assert.strictEqual(M.agentAppId(g, "\u280b scratchpad"), "agent.codex")
  assert.strictEqual(M.agentAppId(g, "Collect iPad boot logs | tcballard"), g)
  assert.strictEqual(M.agentAppId(g, "[ . ] Action Required | Build Omarchy shortcut wheel | tcballard"), "agent.codex")
  assert.strictEqual(M.agentAppId(g, "grok"), "agent.grok")
  assert.strictEqual(M.agentAppId(g, "~/code"), g)
  assert.strictEqual(M.agentAppId(g, "grokking notes"), g)
  assert.strictEqual(M.agentAppId(g, ""), g)
  assert.strictEqual(M.agentFor("agent.grok").name, "Grok")
  assert.strictEqual(M.agentFor(g), null)
})


test("agentAppId only recognises agents in known terminals", () => {
  for (const appId of [
    "com.mitchellh.ghostty", "Ghostty", "Alacritty", "org.alacritty.Alacritty",
    "kitty", "net.kovidgoyal.kitty", "foot", "footclient",
    "org.wezfurlong.wezterm", "WezTerm", "org.gnome.Terminal",
    "gnome-terminal-server", "org.gnome.Console", "kgx", "org.kde.konsole",
    "konsole", "XTerm", "UXTerm", "URxvt", "st", "st-256color",
    "xfce4-terminal", "tilix", "com.gexperts.Tilix"
  ]) {
    assert.strictEqual(M.agentAppId(appId, "Claude Code"), "agent.claude", appId)
    assert.strictEqual(M.agentAppId(appId, "\u280b scratchpad"), "agent.codex", appId)
    assert.strictEqual(M.agentAppId(appId, "grok"), "agent.grok", appId)
  }
  for (const appId of ["zen", "chromium", "firefox", "omarchy-webapp", "my-foot-app", "", null, undefined]) {
    for (const title of [
      "WeTransfer | Send Large Files Fast — Zen Browser",
      "Pricing | Vercel - Chromium",
      "Claude Code overview - Anthropic - Chromium",
      "grok - Google Search - Chromium",
      "Claude Code", "grok", "\u280b scratchpad",
      "[ . ] Action Required | Build Omarchy shortcut wheel | tcballard"
    ]) assert.strictEqual(M.agentAppId(appId, title), appId, String(appId) + ": " + title)
  }
})

test("agentAppId leaves ambiguous Codex titles as terminal windows", () => {
  const appId = "com.mitchellh.ghostty"
  for (const title of [
    "Collect iPad boot logs | tcballard", "vim | project", "build | x",
    "Pricing | Vercel - Chromium", "scratchpad", "notes [ . ] Action Required | project",
    "[ . ] Action Requiredness | project"
  ]) assert.strictEqual(M.agentAppId(appId, title), appId, title)
})

test("monitor-local placeholders retain global IDs for actions", () => {
  assert.deepStrictEqual(M.workspaceIds({11: 1, 13: 2}, [11], 5, false, 1), [11, 12, 13, 14, 15])
  assert.deepStrictEqual(M.workspaceIds({11: 1, 13: 2}, [12], 5, true, 1), [11, 12, 13])
  assert.deepStrictEqual(M.workspaceIds({6: 1}, [6], 5, false, 0), [1, 2, 3, 4, 5, 6])
  assert.deepStrictEqual(M.workspaceIds({11: 1}, [11], 2, false), [1, 2, 11])
})

test("visiting workspaces follow the monitor's own", () => {
  assert.deepStrictEqual(M.workspaceIds({3: 1, 12: 1, 26: 1}, [12], 5, false, 1), [11, 12, 13, 14, 15, 3, 26])
  assert.deepStrictEqual(M.workspaceIds({3: 1, 12: 1}, [3], 5, true, 1), [12, 3])
  assert.deepStrictEqual(M.workspaceIds({3: 1, 12: 1}, [3], 2, false), [1, 2, 3, 12])
})

test("local labels preserve guest IDs and existing label styles", () => {
  assert.strictEqual(M.workspaceLabel(11, false, "number", 1), "1")
  assert.strictEqual(M.workspaceLabel(15, false, "number", 1), "5")
  assert.strictEqual(M.workspaceLabel(20, false, "number", 1), "0")
  assert.strictEqual(M.workspaceLabel(21, false, "number", 1), "21")
  assert.strictEqual(M.workspaceLabel(11, false, "number", -1), "11")
  assert.strictEqual(M.workspaceLabel(11, false, "none", 1), "")
  assert.strictEqual(M.workspaceLabel(11, true, "glyph", 1), M.workspaceLabel(1, true, "glyph"))
})

test("monitor block parser handles missing and malformed snapshots", () => {
  for (const input of [undefined, "", "junk", "-1\tDP-1\tdisplay", "1.5\tDP-1\tdisplay",
    "1\t\tdisplay", "99999999999999999999\tDP-1\tdisplay"]) {
    assert.strictEqual(M.monitorWorkspaceBlock(M.parseWorkspaceBlocks(input), "DP-1", true), -1)
  }
  const blocks = M.parseWorkspaceBlocks("0\teDP-1\tLaptop\n1\tDP-1\tExternal\njunk\n")
  assert.strictEqual(M.monitorWorkspaceBlock(blocks, "eDP-1", true), 0)
  assert.strictEqual(M.monitorWorkspaceBlock(blocks, "DP-1", true), 1)
  assert.strictEqual(M.monitorWorkspaceBlock(blocks, "DP-1", false), -1)
  assert.strictEqual(M.monitorWorkspaceBlock(blocks, "constructor", true), -1)
})

test("new monitor snapshots replace assignments and remove stale monitors", () => {
  let blocks = M.parseWorkspaceBlocks("0\teDP-1\tLaptop\n1\tDP-1\tExternal")
  assert.strictEqual(M.monitorWorkspaceBlock(blocks, "DP-1", true), 1)
  blocks = M.parseWorkspaceBlocks("0\tDP-1\tExternal")
  const block = M.monitorWorkspaceBlock(blocks, "DP-1", true)
  assert.strictEqual(block, 0)
  assert.strictEqual(M.monitorWorkspaceBlock(blocks, "eDP-1", true), -1)
  assert.deepStrictEqual(M.workspaceIds({}, [1], 5, false, block), [1, 2, 3, 4, 5])
  blocks = M.parseWorkspaceBlocks("")
  assert.strictEqual(M.monitorWorkspaceBlock(blocks, "DP-1", true), -1)
})

test("workspace block and slot boundaries agree with Omarchy", () => {
  for (const [id, block, slot] of [[1, 0, 1], [10, 0, 10], [11, 1, 1], [20, 1, 10], [21, 2, 1]]) {
    assert.strictEqual(M.workspaceBlockOf(id), block)
    assert.strictEqual(M.workspaceSlotOf(id), slot)
  }
})

test("workspace icon settings default off and reject junk", () => {
  const s = M.resolveSettings({})
  assert.strictEqual(s.activeIcon, "")
  for (let i = 1; i <= 10; i++) assert.strictEqual(s["wsIcon" + i], "")
  const junk = M.resolveSettings({ activeIcon: 42, wsIcon3: null })
  assert.strictEqual(junk.activeIcon, "")
  assert.strictEqual(junk.wsIcon3, "")
})

test("workspace icon strings are capped at 32 graphemes", () => {
  const s = M.resolveSettings({ wsIcon1: "a".repeat(40), wsIcon2: "\u{1F600}\u{1F600}" })
  assert.strictEqual(s.wsIcon1, "a".repeat(32))
  // Surrogate pairs stay whole; two emoji count as two graphemes.
  assert.strictEqual(s.wsIcon2, "\u{1F600}\u{1F600}")
  // A 40-emoji chain of ZWJ families clips to whole families, never half a
  // sequence.
  const family = "\uD83D\uDC68\u200D\uD83D\uDC69\u200D\uD83D\uDC67\u200D\uD83D\uDC66"
  const long = M.resolveSettings({ wsIcon5: family.repeat(40) })
  assert.strictEqual(long.wsIcon5.length % family.length, 0)
  assert.ok(long.wsIcon5.length <= 32 * family.length)
})

test("workspaceIcon only applies to the custom label style", () => {
  const fields = { wsIcon3: "\u2302", activeIcon: "\u2699" }
  // Number, glyph and none keep their stock behaviour with fields present.
  for (const style of ["number", "glyph", "none"]) {
    const s = M.resolveSettings({ ...fields, labelStyle: style })
    assert.strictEqual(M.workspaceIcon(s, 3, true), "", style)
    assert.strictEqual(M.workspaceIcon(s, 7, true), "", style)
  }
  const custom = M.resolveSettings({ ...fields, labelStyle: "custom" })
  assert.strictEqual(M.workspaceIcon(custom, 3, false), "\u2302")
})

test("workspaceIcon falls back to the label and honours precedence", () => {
  const off = M.resolveSettings({ labelStyle: "custom" })
  assert.strictEqual(M.workspaceIcon(off, 3, true), "")
  assert.strictEqual(M.workspaceIcon(off, 10, false), "")

  const named = M.resolveSettings({ wsIcon3: "\u2302", wsIcon10: "0\uFE0F\u20E3", activeIcon: "\u2699", labelStyle: "custom" })
  assert.strictEqual(M.workspaceIcon(named, 3, false), "\u2302")
  assert.strictEqual(M.workspaceIcon(named, 10, false), "0\uFE0F\u20E3")
  // Unnamed workspaces fall back, and the focused one shows the override.
  assert.strictEqual(M.workspaceIcon(named, 7, false), "")
  assert.strictEqual(M.workspaceIcon(named, 7, true), "\u2699")
  // A named workspace keeps its icon even while focused.
  assert.strictEqual(M.workspaceIcon(named, 3, true), "\u2302")
  // Workspace 11 has no per-workspace field, but the active override still
  // applies to whatever is focused.
  assert.strictEqual(M.workspaceIcon(named, 11, true), "\u2699")
})

if (failed) { console.log(failed + " failed"); process.exit(1) }
