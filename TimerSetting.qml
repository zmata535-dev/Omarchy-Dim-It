import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Column {
  id: root

  property QtObject bar: null
  property string label: ""
  property string displayValue: ""
  property real value: 0
  property real minimum: 0
  property real maximum: 100
  property real step: 1
  property real settingWidth: -1

  signal settingChanged(real value)

  function snapValue(value) {
    var safeStep = Math.max(1, root.step)
    return Math.max(root.minimum, Math.min(root.maximum,
      root.minimum + Math.round((value - root.minimum) / safeStep) * safeStep))
  }

  width: root.settingWidth >= 0 ? root.settingWidth : (parent ? parent.width : Style.space(300))
  spacing: 0

  Row {
    width: parent.width

    Text {
      textFormat: Text.PlainText
      text: root.label
      width: Math.max(0, parent.width - valueLabel.implicitWidth)
      color: Commons.Color.popups.text
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: valueLabel
      textFormat: Text.PlainText
      text: root.displayValue
      color: Commons.Color.popups.text
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      width: implicitWidth
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  PanelSlider {
    bar: root.bar
    width: parent.width
    height: Style.space(18)
    knobSize: Style.space(12)
    minimum: root.minimum
    maximum: root.maximum
    step: root.step
    integer: true
    value: root.value
    onMoved: function(nextValue) { root.settingChanged(root.snapValue(nextValue)) }
  }
}
