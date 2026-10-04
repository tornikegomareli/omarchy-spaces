import QtQuick
import qs.Commons
import qs.Ui

// Kept separate from the workspace widget so the form can be previewed in isolation.
Item {
  id: root
  required property var cfg
  property QtObject bar: null
  property color fg: Color.foreground
  property string fontFamily: Style.font.family
  property string section: "icons"
  property bool confirmingReset: false
  signal settingChanged(var delta)
  signal resetRequested()
  signal closeRequested()

  function applySetting(delta) { settingChanged(delta) }
  implicitHeight: header.implicitHeight + Math.max(navigation.implicitHeight, form.implicitHeight)
    + footer.implicitHeight + Style.space(40)
  onSectionChanged: confirmingReset = false
  Keys.onEscapePressed: {
    if (confirmingReset) confirmingReset = false
    else closeRequested()
  }

  Column {
    id: header
    width: parent.width
    spacing: Style.space(12)
    Item {
      width: parent.width
      implicitHeight: heading.implicitHeight
      Column {
        id: heading
        spacing: Style.space(3)
        Text { text: "Spaces settings"; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
        Text { text: "Changes apply automatically"; color: root.fg; opacity: 0.7; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      }
      Button {
        anchors.right: parent.right
        text: "Close"
        focusable: true
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.closeRequested()
      }
    }
    PanelSeparator { foreground: root.fg }
  }

  Column {
    id: navigation
    anchors.top: header.bottom
    anchors.topMargin: Style.space(16)
    width: Style.space(126)
      spacing: Style.space(6)
      Repeater {
        model: [{value: "icons", label: "App icons"}, {value: "windows", label: "Windows"}, {value: "appearance", label: "Appearance"},
                {value: "workspaces", label: "Workspaces"}, {value: "previews", label: "Previews"},
                {value: "behavior", label: "Behaviour"}]
        delegate: Button {
          required property var modelData
          width: navigation.width
          leftAlign: true
          text: modelData.label
          selected: root.section === modelData.value
          bordered: true
          focusable: true
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.section = modelData.value
        }
      }
    }
  Column {
      id: form
      objectName: "settingsContent"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(16)
      anchors.left: navigation.right
      anchors.leftMargin: Style.space(20)
      anchors.right: parent.right
      spacing: Style.space(12)
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.section === "icons"
          // ---- App icons
          SectionTitle { text: "APP ICONS" }

          ToggleSetting {
            label: "Show app icons"
            description: root.cfg.showIcons ? "Icons of open apps appear in workspace pills" : "Hidden: only workspace labels are shown"
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


      }
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.section === "windows"
        SectionTitle { text: "WINDOWS" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Group windows by app"; description: "One icon per app with a window count"; key: "groupApps" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Dim unfocused windows"; description: "On the active workspace"; key: "dimUnfocused" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Show focused window title"; description: "Next to its icon"; key: "focusedTitle" }
          SliderSetting { visible: root.cfg.showIcons && root.cfg.focusedTitle; title: "TITLE LENGTH"; key: "titleLength"; minimum: 8; maximum: 60; suffix: " characters" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Agent status"; description: "Badges on terminals running coding agents"; key: "agentStatus" }

        ToggleSetting { label: "Highlight urgent windows"; description: "Pulse workspaces asking for attention"; key: "urgentHighlight" }
        ToggleSetting { label: "Tooltips"; description: "Window titles on hover"; key: "tooltips" }
      }
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.section === "appearance"
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

          ToggleSetting {
            label: "Pill background"
            description: "Fill behind occupied and hovered workspaces"
            key: "pillBackground"
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

          ToggleSetting {
            label: "Show numbers while holding Super"
            description: "Hold Super to peek at numbers. Needs keybindings, see README"
            key: "holdSuperNumbers"
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
              { value: "never", label: "Right-click only" }
            ]
          }


      }
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.section === "workspaces"
          // ---- Workspaces
          SectionTitle { text: "WORKSPACES" }

          SliderSetting { title: "ALWAYS SHOW WORKSPACES"; key: "persistentWorkspaces"; minimum: 0; maximum: 10 }
          ToggleSetting { label: "Hide empty workspaces"; key: "hideEmpty" }
          ToggleSetting { label: "Only this monitor's workspaces"; key: "perMonitor" }

      }
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.section === "previews"
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

      }
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.section === "behavior"
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

      }
  }

  Column {
    id: footer
    objectName: "settingsFooter"
    anchors.bottom: parent.bottom
    width: parent.width
    spacing: Style.space(8)
    PanelSeparator { foreground: root.fg }
    Text {
      visible: root.confirmingReset
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Reset all Spaces settings to their defaults?"
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Flow {
      width: parent.width
      spacing: Style.space(8)
      Button {
        text: root.confirmingReset ? "Reset all settings" : "Reset to defaults…"
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        focusable: true
        onClicked: {
          if (root.confirmingReset) { root.resetRequested(); root.confirmingReset = false }
          else root.confirmingReset = true
        }
      }
      Button {
        visible: root.confirmingReset
        text: "Cancel"
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        focusable: true
        onClicked: root.confirmingReset = false
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

    Flow {
      id: choices
      width: parent.width
      property string settingKey: parent.key
      spacing: Style.space(6)
      Repeater {
        model: choices.parent.options
        delegate: Button {
          required property var modelData
          text: modelData.label
          selected: String(root.cfg[choices.settingKey]) === modelData.value
          bordered: true
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          focusable: true
          onClicked: {
            var delta = ({})
            delta[choices.settingKey] = modelData.value
            root.applySetting(delta)
          }
        }
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
      activeFocusOnTab: true
      Keys.onLeftPressed: released(Math.max(minimum, value - 1))
      Keys.onRightPressed: released(Math.min(maximum, value + 1))
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Home) { released(minimum); event.accepted = true }
        else if (event.key === Qt.Key_End) { released(maximum); event.accepted = true }
      }
      Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        visible: slider.activeFocus
        color: "transparent"
        border.color: root.fg
        radius: Style.cornerRadius
      }
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
