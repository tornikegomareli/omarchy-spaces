import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model

FloatingWindow {
  id: controller
  title: "Spaces minimized window regression controller"
  visible: true
  implicitWidth: 1000
  implicitHeight: 80
  color: "#202020"

  FloatingWindow {
    id: subject
    title: "Spaces minimized window regression subject"
    visible: false
    implicitWidth: 800
    implicitHeight: 500
    color: "#426a9f"
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 32
    property string position: "bottom"
    property color barForeground: "white"
    property color background: "black"
    property color urgent: "red"
    property string fontFamily: "sans-serif"
    property var activePopout: null
    property var commands: []
    function run(command) { commands = commands.concat([command]) }
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { activePopout = null }
  }
  Spaces {
    id: widget
    bar: fakeBar
    width: implicitWidth
    height: implicitHeight
    settings: ({animations: false, previews: true, previewLive: true,
      groupApps: false, maxIcons: 20, hideEmpty: true})
  }
  Process {
    id: command
    property int result: -1
    onExited: function(code) { result = code }
  }
  TestCase {
    id: checks
    when: false
    function check(condition, message) {
      if (!condition) throw new Error(message)
    }
    function execute(text) {
      command.result = -1
      command.command = ["bash", "-c", text]
      command.running = true
      for (var i = 0; i < 250 && command.result === -1; i++) wait(20)
      check(command.result === 0, "Command failed: " + text)
    }
    function settle() {
      Hyprland.refreshToplevels()
      wait(300)
      widget.revision++
      wait(50)
    }
    function collect(item, accept, out) {
      if (accept(item)) out.push(item)
      for (var child of item.children) collect(child, accept, out)
      return out
    }
    function run() {
      subject.visible = true
      settle()
      var window = Hyprland.toplevels.values.filter(function(w) {
        return w.title === subject.title
      })[0]
      check(window, "Subject was not mapped")
      var key = Model.normalizeAddress(window.address)
      var target = "address:0x" + key
      execute("hyprctl dispatch 'hl.dsp.window.float({ action = \"on\", window = \"" + target + "\" })'")
      execute("hyprctl dispatch 'hl.dsp.window.move({ x = 310, y = 180, window = \"" + target + "\" })'")
      settle()
      var placement = widget.windowPlacements[key]
      check(placement && placement.workspaceId > 0 && placement.floating, "Subject must start on a floating workspace")
      var origin = placement.workspaceId
      var geometry = JSON.stringify([placement.at, placement.size])
      var workspace = widget.workspaceMap[origin]
      var before = Model.previewLayout(workspace.windows, workspace.area, 260, 143).filter(function(r) {
        return Model.normalizeAddress(r.address) === key
      })[0]
      execute("omarchy-hyprland-window-minimize 0x" + key)
      settle()
      check(window.workspace.name === "special:minimized", "Subject was not minimized; run on a floating workspace")
      placement = widget.windowPlacements[key]
      check(placement && placement.minimized && placement.workspaceId === origin, "Minimized window lost its original workspace")
      check(JSON.stringify([placement.at, placement.size]) === geometry, "Minimized geometry changed")
      workspace = widget.workspaceMap[origin]
      var icons = Model.iconItems(workspace.windows, false, 20).items
      check(icons.some(function(w) { return Model.normalizeAddress(w.address) === key }), "Minimized icon disappeared")
      check(widget.workspaceIds.indexOf(origin) !== -1, "Minimized workspace was hidden as empty")
      var after = Model.previewLayout(workspace.windows, workspace.area, 260, 143).filter(function(r) {
        return Model.normalizeAddress(r.address) === key
      })[0]
      check(JSON.stringify(before) === JSON.stringify(after), "Minimized preview moved or resized")
      console.log("PASS: real minimize keeps icon, workspace occupancy, and exact preview geometry")
      check(widget.peek(origin), "Could not open minimized preview")
      wait(900)
      var card = null
      for (var resource of widget.resources) {
        if (resource.mapWidth !== undefined && resource.triggerMode === "hover") card = resource
      }
      check(card && card.visible, "Minimized preview card did not open")
      var thumbs = []
      for (var content of card.contentItem) collect(content, function(item) {
        return item.win !== undefined && item.win && Model.normalizeAddress(item.win.address) === key
      }, thumbs)
      var thumb = thumbs[0]
      check(thumb, "Missing minimized thumbnail")
      var captures = collect(thumb, function(item) { return item.hasContent !== undefined }, [])
      check(captures.some(function(item) { return item.hasContent }), "Minimized window has no preview image")
      console.log("PASS: minimized thumbnail contains a captured window image")
      widget.hidePreview()

      // Startup recovery uses the compositor's origin tag and retained geometry.
      widget.windowPlacements = Model.windowPlacements(widget.windowSnapshots, {})
      placement = widget.windowPlacements[key]
      check(placement && placement.minimized && placement.workspaceId === origin, "Reload lost the minimized window")
      check(JSON.stringify([placement.at, placement.size]) === geometry, "Reload lost minimized geometry")
      console.log("PASS: startup recovers a window that was already minimized")

      fakeBar.commands = []
      var icon = Model.iconItems([placement], false, 20).items[0]
      widget.activateItem(icon)
      check(fakeBar.commands.length === 1, "Minimized icon did not dispatch one restore command")
      execute(fakeBar.commands[0])
      settle()
      check(window.workspace.id === origin, "Click did not restore the original workspace")
      check(!widget.windowPlacements[key].minimized, "Restored window is still marked minimized")
      check(JSON.stringify([widget.windowPlacements[key].at, widget.windowPlacements[key].size]) === geometry,
        "Restored window geometry changed")
      console.log("PASS: clicking minimized icon restores its window on the original workspace")

      // Moving a focused window may not refresh Quickshell's IPC geometry.
      execute("hyprctl dispatch 'hl.dsp.window.move({ x = 430, y = 230, window = \"" + target + "\" })'")
      execute("omarchy-hyprland-window-minimize 0x" + key)
      settle()
      check(JSON.stringify(widget.windowPlacements[key].at) === JSON.stringify([430, 230]),
        "Minimize after moving retained stale geometry: " + JSON.stringify(widget.windowPlacements[key].at))
      console.log("PASS: minimizing immediately after a move uses the latest position")
      execute("hyprctl dispatch 'hl.dsp.window.close({ window = \"" + target + "\" })'")
      settle()
      check(!widget.windowPlacements[key], "Closed window remained cached: " + JSON.stringify(widget.windowSnapshots.map(function(w) {
        return { address: w.address, title: w.title, workspaceId: w.workspaceId }
      })))
      console.log("PASS: closed minimized/restored windows leave no stale icon")
    }
  }
  Timer {
    interval: 700
    running: true
    onTriggered: {
      try { checks.run(); Qt.quit() }
      catch (error) { console.error(error); Qt.exit(1) }
    }
  }
}
