import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import "Model.js" as Model
FloatingWindow {
  visible: true
  // Grows with the widget so every pill stays inside the window, even on a long vertical bar.
  implicitWidth: Math.max(900, widget.implicitWidth); implicitHeight: Math.max(100, widget.implicitHeight)
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
      workspacePreviews()
      previewHandoff()
    }
    function previewHandoff() {
      widget.applySetting({previews: true, previewActive: true, groupApps: true, previewLive: false})
      wait(50)
      var icons = collect(widget, function(item) {
        return item.agentState !== undefined && !!item.item
          && pillOf(item).workspace.windows.filter(function(window) { return window.floating }).length > 1
          && pillOf(item).workspace.windows.some(function(window) {
            return window.address === item.item.address && window.floating
          })
      }, [])
      var single = icons.filter(function(icon) { return icon.item.count === 1 })[0]
      var grouped = icons.filter(function(icon) {
        return pillOf(icon).workspace.windows.filter(function(window) {
          return window.floating && icon.item.addresses.indexOf(window.address) !== -1
        }).length > 1
      })[0]
      if (!single && !grouped) {
        console.log("SKIP: need floating windows for the preview handoff check")
        return
      }
      for (var icon of [single, grouped].filter(function(item) { return !!item })) {
        widget.hidePreview()
        mouseMove(widget, widget.width - 1, widget.height + 20)
        wait(50)
        var p = icon.mapToItem(widget, icon.width / 2, icon.height / 2)
        mouseMove(widget, p.x, p.y)
        wait(450)
        check(widget.previewOpen, "Floating window preview did not open: icon=" + icon.hovered
          + ", pill=" + pillOf(icon).hovered + ", workspace=" + pillOf(icon).workspaceId
          + ", preview=" + widget.previewWorkspaceId + ", wanted=" + widget.previewWanted)
        var selected = icon.item.address
        var group = JSON.stringify(icon.item.addresses)
        fakeBar.commands = []
        // Leave the icon through the gap before entering the popup.
        mouseMove(widget, p.x, widget.height + 2)
        check(widget.highlightAddress === selected && JSON.stringify(widget.highlightAddresses) === group,
          "Leaving the app icon dropped its preview selection before the pointer reached the popup")

        var card = null
        for (var resource of widget.resources) {
          if (resource.mapWidth !== undefined && resource.triggerMode === "hover") card = resource
        }
        check(card, "Missing workspace preview card")
        var thumbs = []
        for (var content of card.contentItem) collect(content, function(item) {
          return item.rect !== undefined && item.highlighted !== undefined
        }, thumbs)
        var primary = thumbs.filter(function(thumb) { return thumb.modelData === selected })[0]
        check(primary, "Missing selected thumbnail " + selected + ": "
          + JSON.stringify(thumbs.map(function(thumb) { return thumb.modelData }))
          + ", visible=" + card.visible + ", contents=" + card.contentItem.length)
        var siblings = thumbs.filter(function(thumb) {
          return thumb !== primary && thumb.rect.floating
            && (icon.item.count === 1 || icon.item.addresses.indexOf(thumb.modelData) !== -1)
        })
        var sibling = siblings[siblings.length - 1]
        check(sibling, "Need another floating thumbnail for the overlap check")
        var rear = sibling
        // Make the overlap deterministic while keeping the real delegates and hit targets.
        for (var thumb of thumbs) thumb.visible = thumb === primary || thumb === sibling
        primary.x = 10; primary.y = 10; primary.width = 100; primary.height = 80
        sibling.x = 60; sibling.y = 10; sibling.width = 100; sibling.height = 80
        check(primary.z > sibling.z, "Selected window is not above the overlapping thumbnail")
        mouseMove(primary, 75, 40)
        wait(250)
        check(card.containsMouse && widget.previewOpen && widget.highlightAddress === selected,
          "Selected thumbnail did not stay reachable after entering the preview")
        check(fakeBar.commands.length === 0, "Hovering the preview changed actual window focus or stacking")
        if (icon.item.count > 1) {
          mouseMove(sibling, 90, 40)
          wait(20)
          check(widget.highlightAddress === sibling.modelData && sibling.z > primary.z,
            "Hovering another window in the app group did not bring its thumbnail forward")
          mouseMove(sibling, 25, 40)
          wait(20)
          check(widget.highlightAddress === sibling.modelData && sibling.z > primary.z,
            "Moving into the grouped windows' overlap changed the selected window")
          rear = primary
          primary = sibling
        }
        selected = primary.modelData
        mouseMove(primary.parent, 2, 2)
        wait(20)
        check(widget.highlightAddress === selected && primary.z > rear.z,
          "Leaving a thumbnail dropped it behind another window")
        mouseMove(primary, 25, 40)
        var clicked = sentBy(function() { mouseClick(primary, 25, 40) })
        check(clicked.indexOf("address:0x" + Model.normalizeAddress(selected)) !== -1,
          "Preview click did not select the window that stayed in front")
        check(!widget.previewOpen && widget.highlightAddress === "" && widget.highlightAddresses.length === 0,
          "Closing the preview did not clear the retained selection")
        console.log("PASS: icon-to-preview handoff, stable overlap hit target, and click for "
          + (icon.item.count > 1 ? "grouped floating windows" : "a single floating window"))
      }
      if (!grouped) console.log("SKIP: need multiple floating windows of one app for grouped handoff")
      icon = single || grouped
      mouseMove(widget, widget.width - 1, widget.height + 20)
      wait(250)
      p = icon.mapToItem(widget, icon.width / 2, icon.height / 2)
      mouseMove(widget, p.x, p.y)
      wait(450)
      var other = widget.workspaceIds.filter(function(id) {
        return id !== pillOf(icon).workspaceId && widget.workspaceMap[id] && widget.workspaceMap[id].windows.length
      })[0]
      if (other !== undefined) {
        check(widget.peek(other), "Could not open another workspace preview")
        check(widget.highlightAddress === "" && widget.highlightAddresses.length === 0,
          "Another workspace inherited the previous preview's selection")
      }
      widget.hidePreview()
      mouseMove(widget, widget.width - 1, widget.height + 20)
      wait(250)
      mouseMove(widget, p.x, p.y)
      wait(450)
      check(widget.previewOpen && widget.highlightAddress === icon.item.address,
        "Reopening a preview lost the icon's initial selection")
      mouseMove(widget, p.x, widget.height + 2)
      wait(250)
      check(!widget.previewOpen && widget.highlightAddress === "" && widget.highlightAddresses.length === 0,
        "Leaving the icon and preview did not close it and clear the selection")
      console.log("PASS: workspace changes, reopening, and hover dismissal clear the selection at the right time")
    }
    function workspacePreviews() {
      var activePill = collect(widget, function(item) {
        return item.workspaceId === widget.currentWorkspaceId && item.showApps !== undefined
      }, [])[0]
      check(activePill && activePill.occupied, "Need an occupied current workspace for the preview check")
      var icon = collect(activePill, function(item) { return item.agentState !== undefined && !!item.item }, [])[0]
      check(icon, "Need a current-workspace app icon for the preview check")
      var outside = Qt.point(widget.width - 1, widget.height + 20)
      mouseMove(widget, outside.x, outside.y)
      widget.applySetting({previews: true, previewActive: false})
      widget.hidePreview()
      var p = icon.mapToItem(widget, icon.width / 2, icon.height / 2)
      mouseMove(widget, p.x, p.y)
      wait(450)
      check(!widget.previewOpen, "Current workspace preview should be opt-in")

      mouseMove(widget, outside.x, outside.y)
      widget.applySetting({previewActive: true})
      fakeBar.commands = []
      mouseMove(widget, p.x, p.y)
      wait(450)
      check(icon.hovered && widget.previewOpen && widget.previewWorkspaceId === widget.currentWorkspaceId,
        "Hovering a current-workspace app icon did not open its preview")
      check(JSON.stringify(widget.highlightAddresses) === JSON.stringify(icon.item.addresses),
        "Current-workspace preview lost the app's grouped-window highlights")
      check(fakeBar.commands.length === 0, "Preview hover must not focus or raise actual windows")
      widget.applySetting({previewActive: false})
      check(!widget.previewOpen, "Disabling current workspace previews did not close the preview")

      // A setting changed during the hover delay must prevent the pending popup.
      mouseMove(widget, outside.x, outside.y)
      widget.applySetting({previewActive: true})
      mouseMove(widget, p.x, p.y)
      widget.applySetting({previewActive: false})
      wait(450)
      check(!widget.previewOpen, "Pending current workspace preview ignored the disabled option")

      check(widget.peek(widget.currentWorkspaceId) && widget.previewOpen,
        "Explicit peek of the current workspace should still work without opting into hover previews")
      widget.hidePreview()
      var otherPill = collect(widget, function(item) {
        return item.workspaceId !== widget.currentWorkspaceId && item.showApps !== undefined && item.occupied
      }, [])[0]
      if (otherPill) {
        widget.pillHovered(otherPill, true)
        wait(450)
        check(widget.previewOpen && widget.previewWorkspaceId === otherPill.workspaceId,
          "Other workspace previews stopped working with the option disabled")
      }
      widget.applySetting({previews: false, previewActive: true})
      widget.pillHovered(activePill, true)
      wait(450)
      check(!widget.previewOpen, "Master preview switch must also disable current workspace previews")
      check(!widget.hoverPreviewAllowed({workspaceId: widget.currentWorkspaceId, occupied: false}),
        "Empty workspaces should not show previews")
      widget.hidePreview()
      console.log("PASS: opt-in current workspace icon previews, grouped highlights, live setting changes, and master switch")
    }
    function previousWindow() {
      var current = widget.backgroundWindowAddress()
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
      console.log("PASS: focused icon returns to previous live window; unfocused icon focuses its own window")
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
      check(JSON.stringify(widget.highlightAddresses) === JSON.stringify(icon.item.addresses),
        "Icon hover did not highlight all its window addresses")
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
