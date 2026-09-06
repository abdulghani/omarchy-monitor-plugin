import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar readout of CPU / RAM / storage load, with a popup breaking each one
// down. Sampling is a single short-lived script per poll rather than a
// resident reader, so the widget costs nothing between ticks.
Panel {
  id: root
  moduleName: "abdulghani.sysmon"

  readonly property string scriptPath: Qt.resolvedUrl("sample.sh").toString().replace(/^file:\/\//, "")
  readonly property color fg: bar ? bar.foreground : Color.foreground

  // Raw counters from the previous poll, kept so the next one can be diffed.
  property var prevCpu: null
  property var cpuUsage: ({})
  property var loadAvg: [0, 0, 0]
  property int coreCount: 0
  property real memTotalKb: 0
  property real memAvailKb: 0
  property real swapTotalKb: 0
  property real swapFreeKb: 0
  property var disks: []
  // A first sample only establishes the CPU baseline; percentages are blank
  // until a second one lands to diff against.
  property bool primed: false

  readonly property real cpuFraction: cpuUsage["cpu"] !== undefined ? cpuUsage["cpu"] : 0
  readonly property int cpuPercent: Math.round(cpuFraction * 100)
  readonly property real memUsedKb: Math.max(0, memTotalKb - memAvailKb)
  readonly property real memFraction: memTotalKb > 0 ? memUsedKb / memTotalKb : 0
  readonly property int memPercent: Math.round(memFraction * 100)
  readonly property real swapUsedKb: Math.max(0, swapTotalKb - swapFreeKb)
  readonly property bool hasSwap: swapTotalKb > 0

  // The bar label speaks for the root filesystem; the popup lists them all.
  readonly property var rootDisk: {
    for (var i = 0; i < disks.length; i++) if (disks[i].mount === "/") return disks[i]
    return disks.length > 0 ? disks[0] : null
  }
  readonly property real diskFraction: rootDisk && rootDisk.size > 0 ? rootDisk.used / rootDisk.size : 0
  readonly property int diskPercent: Math.round(diskFraction * 100)

  readonly property bool anyCritical: cpuFraction >= 0.9 || memFraction >= 0.9 || diskFraction >= 0.9

  // Which single metric the bar label speaks for. The popup still shows all
  // three; this only picks the one worth a permanent slot on the bar.
  readonly property string barMetric: {
    var v = String(setting("barMetric", "cpu"))
    return (v === "cpu" || v === "memory" || v === "storage") ? v : "cpu"
  }

  readonly property var metricOptions: [
    { value: "cpu",     label: "CPU",  icon: "" },
    { value: "memory",  label: "RAM",  icon: "" },
    { value: "storage", label: "Disk", icon: "" }
  ]

  readonly property string barIcon: barMetric === "memory" ? ""
    : barMetric === "storage" ? "" : ""

  readonly property int barValue: barMetric === "memory" ? memPercent
    : barMetric === "storage" ? diskPercent : cpuPercent

  readonly property real barFraction: barMetric === "memory" ? memFraction
    : barMetric === "storage" ? diskFraction : cpuFraction

  // Persist through the shell so the choice survives a restart, and mirror it
  // locally so the label switches on the click rather than on the round-trip.
  function setBarMetric(value) {
    if (value === root.barMetric) return
    root.settings = Object.assign({}, root.settings, { barMetric: value })
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function meterColor(fraction) {
    return fraction >= 0.9 ? Color.urgent : root.fg
  }

  function sample() {
    if (!proc.running) proc.running = true
  }

  function applySample(text) {
    var s = Model.parse(text)

    root.cpuUsage = Model.cpuUsage(root.prevCpu, s.cpu)
    root.prevCpu = s.cpu
    root.loadAvg = s.load
    root.coreCount = s.cores
    root.memTotalKb = s.mem["MemTotal"] || 0
    root.memAvailKb = s.mem["MemAvailable"] || 0
    root.swapTotalKb = s.mem["SwapTotal"] || 0
    root.swapFreeKb = s.mem["SwapFree"] || 0
    root.disks = s.disks

    // Take the second sample straight away so the widget shows a real CPU
    // figure a moment after login instead of holding 0% for a whole interval.
    if (!root.primed) {
      root.primed = true
      primeTimer.restart()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: [root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySample(text)
    }
  }

  Timer {
    id: primeTimer
    interval: 600
    onTriggered: root.sample()
  }

  // Poll faster while the popup is on screen, where the numbers are being
  // read, and back off when only the bar label depends on them.
  Timer {
    interval: root.opened ? 1500 : 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sample()
  }

  // ---- Reusable pieces -----------------------------------------------------

  component Meter: Item {
    property real fraction: 0
    property color fill: root.fg

    implicitHeight: Math.max(3, Style.space(4))

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
    }

    Rectangle {
      height: parent.height
      width: Math.max(0, Math.min(1, parent.fraction)) * parent.width
      radius: height / 2
      color: parent.fill
      Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 200 } }
    }
  }

  // Label on the left, value on the right, meter underneath.
  component StatRow: Column {
    property string label: ""
    property string value: ""
    property real fraction: 0

    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)

      Text {
        id: rowLabel
        textFormat: Text.PlainText
        text: parent.parent.label
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        anchors.right: rowValue.left
        anchors.rightMargin: Style.space(8)
      }

      Text {
        id: rowValue
        textFormat: Text.PlainText
        text: parent.parent.value
        color: Qt.darker(root.fg, 1.35)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      fraction: parent.fraction
      fill: root.meterColor(parent.fraction)
    }
  }

  // ---- Bar button ----------------------------------------------------------

  // WidgetButton paints its label at one font size, so its own label is
  // switched off and the glyph and digits are drawn here as separate Texts —
  // the icon reads at bar-icon scale while the number stays small enough not
  // to crowd the slot. The button is then sized from this content instead of
  // from the label it is no longer painting.
  readonly property real barIconSize: Style.bar.iconFont
  readonly property real barValueSize: Style.font.bodySmall

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    horizontalMargin: 6
    active: root.anyCritical
    labelVisible: false
    // Still set, because WidgetButton keys visibility off a non-empty text.
    text: root.barIcon + " " + root.barValue
    // Only the metric on show has a slot, so name all three on hover.
    tooltipText: "CPU " + root.cpuPercent + "%   RAM " + root.memPercent + "%   Disk " + root.diskPercent + "%"

    readonly property bool stacked: root.bar ? root.bar.vertical : false
    // A vertical bar keeps its fixed width and grows downwards; a horizontal
    // one keeps the bar height and grows sideways. -1 leaves that axis to
    // WidgetButton's own default.
    fixedWidth: stacked ? -1 : horizontalRow.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: stacked ? verticalColumn.implicitHeight + scaledVerticalPadding * 2 : -1

    Row {
      id: horizontalRow
      visible: !button.stacked
      anchors.centerIn: parent
      spacing: Style.spaceReal(3)

      Text {
        textFormat: Text.PlainText
        text: root.barIcon
        color: button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: root.barIconSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: root.barValue + "%"
        color: button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: root.barValueSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Column {
      id: verticalColumn
      visible: button.stacked
      anchors.centerIn: parent
      spacing: 0

      Text {
        textFormat: Text.PlainText
        text: root.barIcon
        color: button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: root.barIconSize
        renderType: Text.NativeRendering
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: String(root.barValue)
        color: button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: root.barValueSize
        renderType: Text.NativeRendering
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }

    onPressed: function (b) {
      if (b === Qt.RightButton) {
        if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
      } else {
        root.toggle()
      }
    }
  }

  // ---- Popup ---------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Which metric the bar shows ----------
        PanelSectionHeader {
          text: "SHOW IN BAR"
          foreground: root.fg
        }

        ButtonGroup {
          width: parent.width
          options: root.metricOptions
          value: root.barMetric
          foreground: root.fg
          background: Color.popups.background
          accent: Color.accent
          fontSize: Style.font.bodySmall
          // The panel owns keyboard handling via PanelKeyCatcher, so the group
          // stays out of the Tab order and is driven by the pointer.
          focusable: false
          onChanged: function (value) { root.setBarMetric(value) }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- CPU ----------
        PanelSectionHeader {
          text: "CPU"
          foreground: root.fg
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(cpuBig.implicitHeight, cpuMeta.implicitHeight)

          Text {
            id: cpuBig
            textFormat: Text.PlainText
            text: root.primed ? root.cpuPercent + "%" : "—"
            color: root.meterColor(root.cpuFraction)
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: cpuMeta
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "load " + root.loadAvg[0].toFixed(2) + "  " + root.loadAvg[1].toFixed(2) + "  " + root.loadAvg[2].toFixed(2)
              color: Qt.darker(root.fg, 1.35)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.coreCount + " cores"
              color: Qt.darker(root.fg, 1.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              width: parent.width
            }
          }
        }

        // Per-core load, one thin bar each, in core order.
        Row {
          id: coreRow
          width: parent.width
          spacing: Style.space(3)
          visible: coreRepeater.count > 0

          readonly property var names: Model.coreNames(root.cpuUsage)
          readonly property real cellWidth: coreRepeater.count > 0
            ? (width - spacing * (coreRepeater.count - 1)) / coreRepeater.count
            : 0

          Repeater {
            id: coreRepeater
            model: coreRow.names

            Meter {
              required property string modelData
              width: coreRow.cellWidth
              fraction: root.cpuUsage[modelData] || 0
              fill: root.meterColor(fraction)
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Memory ----------
        PanelSectionHeader {
          text: "MEMORY"
          foreground: root.fg
        }

        StatRow {
          width: parent.width
          label: "RAM  " + root.memPercent + "%"
          value: Model.pairGib(root.memUsedKb * 1024, root.memTotalKb * 1024)
          fraction: root.memFraction
        }

        StatRow {
          width: parent.width
          visible: root.hasSwap
          label: "Swap  " + Model.percent(root.swapUsedKb, root.swapTotalKb) + "%"
          value: Model.pairGib(root.swapUsedKb * 1024, root.swapTotalKb * 1024)
          fraction: root.swapTotalKb > 0 ? root.swapUsedKb / root.swapTotalKb : 0
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Storage ----------
        PanelSectionHeader {
          text: "STORAGE"
          foreground: root.fg
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: root.disks

            StatRow {
              required property var modelData
              width: parent.width
              label: Model.mountLabel(modelData.mount) + "  " + Model.percent(modelData.used, modelData.size) + "%"
              value: Model.pairGib(modelData.used, modelData.size)
              fraction: modelData.size > 0 ? modelData.used / modelData.size : 0
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: "Right-click the bar for btop"
          color: Qt.darker(root.fg, 1.8)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          width: parent.width
          horizontalAlignment: Text.AlignRight
        }
      }
    }
  }
}
