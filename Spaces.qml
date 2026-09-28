import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Workspace switcher that shows which apps are open on each workspace.
//
// Each workspace is a pill. The active pill (and, depending on settings, the
// hovered or every occupied pill) slides open to reveal the app icons of its
// windows. Left-click a pill to focus the workspace, left-click an icon to
// focus that window, scroll to step through workspaces, right-click for
// settings. Settings persist inline on this widget's shell.json entry.
Panel {
  id: root
  moduleName: "tornikegomareli.spaces"
  ipcTarget: "tornikegomareli.spaces"
  manageIpc: false

  // ------------------------------------------------------------ settings

  readonly property var cfg: Model.resolveSettings(root.settings)

  function applySetting(delta) {
    var entry = Model.mergedEntry(root.moduleName, root.settings, delta)
    // Applied locally first so the widget redraws on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function resetSettings() {
    var entry = { id: root.moduleName }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ------------------------------------------------------------ geometry & colors

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color bg: bar ? bar.background : Color.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int pillThickness: Math.max(16, barSize - Style.space(6))
  readonly property int iconPx: Math.min(cfg.iconSize, pillThickness - Style.space(4))
  readonly property int pillRadius: Style.cornerRadius > 0 ? Math.round(pillThickness * 0.32) : 0
  readonly property int dur: Model.durationFor(cfg, 280)
  readonly property int fastDur: Model.durationFor(cfg, 160)
  readonly property real trailingGap: vertical ? 0 : Style.spaceReal(1.5)
  readonly property var metrics: Model.densityMetrics(cfg.density)
  readonly property bool widgetHovered: widgetHover.hovered

  function activeFill() {
    if (cfg.activeStyle === "solid") return root.fg
    if (cfg.activeStyle === "accent") return Color.accent
    return Util.alpha(root.fg, 0.18)
  }

  function activeText() {
    return cfg.activeStyle === "subtle" ? root.fg : root.bg
  }

  // ------------------------------------------------------------ Hyprland state

  // Bumped after Hyprland reports window moves, so positions (and therefore
  // icon order) re-read the freshly refreshed IPC objects.
  property int revision: 0

  readonly property var monitor: {
    var w = root.QsWindow.window
    return w && w.screen ? Hyprland.monitorFor(w.screen) : null
  }

  readonly property int currentWorkspaceId: {
    if (cfg.perMonitor && root.monitor && root.monitor.activeWorkspace) return root.monitor.activeWorkspace.id
    return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  }

  // Workspace focused before the current one, for "click active = go back".
  property int previousWorkspaceId: -1
  property int lastWorkspaceId: -1
  onCurrentWorkspaceIdChanged: {
    if (root.lastWorkspaceId > 0 && root.lastWorkspaceId !== root.currentWorkspaceId)
      root.previousWorkspaceId = root.lastWorkspaceId
    root.lastWorkspaceId = root.currentWorkspaceId
    if (root.currentWorkspaceId === root.previewWorkspaceId) root.hidePreview()
  }

  // Addresses (normalized) of windows that requested attention and have not
  // been focused since.
  property var urgentAddresses: ({})

  function setUrgent(address, urgent) {
    var key = Model.normalizeAddress(address)
    if (key === "" || (!!root.urgentAddresses[key]) === urgent) return
    var next = ({})
    for (var k in root.urgentAddresses) if (k !== key) next[k] = true
    if (urgent) next[key] = true
    root.urgentAddresses = next
  }

  function isUrgent(address) {
    return root.cfg.urgentHighlight && !!root.urgentAddresses[Model.normalizeAddress(address)]
  }

  // ------------------------------------------------------------ agents

  // Coding agents report in through reporter hooks (for example,
  // hooks/claude-hook):
  //   { [session]: { state: "working" | "waiting" | "done" | "idle", pids: [...] } }
  // Reporters are trusted for their own lifecycle, but not forever: a crashed
  // reporter never sends "end", so live claims are rechecked against /proc.
  property var agents: ({})
  property var liveAgentPids: ({})
  property bool agentProbeSeen: false
  property bool agentProbeFailed: false

  readonly property var pidByAddress: {
    var map = ({})
    for (var id in root.workspaceMap) {
      var windows = root.workspaceMap[id].windows
      for (var i = 0; i < windows.length; i++) map[windows[i].address] = windows[i].pid
    }
    return map
  }

  readonly property var agentByPid: {
    if (!root.cfg.agentStatus) return ({})
    var pids = ({})
    for (var address in root.pidByAddress) if (root.pidByAddress[address]) pids[root.pidByAddress[address]] = true
    return Model.agentStates(root.agents, pids)
  }

  function agentStateFor(addresses) {
    var best = ""
    var rank = { waiting: 3, working: 2, done: 1 }
    for (var i = 0; i < addresses.length; i++) {
      var state = root.agentByPid[root.pidByAddress[addresses[i]]] || ""
      if (state && (!best || rank[state] > rank[best])) best = state
    }
    return best
  }

  // PID of the window that owns an agent: its nearest ancestor window.
  function agentWindowPid(agent) {
    var windowPids = ({})
    for (var address in root.pidByAddress) windowPids[root.pidByAddress[address]] = true
    for (var i = 0; i < agent.pids.length; i++) if (windowPids[agent.pids[i]]) return agent.pids[i]
    return 0
  }

  function activeWindowPid() {
    var active = Hyprland.activeToplevel
    return active ? (root.pidByAddress[String(active.address)] || 0) : 0
  }

  function applyAgent(session, state, pidsCsv) {
    var next = ({})
    for (var k in root.agents) if (k !== session) next[k] = root.agents[k]
    if (state === "end") {
      root.agents = next
      return
    }
    var reported = Model.normalizeAgentState(state)
    if (!reported) return
    var agent = { state: reported, pids: Model.parsePids(pidsCsv) }
    // Finishing in the window you are looking at needs no check mark.
    if (reported === "done" && root.agentWindowPid(agent) === root.activeWindowPid()) agent.state = "idle"
    next[session] = agent
    root.agents = next
  }

  // A crashed reporter leaves working/waiting behind with no "end". Recheck
  // the agent process itself: ancestors and terminals can outlive the agent.
  function startAgentProbe() {
    if (agentProbe.running) return
    var pids = Model.agentProcessIds(root.agents)
    if (!pids.length) return
    root.liveAgentPids = ({})
    root.agentProbeSeen = false
    root.agentProbeFailed = false
    agentProbe.command = ["bash", "-c", [
      'echo "spaces-agent-probe";',
      'if [[ ! -d /proc ]]; then echo "spaces-agent-probe-unavailable"; exit 0; fi;',
      'for pid in ' + pids.join(" ") + '; do',
      '[[ -r /proc/$pid/stat ]] || continue;',
      'stat=$(cat "/proc/$pid/stat" 2>/dev/null) || continue;',
      'rest=${stat##*) };',
      '[[ ${rest:1:1} != "Z" ]] && echo "$pid";',
      'done'
    ].join("\n")]
    agentProbe.running = true
  }

  function noteAgentProbe(line) {
    var text = String(line || "").trim()
    if (text === "spaces-agent-probe") {
      root.agentProbeSeen = true
      return
    }
    if (text === "spaces-agent-probe-unavailable") {
      root.agentProbeFailed = true
      return
    }
    var pid = Number(text)
    if (pid > 1) root.liveAgentPids[pid] = true
  }

  function finishAgentProbe() {
    var alive = root.liveAgentPids
    var seen = root.agentProbeSeen
    var failed = root.agentProbeFailed
    root.liveAgentPids = ({})
    root.agentProbeSeen = false
    root.agentProbeFailed = false
    // Never reap on a broken probe: an empty result must mean dead agents,
    // not a failed check.
    if (!seen || failed) return
    // pruneDeadAgents takes an array; liveAgentPids is a dedup map.
    root.agents = Model.pruneDeadAgents(root.agents, Object.keys(alive))
  }

  // Seeing a finished agent's window clears its check mark.
  function acknowledgeAgents() {
    var pid = root.activeWindowPid()
    if (!pid) return
    var changed = false
    var next = ({})
    for (var k in root.agents) {
      var agent = root.agents[k]
      if (agent.state === "done" && root.agentWindowPid(agent) === pid) {
        agent = { state: "idle", pids: agent.pids }
        changed = true
      }
      next[k] = agent
    }
    if (changed) root.agents = next
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { Qt.callLater(root.acknowledgeAgents) }
  }

  Process {
    id: agentProbe
    stdout: SplitParser { onRead: function(line) { root.noteAgentProbe(line) } }
    onExited: root.finishAgentProbe()
  }

  Timer {
    id: agentProbeTimer
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.startAgentProbe()
  }

  function appIdOf(toplevel) {
    if (toplevel.wayland && toplevel.wayland.appId) return toplevel.wayland.appId
    var ipc = toplevel.lastIpcObject
    return ipc && ipc["class"] ? ipc["class"] : ""
  }

  // { [workspaceId]: { id, active, windows: [{ address, appId, title, focused, at }] } }
  readonly property var workspaceMap: {
    root.revision
    var values = Hyprland.workspaces.values
    var activeToplevel = Hyprland.activeToplevel
    var perMonitor = cfg.perMonitor && root.monitor !== null
    var map = ({})

    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws.id <= 0) continue
      if (perMonitor && ws.monitor !== root.monitor) continue

      var windows = []
      var toplevels = ws.toplevels.values
      for (var j = 0; j < toplevels.length; j++) {
        var tl = toplevels[j]
        var ipc = tl.lastIpcObject || {}
        windows.push({
          address: String(tl.address),
          appId: root.appIdOf(tl),
          title: String(tl.title || ""),
          focused: activeToplevel ? tl === activeToplevel : !!(tl.wayland && tl.wayland.activated),
          at: ipc.at && ipc.at.length === 2 ? [ipc.at[0], ipc.at[1]] : null,
          size: ipc.size && ipc.size.length === 2 ? [ipc.size[0], ipc.size[1]] : null,
          floating: ipc.floating === true,
          pid: ipc.pid || 0,
          toplevel: tl.wayland
        })
      }
      var mon = ws.monitor
      var area = mon ? Model.monitorArea({
        x: mon.x, y: mon.y, width: mon.width, height: mon.height, scale: mon.scale,
        reserved: mon.lastIpcObject ? mon.lastIpcObject.reserved : null
      }) : null
      map[ws.id] = { id: ws.id, windows: Model.sortWindows(windows), area: area }
    }
    return map
  }

  readonly property var workspaceIds: {
    var occupied = ({})
    for (var id in workspaceMap) occupied[id] = workspaceMap[id].windows.length
    var active = root.currentWorkspaceId > 0 ? [root.currentWorkspaceId] : []
    return Model.workspaceIds(occupied, active, cfg.persistentWorkspaces, cfg.hideEmpty)
  }

  function focusWorkspace(id) {
    run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function focusWindow(address) {
    var target = "address:0x" + String(address).replace(/^0x/, "")
    run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"" + target + "\" })")
      + " >/dev/null 2>&1 || hyprctl dispatch focuswindow " + Util.shellQuote(target))
  }

  function closeWindow(address) {
    var target = "address:0x" + Model.normalizeAddress(address)
    run("hyprctl dispatch " + Util.shellQuote("hl.dsp.window.close({ window = \"" + target + "\" })")
      + " >/dev/null 2>&1 || hyprctl dispatch closewindow " + Util.shellQuote(target))
  }

  function clickWorkspace(id) {
    if (id === root.currentWorkspaceId) {
      if (root.cfg.activeClick === "previous" && root.previousWorkspaceId > 0) focusWorkspace(root.previousWorkspaceId)
      return
    }
    focusWorkspace(id)
  }

  function activateItem(item) {
    // A grouped icon that is already focused cycles through its windows.
    if (item.focused && item.addresses.length > 1) {
      var idx = item.addresses.indexOf(item.address)
      focusWindow(item.addresses[(idx + 1) % item.addresses.length])
    } else {
      focusWindow(item.address)
    }
  }

  function scrollBy(delta) {
    if (!cfg.scrollSwitch || delta === 0) return
    var next = Model.stepWorkspace(root.workspaceIds, root.currentWorkspaceId, delta < 0 ? 1 : -1)
    if (next !== root.currentWorkspaceId) focusWorkspace(next)
  }

  function showTip(target, text) {
    if (root.bar && root.cfg.tooltips && text) root.bar.showTooltip(target, text)
  }

  function hideTip(target) {
    if (root.bar) root.bar.hideTooltip(target)
  }

  function run(command) {
    if (root.bar && typeof root.bar.run === "function") root.bar.run(command)
    else Quickshell.execDetached(["bash", "-c", command])
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
      case "urgent":
        root.setUrgent(event.data, true)
        break
      case "activewindowv2":
        root.setUrgent(event.data, false)
        refreshDebounce.restart()
        break
      case "closewindow":
        root.setUrgent(event.data, false)
        refreshDebounce.restart()
        break
      case "openwindow":
      case "movewindow":
      case "movewindowv2":
      case "changefloatingmode":
      case "windowtitle":
      case "windowtitlev2":
        refreshDebounce.restart()
        break
      }
    }
  }

  Timer {
    id: refreshDebounce
    interval: 120
    onTriggered: {
      Hyprland.refreshToplevels()
      revisionBump.restart()
    }
  }

  Timer {
    id: revisionBump
    interval: 80
    onTriggered: root.revision++
  }

  // ------------------------------------------------------------ app icons

  property var iconIndex: ({})
  property var pendingIconIndex: ({})
  property var iconCache: ({})
  property int iconRevision: 0

  function findDesktopEntry(appId) {
    if (!appId) return null
    var candidates = Model.appIdCandidates(appId)
    for (var c = 0; c < candidates.length; c++) {
      var byId = DesktopEntries.byId(candidates[c])
      if (byId) return byId
    }
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry

    var host = Model.webAppHost(appId)
    if (host === "") return null
    var apps = DesktopEntries.applications.values
    for (var i = 0; i < apps.length; i++) {
      var exec = String(apps[i].execString || "")
      if (exec.indexOf("//" + host) !== -1) return apps[i]
    }
    return null
  }

  function iconUrl(name) {
    var value = String(name || "")
    if (value === "") return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var indexed = root.iconIndex[value]
    if (indexed) return Util.fileUrl(indexed)
    return Quickshell.iconPath(value, true)
  }

  // Returns { source, name } for an app id; cached until icons rescan.
  function appInfo(appId) {
    root.iconRevision
    var key = Model.appKey(appId)
    var cached = root.iconCache[key]
    if (cached) return cached

    var entry = findDesktopEntry(appId)
    var source = iconUrl(entry && entry.icon ? entry.icon : appId)
    if (source === "" && key !== appId) source = iconUrl(key)
    var info = { source: source, name: entry && entry.name ? String(entry.name) : String(appId || "") }
    root.iconCache[key] = info
    return info
  }

  function invalidateIcons() {
    root.iconCache = ({})
    root.iconRevision++
  }

  function indexIconLine(line) {
    var path = String(line || "").trim()
    if (path === "") return
    var name = Model.iconNameFromPath(path)
    var existing = root.pendingIconIndex[name]
    if (!existing || Model.iconPathScore(path) > Model.iconPathScore(existing))
      root.pendingIconIndex[name] = path
  }

  Process {
    id: iconScan
    // Non-login shell on purpose: a login shell can touch ~/.local/share and
    // retrigger desktop-entry watchers.
    command: ["bash", "-c", [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for base in $dirs; do [[ -d $base ]] && find "$base" -path "*/apps/*" \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null; done;',
      'find /usr/share/pixmaps -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null'
    ].join(" ")]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    onExited: {
      root.iconIndex = root.pendingIconIndex
      root.invalidateIcons()
    }
  }

  Connections {
    target: DesktopEntries
    function onApplicationsChanged() { iconDebounce.restart() }
  }

  Timer {
    id: iconDebounce
    interval: 1500
    onTriggered: root.invalidateIcons()
  }

  Component.onCompleted: {
    // Touching the list starts Quickshell's desktop-entry scan.
    DesktopEntries.applications.values
    iconScan.running = true
    Hyprland.refreshToplevels()
  }

  // ------------------------------------------------------------ previews

  // Hovering a pill of another workspace shows a live miniature of it. One
  // card serves every pill and slides between them.
  property int previewWorkspaceId: -1
  property Item previewPill: null
  property bool previewWanted: false
  property string highlightAddress: ""

  readonly property bool previewOpen: previewWanted && previewWorkspaceId > 0 && !root.opened
    && root.cfg.previews && !!root.workspaceMap[previewWorkspaceId]
    && root.workspaceMap[previewWorkspaceId].windows.length > 0

  function pillHovered(pill, hovered) {
    if (!root.cfg.previews) return
    if (hovered && pill.workspaceId !== root.currentWorkspaceId && pill.occupied) {
      previewHideTimer.stop()
      root.previewPill = pill
      if (root.previewOpen) {
        // Already showing: follow the pointer right away.
        root.previewWorkspaceId = pill.workspaceId
        root.placePreviewAnchor(true)
      } else {
        previewShowTimer.restart()
      }
    } else if (!hovered) {
      previewShowTimer.stop()
      previewHideTimer.restart()
    }
  }

  function hidePreview() {
    previewShowTimer.stop()
    previewHideTimer.stop()
    root.previewWanted = false
    root.highlightAddress = ""
  }

  function placePreviewAnchor(animate) {
    var pill = root.previewPill
    if (!pill) return
    var p = pill.mapToItem(root, 0, 0)
    previewAnchor.animate = animate
    previewAnchor.x = p.x
    previewAnchor.y = p.y
    previewAnchor.width = pill.width
    previewAnchor.height = pill.height
  }

  Timer {
    id: previewShowTimer
    interval: 380
    onTriggered: {
      if (!root.previewPill) return
      root.previewWorkspaceId = root.previewPill.workspaceId
      root.placePreviewAnchor(false)
      root.previewWanted = true
    }
  }

  Timer {
    id: previewHideTimer
    interval: 200
    onTriggered: if (!preview.containsMouse) root.hidePreview()
  }

  // Opens the preview for a workspace without hovering, e.g. from a
  // keybinding. Closes on its own unless the pointer moves onto the card.
  function peek(id) {
    var idx = root.workspaceIds.indexOf(Number(id))
    var pill = idx >= 0 ? pillRepeater.itemAt(idx) : null
    if (!pill || !pill.occupied) return false
    previewHideTimer.stop()
    root.previewPill = pill
    root.previewWorkspaceId = pill.workspaceId
    root.placePreviewAnchor(root.previewOpen)
    root.previewWanted = true
    peekTimer.restart()
    return true
  }

  Timer {
    id: peekTimer
    interval: 2500
    onTriggered: if (!preview.containsMouse) root.hidePreview()
  }

  onOpenedChanged: if (opened) hidePreview()

  // ------------------------------------------------------------ IPC

  IpcHandler {
    target: "tornikegomareli.spaces"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function peek(workspace: string): string { return root.peek(workspace) ? "ok" : "empty" }
    function agent(session: string, state: string, pids: string): void {
      // One IPC handler serves every monitor's bar, so relay to all of them.
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      if (items.indexOf(root) === -1) items = items.concat([root])
      for (var i = 0; i < items.length; i++) if (items[i] && typeof items[i].applyAgent === "function") items[i].applyAgent(session, state, pids)
    }
  }

  // ------------------------------------------------------------ bar widget

  implicitWidth: vertical ? barSize : pillFlow.implicitWidth + trailingGap
  implicitHeight: vertical ? pillFlow.implicitHeight : barSize

  HoverHandler { id: widgetHover }

  // Right-click anywhere opens settings; wheel steps workspaces. Pills and
  // icons only take the left button, so other buttons fall through to here.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) { if (mouse.button === Qt.RightButton) root.toggle() }
    onWheel: function(wheel) { root.scrollBy(wheel.angleDelta.y || wheel.angleDelta.x) }
  }

  Grid {
    id: pillFlow
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: root.vertical ? Math.round((root.barSize - root.pillThickness) / 2) : 0
    anchors.topMargin: root.vertical ? 0 : Math.round((root.barSize - root.pillThickness) / 2)
    columns: root.vertical ? 1 : Math.max(1, root.workspaceIds.length + 1)
    spacing: Style.space(root.metrics.gap)

    Repeater {
      id: pillRepeater
      model: ScriptModel { values: root.workspaceIds }

      delegate: Item {
        id: pill

        required property var modelData
        readonly property int workspaceId: Number(modelData)
        readonly property var workspace: root.workspaceMap[workspaceId] || ({ id: workspaceId, windows: [] })
        readonly property bool active: workspaceId === root.currentWorkspaceId
        readonly property bool occupied: workspace.windows.length > 0
        readonly property bool hovered: pillHover.hovered
        onHoveredChanged: root.pillHovered(pill, hovered)
        readonly property bool showApps: Model.showsApps(root.cfg, occupied, active, hovered)
        readonly property bool urgent: {
          if (active) return false
          if (root.agentStateFor(workspace.windows.map(function(w) { return w.address })) === "waiting") return true
          if (!root.cfg.urgentHighlight) return false
          for (var i = 0; i < workspace.windows.length; i++)
            if (root.isUrgent(workspace.windows[i].address)) return true
          return false
        }
        readonly property var iconData: Model.iconItems(workspace.windows, root.cfg.groupApps, root.cfg.maxIcons)
        readonly property var itemMap: {
          var map = ({})
          for (var i = 0; i < iconData.items.length; i++) map[iconData.items[i].key] = iconData.items[i]
          return map
        }
        readonly property var itemKeys: iconData.items.map(function(item) { return item.key })
        readonly property color textColor: active ? root.activeText() : root.fg
        readonly property string label: Model.workspaceLabel(workspaceId, active, root.cfg.labelStyle)
        readonly property real pad: Style.space(label === "" ? 3 : root.metrics.pad)

        // Appear animation lives on the delegate: positioner add transitions
        // can be interrupted and leave items stuck half faded.
        property real appear: root.dur > 0 ? 0 : 1
        opacity: appear
        scale: 0.6 + 0.4 * appear
        Component.onCompleted: if (root.dur > 0) pillAppear.start()
        NumberAnimation { id: pillAppear; target: pill; property: "appear"; to: 1; duration: root.dur; easing.type: Easing.OutBack }

        width: implicitWidth
        height: implicitHeight
        implicitWidth: root.vertical ? root.pillThickness : content.implicitWidth + pad * 2
        implicitHeight: root.vertical ? content.implicitHeight + pad * 2 : root.pillThickness

        Behavior on implicitWidth { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
        Behavior on implicitHeight { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

        // Urgent pulse, under the regular fill so the active style still reads.
        Rectangle {
          id: urgentGlow
          anchors.fill: parent
          radius: root.pillRadius
          color: root.bar ? root.bar.urgent : Color.urgent
          opacity: 0
          visible: pill.urgent

          SequentialAnimation on opacity {
            running: pill.urgent
            loops: Animation.Infinite
            NumberAnimation { from: 0.15; to: 0.55; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.55; to: 0.15; duration: 700; easing.type: Easing.InOutSine }
          }
        }

        Rectangle {
          anchors.fill: parent
          radius: root.pillRadius
          color: pill.active ? root.activeFill()
            : pill.hovered ? Util.alpha(root.fg, 0.12)
            : pill.occupied ? Util.alpha(root.fg, 0.06)
            : "transparent"
          Behavior on color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
        }

        HoverHandler { id: pillHover }

        MouseArea {
          id: pillMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.hidePreview()
            root.clickWorkspace(pill.workspaceId)
          }
          onWheel: function(wheel) { root.scrollBy(wheel.angleDelta.y || wheel.angleDelta.x) }
        }

        Grid {
          id: content
          anchors.centerIn: parent
          columns: root.vertical ? 1 : 2
          horizontalItemAlignment: Grid.AlignHCenter
          verticalItemAlignment: Grid.AlignVCenter
          spacing: pill.label !== "" && iconClip.shownExtent > 0 ? Style.space(5) : 0

          Text {
            visible: pill.label !== ""
            text: pill.label
            color: pill.textColor
            opacity: pill.occupied || pill.active ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: pill.active
            Behavior on color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
            Behavior on opacity { enabled: root.fastDur > 0; NumberAnimation { duration: root.fastDur } }
          }

          // The icon strip is clipped and its extent animates, so icons slide
          // out of the pill rather than popping in.
          Item {
            id: iconClip
            readonly property real fullExtent: root.vertical ? icons.implicitHeight : icons.implicitWidth
            property real shownExtent: pill.showApps ? fullExtent : 0
            Behavior on shownExtent { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

            implicitWidth: root.vertical ? icons.implicitWidth : shownExtent
            implicitHeight: root.vertical ? shownExtent : icons.implicitHeight
            clip: true
            opacity: pill.showApps ? 1 : 0
            Behavior on opacity { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

            Grid {
              id: icons
              columns: root.vertical ? 1 : Math.max(1, pill.itemKeys.length + 1)
              spacing: Style.space(root.metrics.iconGap)
              verticalItemAlignment: Grid.AlignVCenter
              horizontalItemAlignment: Grid.AlignHCenter

              move: Transition {
                enabled: root.dur > 0
                NumberAnimation { properties: "x,y"; duration: root.dur; easing.type: Easing.OutCubic }
              }

              Repeater {
                model: ScriptModel { values: pill.itemKeys }

                delegate: Item {
                  id: appIcon

                  required property var modelData
                  readonly property var item: pill.itemMap[modelData] || null
                  readonly property var info: item ? root.appInfo(item.appId) : ({ source: "", name: "" })
                  readonly property bool focusedHere: !!item && item.focused && pill.active
                  readonly property string titleText: root.cfg.focusedTitle && focusedHere && !root.vertical
                    ? Model.focusedLabel(item, info.name, root.cfg.titleLength) : ""
                  readonly property bool hovered: iconMouse.containsMouse
                  readonly property string agentState: item ? root.agentStateFor(item.addresses) : ""

                  implicitWidth: iconRow.implicitWidth + Style.space(4)
                  implicitHeight: Math.max(root.iconPx, iconRow.implicitHeight) + Style.space(4)
                  width: implicitWidth
                  height: implicitHeight
                  property real dim: root.cfg.dimUnfocused && pill.active && !focusedHere && !hovered ? 0.5 : 1
                  Behavior on dim { enabled: root.fastDur > 0; NumberAnimation { duration: root.fastDur } }
                  property real appear: root.dur > 0 ? 0 : 1
                  opacity: Math.min(1, appear)
                  scale: 0.4 + 0.6 * appear
                  Component.onCompleted: if (root.dur > 0) iconAppear.start()
                  NumberAnimation { id: iconAppear; target: appIcon; property: "appear"; to: 1; duration: root.dur; easing.type: Easing.OutBack }
                  Behavior on implicitWidth { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius > 0 ? Style.space(5) : 0
                    color: appIcon.focusedHere || appIcon.hovered ? Util.alpha(pill.textColor, 0.18) : "transparent"
                    Behavior on color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
                  }

                  Row {
                    id: iconRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Item {
                      width: root.iconPx
                      height: root.iconPx
                      scale: appIcon.hovered ? 1.12 : 1
                      Behavior on scale { enabled: root.fastDur > 0; NumberAnimation { duration: root.fastDur; easing.type: Easing.OutCubic } }

                      Image {
                        id: iconImage
                        anchors.fill: parent
                        source: appIcon.info.source
                        sourceSize.width: root.iconPx * 2
                        sourceSize.height: root.iconPx * 2
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        visible: status === Image.Ready
                        opacity: appIcon.dim
                        layer.enabled: root.cfg.iconStyle === "mono"
                        layer.effect: MultiEffect { saturation: -1.0 }
                      }

                      // Letter tile when no icon could be resolved.
                      Rectangle {
                        anchors.fill: parent
                        visible: iconImage.status !== Image.Ready
                        opacity: appIcon.dim
                        radius: Style.cornerRadius > 0 ? width * 0.25 : 0
                        color: Util.alpha(pill.textColor, 0.2)
                        Text {
                          anchors.centerIn: parent
                          text: String(appIcon.info.name || (appIcon.item ? appIcon.item.appId : "?")).charAt(0).toUpperCase()
                          color: pill.textColor
                          font.family: root.fontFamily
                          font.pixelSize: Math.round(root.iconPx * 0.62)
                          font.bold: true
                        }
                      }

                      // Attention dot for windows that asked to be looked at.
                      Rectangle {
                        visible: appIcon.agentState === "" && appIcon.item !== null && appIcon.item.addresses.some(function(a) { return root.isUrgent(a) })
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -Style.space(2)
                        anchors.topMargin: -Style.space(2)
                        width: Math.max(5, Math.round(root.iconPx * 0.36))
                        height: width
                        radius: width / 2
                        color: root.bar ? root.bar.urgent : Color.urgent
                        border.width: 1
                        border.color: root.bg
                      }

                      // Agent badge: spinner while working, pulse when it
                      // needs input, check mark when done.
                      Item {
                        id: agentBadge
                        visible: appIcon.agentState !== "" && appIcon.agentState !== "idle"
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -Style.space(3)
                        anchors.topMargin: -Style.space(2)
                        width: Math.max(8, Math.round(root.iconPx * 0.6))
                        height: width

                        Rectangle {
                          anchors.fill: parent
                          radius: width / 2
                          color: appIcon.agentState === "done" ? Color.accent
                            : appIcon.agentState === "waiting" ? (root.bar ? root.bar.urgent : Color.urgent)
                            : root.bg
                        }

                        Canvas {
                          id: spinner
                          anchors.fill: parent
                          anchors.margins: 1.5
                          visible: appIcon.agentState === "working"
                          onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.lineWidth = Math.max(1.5, width * 0.18)
                            ctx.lineCap = "round"
                            ctx.strokeStyle = root.fg
                            ctx.beginPath()
                            ctx.arc(width / 2, height / 2, width / 2 - ctx.lineWidth / 2, 0, Math.PI * 1.4)
                            ctx.stroke()
                          }
                          Connections {
                            target: root
                            function onFgChanged() { spinner.requestPaint() }
                          }
                          RotationAnimator on rotation {
                            running: spinner.visible
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                          }
                        }

                        Text {
                          anchors.centerIn: parent
                          visible: appIcon.agentState === "done" || appIcon.agentState === "waiting"
                          text: appIcon.agentState === "done" ? "\uf00c" : "!"
                          color: root.bg
                          font.family: root.fontFamily
                          font.pixelSize: Math.round(parent.width * 0.62)
                          font.bold: true
                        }

                        SequentialAnimation on scale {
                          running: appIcon.agentState === "waiting"
                          loops: Animation.Infinite
                          alwaysRunToEnd: true
                          NumberAnimation { from: 1; to: 1.3; duration: 520; easing.type: Easing.InOutSine }
                          NumberAnimation { from: 1.3; to: 1; duration: 520; easing.type: Easing.InOutSine }
                        }
                      }

                      // Window count for grouped apps.
                      Rectangle {
                        visible: appIcon.item !== null && appIcon.item.count > 1
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -Style.space(3)
                        anchors.bottomMargin: -Style.space(2)
                        width: Math.max(height, countText.implicitWidth + Style.space(4))
                        height: Math.round(root.iconPx * 0.6)
                        radius: height / 2
                        color: root.fg
                        Text {
                          id: countText
                          anchors.centerIn: parent
                          text: appIcon.item ? String(appIcon.item.count) : ""
                          color: root.bg
                          font.family: root.fontFamily
                          font.pixelSize: Math.max(7, Math.round(root.iconPx * 0.45))
                          font.bold: true
                        }
                      }
                    }

                    Text {
                      visible: appIcon.titleText !== ""
                      opacity: appIcon.dim
                      anchors.verticalCenter: parent.verticalCenter
                      text: appIcon.titleText
                      color: pill.textColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                  }

                  MouseArea {
                    id: iconMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: root.cfg.middleClickClose ? (Qt.LeftButton | Qt.MiddleButton) : Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                      if (!appIcon.item) return
                      if (mouse.button === Qt.MiddleButton) root.closeWindow(appIcon.item.address)
                      else root.activateItem(appIcon.item)
                    }
                    onWheel: function(wheel) { root.scrollBy(wheel.angleDelta.y || wheel.angleDelta.x) }
                    onContainsMouseChanged: {
                      root.highlightAddress = containsMouse && appIcon.item ? appIcon.item.address : ""
                      if (containsMouse && appIcon.item) {
                        var tip = appIcon.item.title || appIcon.info.name
                        if (appIcon.item.count > 1) tip = appIcon.info.name + " (" + appIcon.item.count + " windows)"
                        var agentText = { working: "Agent working", waiting: "Agent needs your input", done: "Agent finished" }[appIcon.agentState]
                        if (agentText) tip = agentText + " \u00b7 " + tip
                        if (!root.previewOpen) root.showTip(appIcon, tip)
                      } else {
                        root.hideTip(appIcon)
                      }
                    }
                  }
                }
              }

              // "+N" chip for windows beyond maxIcons.
              Text {
                visible: pill.iconData.overflow > 0
                text: "+" + pill.iconData.overflow
                color: pill.textColor
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
        }
      }
    }

    // Settings gear. Slides in while the pointer is over the widget (or
    // always / never, per settings); also lit while the panel is open.
    Item {
      id: gear
      readonly property bool shown: root.opened || root.cfg.settingsButton === "always"
        || (root.cfg.settingsButton === "hover" && root.widgetHovered)
      readonly property real size: root.pillThickness
      property real extent: shown ? size : 0
      Behavior on extent { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

      visible: extent > 0.5
      implicitWidth: root.vertical ? size : extent
      implicitHeight: root.vertical ? extent : size
      width: implicitWidth
      height: implicitHeight
      clip: true
      opacity: shown ? 1 : 0
      Behavior on opacity { enabled: root.dur > 0; NumberAnimation { duration: root.dur } }

      Rectangle {
        anchors.fill: parent
        radius: root.pillRadius
        color: root.opened ? root.activeFill() : gearMouse.containsMouse ? Util.alpha(root.fg, 0.12) : "transparent"
        Behavior on color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
      }

      Text {
        anchors.centerIn: parent
        text: "\uf013"
        color: root.opened ? root.activeText() : root.fg
        opacity: root.opened || gearMouse.containsMouse ? 1 : 0.6
        rotation: root.opened ? 90 : 0
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Behavior on rotation { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
      }

      MouseArea {
        id: gearMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
        onContainsMouseChanged: containsMouse ? root.showTip(gear, "Spaces settings") : root.hideTip(gear)
      }
    }
  }

  // ------------------------------------------------------------ preview card

  // Invisible stand-in for the hovered pill. The card anchors to it, so
  // animating it slides the card from pill to pill.
  Item {
    id: previewAnchor
    property bool animate: false
    visible: false

    Behavior on x { enabled: previewAnchor.animate && root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: previewAnchor.animate && root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
    onXChanged: if (preview.visible) preview.anchor.updateAnchor()
    onYChanged: if (preview.visible) preview.anchor.updateAnchor()
  }

  // Popup coordination stays out of it: a hover preview must never close
  // another widget's open panel.
  QtObject {
    id: previewBar
    readonly property string position: root.bar ? root.bar.position : "top"
    property var activePopout: null
    function requestPopout(owner) {}
    function releasePopout(owner) {}
  }

  PopupCard {
    id: preview
    anchorItem: previewAnchor
    bar: previewBar
    triggerMode: "hover"
    open: root.previewOpen

    readonly property var workspace: root.workspaceMap[root.previewWorkspaceId] || null
    readonly property var area: workspace ? workspace.area : null
    readonly property real mapWidth: Style.space(Model.previewWidth(root.cfg.previewSize))
    readonly property real mapHeight: area ? Math.round(mapWidth * area.height / area.width) : Math.round(mapWidth * 9 / 16)

    contentWidth: preview.fittedContentWidth(mapWidth + padding * 2 + Style.space(4))
    contentHeight: preview.fittedContentHeight(previewColumn.implicitHeight)

    onContainsMouseChanged: {
      if (containsMouse) previewHideTimer.stop()
      else previewHideTimer.restart()
    }

    // Popups get no compositor blur, so the card needs its own opaque fill.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -Math.max(0, preview.padding - Style.space(2))
      radius: Math.max(0, Style.cornerRadius - Style.space(2))
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.97)
    }

    Column {
      id: previewColumn
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)
      scale: preview.open ? 1 : 0.96
      transformOrigin: previewBar.position === "bottom" ? Item.Bottom : Item.Top
      Behavior on scale { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

      Item {
        width: preview.mapWidth
        implicitHeight: Math.max(previewTitle.implicitHeight, previewCount.implicitHeight)

        Text {
          id: previewTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Workspace " + (root.previewWorkspaceId === 10 ? "0" : root.previewWorkspaceId)
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          id: previewCount
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          readonly property int count: preview.workspace ? preview.workspace.windows.length : 0
          text: count + (count === 1 ? " WINDOW" : " WINDOWS")
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }
      }

      // The miniature. Rebuilt per workspace so switching pills crossfades.
      Item {
        id: miniature
        width: preview.mapWidth
        height: preview.mapHeight

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius > 0 ? Style.space(6) : 0
          color: Util.alpha(root.fg, 0.05)
          border.width: 1
          border.color: Util.alpha(root.fg, 0.08)
        }

        Loader {
          id: miniatureLoader
          anchors.fill: parent
          active: preview.visible && preview.workspace !== null
          sourceComponent: miniatureComponent
        }

        Connections {
          target: root
          function onPreviewWorkspaceIdChanged() {
            if (!preview.visible || root.dur === 0) return
            swapAnimation.restart()
          }
        }

        ParallelAnimation {
          id: swapAnimation
          NumberAnimation { target: miniatureLoader; property: "opacity"; from: 0.35; to: 1; duration: root.dur; easing.type: Easing.OutCubic }
          NumberAnimation { target: miniatureLoader; property: "scale"; from: 0.97; to: 1; duration: root.dur; easing.type: Easing.OutCubic }
        }
      }

      Text {
        id: previewFooter
        width: preview.mapWidth
        readonly property var hovered: root.windowByAddress(root.highlightAddress)
        text: hovered ? hovered.title : "Click a window to jump to it"
        color: root.fg
        opacity: hovered ? 0.9 : 0.5
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  function windowByAddress(address) {
    if (!address || !preview.workspace) return null
    var windows = preview.workspace.windows
    for (var i = 0; i < windows.length; i++) if (windows[i].address === address) return windows[i]
    return null
  }

  Component {
    id: miniatureComponent

    Item {
      id: mini
      readonly property var workspace: preview.workspace
      readonly property var layout: workspace
        ? Model.previewLayout(workspace.windows, workspace.area, width, height) : []
      readonly property var rects: {
        var map = ({})
        for (var i = 0; i < layout.length; i++) map[layout[i].address] = layout[i]
        return map
      }

      Repeater {
        model: ScriptModel { values: mini.layout.map(function(r) { return r.address }) }

        delegate: Item {
          id: thumb
          required property var modelData
          readonly property var rect: mini.rects[modelData] || null
          readonly property var win: root.windowByAddress(modelData)
          readonly property bool highlighted: root.highlightAddress === modelData || thumbMouse.containsMouse
          readonly property real inset: Style.space(2)

          x: rect ? rect.x + inset : 0
          y: rect ? rect.y + inset : 0
          width: rect ? Math.max(2, rect.width - inset * 2) : 0
          height: rect ? Math.max(2, rect.height - inset * 2) : 0
          z: rect && rect.floating ? 1 : 0

          Behavior on x { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
          Behavior on y { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
          Behavior on width { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
          Behavior on height { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

          ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: thumb.win ? thumb.win.toplevel : null
            live: root.cfg.previewLive
            constraintSize: Qt.size(Math.round(thumb.width * 2), Math.round(thumb.height * 2))
            opacity: hasContent ? 1 : 0
            Behavior on opacity { enabled: root.fastDur > 0; NumberAnimation { duration: root.fastDur } }
          }

          // Placeholder until the first frame arrives.
          Rectangle {
            anchors.fill: parent
            visible: !capture.hasContent
            color: Util.alpha(root.fg, 0.08)
          }

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: thumb.highlighted ? 2 : 1
            border.color: thumb.highlighted ? Color.accent : Util.alpha(root.fg, 0.18)
            Behavior on border.color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
          }

          // App badge in the corner, so small thumbnails stay identifiable.
          Rectangle {
            readonly property var info: thumb.win ? root.appInfo(thumb.win.appId) : null
            visible: info !== null && thumb.width > 28 && thumb.height > 22
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(4)
            width: Style.space(20)
            height: width
            radius: Style.cornerRadius > 0 ? Style.space(5) : 0
            color: Util.alpha(root.bg, 0.85)

            Image {
              anchors.centerIn: parent
              width: Style.space(14)
              height: width
              source: parent.info ? parent.info.source : ""
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }
          }

          MouseArea {
            id: thumbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
              if (containsMouse) root.highlightAddress = thumb.modelData
              else if (root.highlightAddress === thumb.modelData) root.highlightAddress = ""
            }
            onClicked: {
              root.focusWindow(thumb.modelData)
              root.hidePreview()
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ settings panel

  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(form.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: form.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: form
          width: parent.width
          spacing: Style.space(14)

          Column {
            width: parent.width
            spacing: Style.space(2)
            Text {
              text: "Spaces"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: "SEE WHAT RUNS ON EVERY WORKSPACE"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }

          PanelSeparator { foreground: root.fg }

          // ---- App icons
          SectionTitle { text: "APP ICONS" }

          ToggleSetting {
            label: "Show app icons"
            description: root.cfg.showIcons ? "Icons of open apps appear in workspace pills" : "Hidden: workspaces show numbers only"
            key: "showIcons"
          }

          ChoiceSetting {
            visible: root.cfg.showIcons
            title: "SHOW ICONS ON"
            key: "showApps"
            options: [
              { value: "all", label: "Always" },
              { value: "active", label: "Active" },
              { value: "hover", label: "Active + hover" },
              { value: "hoverOnly", label: "Hover" }
            ]
          }

          ChoiceSetting {
            visible: root.cfg.showIcons
            title: "ICON STYLE"
            key: "iconStyle"
            options: [
              { value: "color", label: "Color" },
              { value: "mono", label: "Monochrome" }
            ]
          }

          SliderSetting { visible: root.cfg.showIcons; title: "ICON SIZE"; key: "iconSize"; minimum: 12; maximum: 24; suffix: "px" }
          SliderSetting { visible: root.cfg.showIcons; title: "MAX ICONS PER WORKSPACE"; key: "maxIcons"; minimum: 1; maximum: 20 }

          ToggleSetting { visible: root.cfg.showIcons; label: "Group windows by app"; description: "One icon per app with a window count"; key: "groupApps" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Dim unfocused windows"; description: "On the active workspace"; key: "dimUnfocused" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Show focused window title"; description: "Next to its icon"; key: "focusedTitle" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Agent status"; description: "Badges on terminals running coding agents"; key: "agentStatus" }

          PanelSeparator { foreground: root.fg }

          // ---- Previews
          SectionTitle { text: "PREVIEWS" }

          ToggleSetting {
            label: "Workspace previews"
            description: "Hover another workspace to see a live miniature of it"
            key: "previews"
          }

          ChoiceSetting {
            visible: root.cfg.previews
            title: "PREVIEW SIZE"
            key: "previewSize"
            options: [
              { value: "small", label: "Small" },
              { value: "medium", label: "Medium" },
              { value: "large", label: "Large" }
            ]
          }

          ToggleSetting {
            visible: root.cfg.previews
            label: "Live video"
            description: "Off shows a still frame and saves power"
            key: "previewLive"
          }

          PanelSeparator { foreground: root.fg }

          // ---- Appearance
          SectionTitle { text: "APPEARANCE" }

          ChoiceSetting {
            title: "ACTIVE WORKSPACE"
            key: "activeStyle"
            options: [
              { value: "subtle", label: "Subtle" },
              { value: "solid", label: "Solid" },
              { value: "accent", label: "Accent" }
            ]
          }

          ChoiceSetting {
            title: "WORKSPACE LABEL"
            key: "labelStyle"
            options: [
              { value: "number", label: "Number" },
              { value: "glyph", label: "Glyph" },
              { value: "none", label: "None" }
            ]
          }

          ChoiceSetting {
            title: "DENSITY"
            key: "density"
            options: [
              { value: "compact", label: "Compact" },
              { value: "normal", label: "Normal" },
              { value: "roomy", label: "Roomy" }
            ]
          }

          ChoiceSetting {
            title: "SETTINGS BUTTON"
            key: "settingsButton"
            options: [
              { value: "hover", label: "On hover" },
              { value: "always", label: "Always" },
              { value: "never", label: "Hidden" }
            ]
          }

          ToggleSetting { label: "Highlight urgent windows"; description: "Pulse workspaces with windows asking for attention"; key: "urgentHighlight" }
          ToggleSetting { label: "Tooltips"; description: "Window titles on hover"; key: "tooltips" }

          PanelSeparator { foreground: root.fg }

          // ---- Workspaces
          SectionTitle { text: "WORKSPACES" }

          SliderSetting { title: "ALWAYS SHOW WORKSPACES"; key: "persistentWorkspaces"; minimum: 0; maximum: 10 }
          ToggleSetting { label: "Hide empty workspaces"; key: "hideEmpty" }
          ToggleSetting { label: "Only this monitor's workspaces"; key: "perMonitor" }

          PanelSeparator { foreground: root.fg }

          // ---- Behavior
          SectionTitle { text: "BEHAVIOR" }

          ChoiceSetting {
            title: "CLICKING THE ACTIVE WORKSPACE"
            key: "activeClick"
            options: [
              { value: "none", label: "Does nothing" },
              { value: "previous", label: "Goes back" }
            ]
          }

          ToggleSetting { label: "Scroll to switch workspaces"; key: "scrollSwitch" }
          ToggleSetting { label: "Middle-click icon closes window"; key: "middleClickClose" }

          PanelSeparator { foreground: root.fg }

          // ---- Animation
          SectionTitle { text: "ANIMATION" }

          ToggleSetting { label: "Animations"; key: "animations" }

          ChoiceSetting {
            visible: root.cfg.animations
            title: "SPEED"
            key: "animationSpeed"
            options: [
              { value: "slow", label: "Slow" },
              { value: "normal", label: "Normal" },
              { value: "fast", label: "Fast" }
            ]
          }

          PanelSeparator { foreground: root.fg }

          Button {
            text: "Reset to defaults"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.resetSettings()
          }
        }
      }
    }
  }

  component SectionTitle: Text {
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  component ChoiceSetting: Column {
    property string title: ""
    property string key: ""
    property var options: []

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    PanelSectionHeader {
      text: parent.title
      foreground: root.fg
      fontFamily: root.fontFamily
    }

    ButtonGroup {
      options: parent.options
      value: String(root.cfg[parent.key])
      foreground: root.fg
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      focusable: false
      onChanged: function(value) {
        var delta = ({})
        delta[parent.key] = value
        root.applySetting(delta)
      }
    }
  }

  component SliderSetting: Column {
    id: sliderSetting
    property string title: ""
    property string key: ""
    property int minimum: 0
    property int maximum: 10
    property string suffix: ""

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: sliderHeader.implicitHeight
      PanelSectionHeader {
        id: sliderHeader
        text: sliderSetting.title
        foreground: root.fg
        fontFamily: root.fontFamily
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(slider.liveValue) + sliderSetting.suffix
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: sliderSetting.minimum
      maximum: sliderSetting.maximum
      step: 1
      integer: true
      value: Number(root.cfg[sliderSetting.key])
      onReleased: function(value) {
        var delta = ({})
        delta[sliderSetting.key] = Math.round(value)
        root.applySetting(delta)
      }
    }
  }

  component ToggleSetting: Toggle {
    property string key: ""
    width: parent ? parent.width : 0
    checked: root.cfg[key] === true
    foreground: root.fg
    fontFamily: root.fontFamily
    onClicked: {
      var delta = ({})
      delta[key] = !checked
      root.applySetting(delta)
    }
  }
}
