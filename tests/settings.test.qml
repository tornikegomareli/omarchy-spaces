import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Commons
import "Model.js" as Model
Window {
  visible: true
  width: 680
  height: Math.max(520, form.implicitHeight) + 32
  SpacesSettings {
    id: form
    anchors.fill: parent
    anchors.margins: 16
    cfg: Model.resolveSettings({})
    onSettingChanged: function(delta) { cfg = Model.resolveSettings(Object.assign({}, cfg, delta)) }
    onResetRequested: cfg = Model.resolveSettings({})
  }
  Timer {
    interval: 500
    running: true
    onTriggered: {
      try { checks.test_settings(); console.log("Interaction checks passed"); Qt.quit() }
      catch (error) { console.error(error); Qt.exit(1) }
    }
  }
  TestCase {
    id: checks
    name: "SpacesSettings"
    // Quickshell supplies its own application, so invoke the checks from
    // the timer and use QtTest only for input synthesis.
    when: false
    function find(item, prop, value) {
      if (item[prop] === value) return item
      for (var i = 0; i < item.children.length; i++) {
        var result = find(item.children[i], prop, value)
        if (result) return result
      }
      return null
    }
    function equal(actual, expected) {
      if (actual !== expected)
        throw new Error("Expected " + expected + ", got " + actual)
    }
    function test_settings() {
      var workspaces = find(form, "text", "Workspaces")
      mouseClick(workspaces)
      equal(form.section, "workspaces")
      var toggle = find(form, "key", "hideEmpty")
      toggle.forceActiveFocus()
      keyClick(Qt.Key_Space)
      equal(form.cfg.hideEmpty, true)
      var row = find(form, "key", "persistentWorkspaces")
      var slider = find(row, "integer", true)
      slider.forceActiveFocus()
      keyClick(Qt.Key_Right)
      equal(form.cfg.persistentWorkspaces, 6)
      keyClick(Qt.Key_End)
      equal(form.cfg.persistentWorkspaces, 10)
      keyClick(Qt.Key_Home)
      equal(form.cfg.persistentWorkspaces, 0)
      mouseClick(find(form, "text", "Reset to defaults…"))
      equal(form.confirmingReset, true)
      equal(form.cfg.hideEmpty, true)
      keyClick(Qt.Key_Escape)
      equal(form.confirmingReset, false)
      mouseClick(find(form, "text", "Reset to defaults…"))
      mouseClick(find(form, "text", "Reset all settings"))
      equal(form.cfg.hideEmpty, false)
      equal(form.cfg.persistentWorkspaces, 5)
      form.section = "appearance"
      wait(50)
      var heightSlider = find(find(form, "key", "pillHeight"), "integer", true)
      heightSlider.forceActiveFocus()
      keyClick(Qt.Key_Right)
      equal(form.cfg.pillHeight, 8)
      keyClick(Qt.Key_Home)
      equal(form.cfg.pillHeight, 0)
      var paddingSlider = find(find(form, "key", "pillPadding"), "integer", true)
      paddingSlider.forceActiveFocus()
      keyClick(Qt.Key_Right)
      equal(form.cfg.pillPadding, 1)
      keyClick(Qt.Key_End)
      equal(form.cfg.pillPadding, 24)
      keyClick(Qt.Key_Home)
      equal(form.cfg.pillPadding, 0)
      // Group headings are all the same small-caps label; a title-case heading
      // of its own would stand out from every other group.
      equal(find(form, "text", "Pill size"), null)
      equal(find(form, "text", "PILL SIZE") !== null, true)
      form.cfg = Model.resolveSettings({})
      mouseClick(find(form, "text", "App icons"))
      wait(50)
      mouseClick(find(form, "text", "Monochrome"))
      equal(form.cfg.iconStyle, "mono")
      mouseClick(find(form, "key", "showIcons"))
      equal(form.cfg.showIcons, false)
      equal(find(form, "key", "iconSize").visible, false)
      mouseClick(find(form, "text", "Behaviour"))
      wait(50)
      mouseClick(find(form, "text", "Previous window"))
      equal(form.cfg.activeIconClick, "previous")
      mouseClick(find(form, "text", "Cycles windows"))
      equal(form.cfg.activeIconClick, "cycle")
      form.cfg = Model.resolveSettings({focusedTitle: true})
      for (var section of ["icons", "windows", "appearance", "workspaces", "previews", "behavior"]) {
        form.section = section
        form.confirmingReset = true
        wait(50)
        var content = find(form, "objectName", "settingsContent")
        var footer = find(form, "objectName", "settingsFooter")
        if (content.y + content.implicitHeight > footer.y)
          throw new Error("Settings overlap the footer in " + section)
      }
      console.log("All settings assertions completed")
    }
  }
}
