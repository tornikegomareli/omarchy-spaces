import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Hyprland
import "Model.js" as Model
Window {
  visible: true
  // Grows with the widget so every pill stays inside the window, even on a long vertical bar.
  width: Math.max(900, widget.implicitWidth); height: Math.max(100, widget.implicitHeight)
  // Stands in for the bar; run() records commands instead of dispatching them.
  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 32
    readonly property string position: vertical ? "left" : "top"
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
    width: implicitWidth; height: implicitHeight
    settings: ({settingsButton: "hover", animations: false, persistentWorkspaces: 2, previews: false})
  }
  TestCase {
    id: checks
    when: false
    function find(item, name) {
      if (item.objectName === name) return item
      for (var child of item.children) {
        var found = find(child, name)
        if (found) return found
      }
      return null
    }
    function collect(item, accept, found) {
      if (accept(item)) found.push(item)
      for (var child of item.children) collect(child, accept, found)
      return found
    }
    function pillOf(item) {
      while (item && (item.workspaceId === undefined || item.showApps === undefined)) item = item.parent
      return item
    }
    function check(condition, message) {
      if (!condition) throw new Error(message)
    }
    // Commands the widget sends to the bar while `action` runs.
    function sentBy(action) {
      fakeBar.commands = []
      action()
      var sent = JSON.stringify(fakeBar.commands)
      fakeBar.commands = []
      return sent
    }
    // The point `edge` px across the bar, inside the pill's leading padding along it. The padding
    // holds no app icons, even when a small bar lets them overflow, so the pill takes the input.
    function across(item, edge) {
      var pos = item.mapToItem(widget, 0, 0)
      return fakeBar.vertical ? Qt.point(edge, pos.y + item.pad / 2) : Qt.point(pos.x + item.pad / 2, edge)
    }
    function run() {
      var gear = find(widget, "spacesSettingsGear")
      if (!gear) throw new Error("Missing settings gear")
      var x = gear.x, y = gear.y, width = gear.width
      mouseMove(widget, widget.width - 2, widget.height / 2)
      wait(100)
      widget.applySetting({persistentWorkspaces: 10, showApps: "all"})
      wait(100)
      if (gear.x !== x || gear.y !== y || gear.width !== width)
        throw new Error("Gear moved when workspaces expanded")
      mouseClick(gear, gear.width / 2, gear.height / 2)
      wait(100)
      if (!widget.opened) throw new Error("Gear did not open settings")
      widget.close()
      widget.applySetting({settingsButton: "never"})
      wait(50)
      if (gear.visible) throw new Error("Hidden gear still visible")
      console.log("PASS: stable gear position, click opens settings, hidden mode")
      workspaceEdges()
      appIcons()
      previousWindow()
      crossWorkspaceFocusHistory()
      specialWorkspaceHistory()
    }
    function previousWindow() {
      var current = String(widget.activeWindowAddress()).replace(/^0x/, "").toLowerCase()
      var other = widget.liveWindowAddresses().filter(function(address) { return address !== current })[0]
      if (!current || !other) {
        console.log("SKIP: need two live windows for the previous-window check")
        return
      }
      widget.settings = Object.assign({}, widget.settings, {activeIconClick: "previous"})
      widget.windowFocusHistory = [current, other]
      var icon = {address: current, addresses: [current], focused: true}
      var sent = sentBy(function() { widget.activateItem(icon) })
      check(sent.indexOf("address:0x" + other) !== -1,
        "Focused icon did not target the previous live window: " + sent)
      check(sent.indexOf("alter_zorder") !== -1 && sent.indexOf("alterzorder") !== -1
        && sent.indexOf("top,address:0x" + other) !== -1,
        "Previous window was not raised using the target address: " + sent)
      icon.focused = false
      sent = sentBy(function() { widget.activateItem(icon) })
      check(sent.indexOf("address:0x" + current) !== -1,
        "Unfocused icon did not target its own window: " + sent)
      check(sent.indexOf("top,address:0x" + current) !== -1,
        "Icon's window was not raised using the target address: " + sent)
      check(sent.indexOf("cursor.move") === -1, "Pointer restored while movePointer is on: " + sent)
      widget.settings = Object.assign({}, widget.settings, {movePointer: false})
      sent = sentBy(function() { widget.activateItem(icon) })
      check(sent.indexOf("hyprctl eval") !== -1 && sent.indexOf("get_cursor_pos") < sent.indexOf("cursor.move")
        && sent.indexOf("|| (hyprctl dispatch") !== -1 && sent.indexOf("address:0x" + current) !== -1,
        "movePointer off did not focus in one Lua call that restores the pointer: " + sent)
      console.log("PASS: focused icon returns to previous live window; unfocused icon focuses its own window; pointer can stay")
    }
    function crossWorkspaceFocusHistory() {
      var current = widget.backgroundWindowAddress()
      var others = widget.liveWindowAddresses().filter(function(address) { return address !== current })
      if (!current || others.length < 2) {
        console.log("SKIP: need three live windows for the intermediate-focus check")
        return
      }
      var target = others[0], intermediate = others[1]
      widget.windowFocusHistory = [current, intermediate]
      sentBy(function() { widget.focusWindow(target) })
      check(widget.pendingWindowFocus === target, "Window focus request was not tracked")
      widget.rememberFocusedWindow("")
      widget.rememberFocusedWindow(intermediate)
      check(JSON.stringify(widget.windowFocusHistory) === JSON.stringify([current, intermediate]),
        "Workspace's intermediate focus replaced the origin")
      widget.rememberFocusedWindow(target)
      check(widget.pendingWindowFocus === "", "Successful focus did not finish the request immediately")
      var icon = {address: target, addresses: [target], focused: true}
      check(Model.iconClickTarget(icon, "previous", widget.windowFocusHistory, widget.liveWindowAddresses()) === current,
        "Focused icon would return inside the destination workspace instead of to the origin")
      widget.rememberFocusedWindow(intermediate)
      check(widget.windowFocusHistory[0] === intermediate && widget.windowFocusHistory[1] === target,
        "Normal focus changes stopped updating history after a successful request")

      // A newer click supersedes an outstanding request.
      widget.windowFocusHistory = [current]
      sentBy(function() { widget.focusWindow(target); widget.focusWindow(intermediate) })
      widget.rememberFocusedWindow(target)
      check(widget.windowFocusHistory[0] === current, "An older focus request polluted the new request's history")
      widget.rememberFocusedWindow(intermediate)
      check(JSON.stringify(widget.windowFocusHistory) === JSON.stringify([intermediate, current]),
        "Newer focus request lost its origin")

      // Failed dispatches and targets that disappear must not freeze history.
      sentBy(function() { widget.focusWindow(target) })
      wait(1100)
      check(widget.pendingWindowFocus === "", "Failed focus request did not expire")
      widget.rememberFocusedWindow(intermediate)
      check(widget.windowFocusHistory[0] === intermediate, "History stayed paused after a failed request")
      sentBy(function() { widget.focusWindow("deadbeef") })
      widget.rememberFocusedWindow(target)
      check(widget.pendingWindowFocus === "" && widget.windowFocusHistory[0] === target,
        "A vanished target left history paused")
      widget.rememberFocusedWindow()
      console.log("PASS: intermediate workspace focus, newer clicks, normal focus, failed requests, and vanished targets")
    }
    function specialWorkspaceHistory() {
      var special = Hyprland.toplevels.values.filter(function(window) {
        return window.workspace && window.workspace.id < 0
      }).map(function(window) { return Model.normalizeAddress(window.address) })
      var current = widget.backgroundWindowAddress()
      var live = widget.liveWindowAddresses()
      var target = live.filter(function(address) { return address !== current })[0]
      if (!special.length || live.indexOf(current) === -1 || !target) {
        console.log("SKIP: need a special-workspace window and two regular windows for the overlay check")
        return
      }
      widget.windowFocusHistory = [current]
      sentBy(function() { widget.focusWindow(target) })
      for (var address of special) {
        check(live.indexOf(address) === -1, "Special workspace became a previous-window target")
        widget.rememberFocusedWindow(address)
        check(widget.pendingWindowFocus === target && widget.windowFocusHistory[0] === current,
          "Restoring an overlay interrupted the background window focus request")
      }
      widget.rememberFocusedWindow(target)
      check(widget.pendingWindowFocus === ""
        && JSON.stringify(widget.windowFocusHistory) === JSON.stringify([target, current]),
        "Background focus completion lost the regular window's return target")
      widget.rememberFocusedWindow()
      console.log("PASS: special workspaces stay out of history and preserve pending background focus")
    }
    function workspaceEdges() {
      var workspace = widget.workspaceIds.filter(function(id) { return id !== widget.currentWorkspaceId })[0]
      check(workspace !== undefined, "No inactive workspace among " + JSON.stringify(widget.workspaceIds))
      var pill = null
      for (var size of [32, 17]) for (var vertical of [false, true]) {
        fakeBar.barSize = size
        fakeBar.vertical = vertical
        wait(100)
        var bar = (vertical ? "vertical " : "horizontal ") + size + "px bar"
        pill = collect(widget, function(item) { return item.workspaceId === workspace && item.showApps !== undefined }, [])[0]
        check(pill, "Missing workspace " + workspace + " in the " + bar)
        check(!pill.active, "Workspace " + workspace + " is no longer inactive in the " + bar)
        var pos = pill.mapToItem(widget, 0, 0)
        var inset = vertical ? pos.x : pos.y
        check(inset > 0 && inset + (vertical ? pill.width : pill.height) <= size, "Pill not inset in the " + bar)
        var click = sentBy(function() { widget.clickWorkspace(workspace) })
        check(click !== "[]", "Workspace " + workspace + " has no click command")
        var step = sentBy(function() { widget.scrollBy(-120) }) === "[]" ? 120 : -120
        var wheel = sentBy(function() { widget.scrollBy(step) })
        for (var edge of [0, size - 1]) {
          var p = across(pill, edge)
          mouseMove(widget, p.x, p.y)
          check(pill.hovered, "Workspace not hovered " + edge + "px across the " + bar)
          var clicked = sentBy(function() { mouseClick(widget, p.x, p.y) })
          check(clicked === click, "Click " + edge + "px across the " + bar + " did not focus workspace " + workspace
            + " once: sent " + clicked + ", expected " + click)
          var wheeled = sentBy(function() { mouseWheel(widget, p.x, p.y, 0, step) })
          check(wheeled === wheel, "Wheel " + edge + "px across the " + bar + " did not step once: sent "
            + wheeled + ", expected " + wheel)
        }
        p = across(pill, size)
        mouseMove(widget, p.x, p.y)
        check(!pill.hovered, "Workspace hovered past the " + bar)
      }
      p = across(pill, 0)
      var rightClicked = sentBy(function() { mouseClick(widget, p.x, p.y, Qt.RightButton) })
      check(rightClicked === "[]" && widget.opened,
        "Right-click on the bar edge did not open settings: sent " + rightClicked + ", opened " + widget.opened)
      widget.close()
      console.log("PASS: workspace hover, click, and wheel span the full bar thickness; right-click still opens settings")
    }
    function appIcons() {
      fakeBar.barSize = 32
      fakeBar.vertical = false
      wait(100)
      // Icons on another workspace come first: there a stray pill click would also send a command.
      var icons = collect(widget, function(item) { return item.agentState !== undefined && !!item.item }, [])
      icons.sort(function(a, b) { return pillOf(a).active - pillOf(b).active })
      var icon = icons[0]
      if (!icon) {
        console.log("SKIP: no app icons on this desktop")
        return
      }
      var p = icon.mapToItem(widget, icon.width / 2, icon.height / 2)
      mouseMove(widget, p.x, p.y)
      check(icon.hovered && pillOf(icon).hovered, "Icon hover did not register")
      // Clicking the active pill sends nothing by default, which would hide a stray pill click
      // there. Going back to a previous workspace makes every pill click send a command.
      var activeClick = widget.cfg.activeClick, previous = widget.previousWorkspaceId
      var other = widget.workspaceIds.filter(function(id) { return id !== widget.currentWorkspaceId })[0]
      check(other !== undefined, "No workspace besides " + widget.currentWorkspaceId + " to go back to")
      widget.applySetting({activeClick: "previous"})
      widget.previousWorkspaceId = other
      wait(50)
      var focus = sentBy(function() { widget.activateItem(icon.item) })
      var stray = sentBy(function() { widget.clickWorkspace(pillOf(icon).workspaceId) })
      check(focus !== "[]" && stray !== "[]" && stray !== focus,
        "Icon and pill clicks are indistinguishable: icon " + focus + ", pill " + stray)
      var clicked = sentBy(function() { mouseClick(widget, p.x, p.y) })
      widget.applySetting({activeClick: activeClick})
      widget.previousWorkspaceId = previous
      check(clicked === focus, "Icon click did not focus only its window: sent " + clicked + ", expected " + focus)
      console.log("PASS: icon hover and click take precedence over the workspace")
    }
  }
  Timer {
    interval: 500; running: true
    onTriggered: {
      try { checks.run(); Qt.quit() }
      catch(error) { console.error(error); Qt.exit(1) }
    }
  }
}
