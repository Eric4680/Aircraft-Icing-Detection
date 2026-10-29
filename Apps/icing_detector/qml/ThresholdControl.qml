import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: control
    property string title: "Confidence"
    property string helpText: ""
    property real value: 0.25
    property bool applicable: true
    signal edited(real value)
    spacing: 5
    RowLayout {
        Layout.fillWidth: true
        Text { text: control.title; color: control.applicable ? Theme.text : Theme.muted; font.pixelSize: 12; font.weight: Font.Medium }
        ToolButton {
            id: helpButton
            objectName: control.objectName + "_help"
            visible: control.helpText.length > 0
            implicitWidth: 24; implicitHeight: 24
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Accessible.name: control.title + "说明"
            Accessible.description: control.helpText
            contentItem: Item {
                Icon { anchors.centerIn: parent; name: "help"; width: 15; height: 15; ink: helpButton.hovered || helpButton.visualFocus ? Theme.accent : Theme.muted }
            }
            background: Rectangle { radius: 6; color: helpButton.down || helpButton.hovered || helpButton.visualFocus ? Theme.field : "transparent" }
            ToolTip {
                objectName: control.objectName + "_tooltip"
                popupType: Popup.Item
                visible: helpButton.hovered || helpButton.visualFocus
                delay: helpButton.visualFocus ? 0 : 450
                width: Math.min(280, control.width)
                padding: 11
                contentItem: Text { text: control.helpText; textFormat: Text.PlainText; color: Theme.text; font.pixelSize: 11; wrapMode: Text.Wrap; lineHeight: 1.45 }
                background: Rectangle { color: Theme.panel; border.color: Theme.border; radius: 8 }
                enter: Transition {}
                exit: Transition {}
            }
        }
        Item { Layout.fillWidth: true }
        SpinBox {
            objectName: control.objectName + "_number"
            id: number; from: 0; to: 100; value: Math.round(control.value * 100)
            enabled: control.applicable; editable: true; implicitWidth: 70; implicitHeight: 28
            font.pixelSize: 12
            Accessible.name: control.title + " 百分比"
            textFromValue: function(v, locale) { return v.toString() + "%" }
            valueFromText: function(t, locale) { return parseInt(t.replace("%", "")) || 0 }
            onValueModified: control.edited(value / 100)
            up.indicator: Item { }
            down.indicator: Item { }
            contentItem: TextInput { text: number.textFromValue(number.value, number.locale); font: number.font; color: control.applicable ? Theme.accent : Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; readOnly: !number.editable; validator: RegularExpressionValidator { regularExpression: /\d{0,3}%?/ } selectByMouse: true; selectionColor: Theme.accent }
            background: Rectangle { color: Theme.field; radius: 6; border.color: number.activeFocus ? Theme.accent : "transparent" }
        }
    }
    Slider {
        objectName: control.objectName + "_slider"
        id: slider
        from: 0; to: 1; stepSize: 0.01; value: control.value
        enabled: control.applicable
        Layout.fillWidth: true
        implicitHeight: 24
        Accessible.name: control.title
        onMoved: control.edited(value)
        background: Rectangle {
            x: slider.leftPadding; y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: 200; height: 4; width: slider.availableWidth; radius: 2; color: Theme.border
            Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: control.applicable ? Theme.accent : Theme.muted }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: 16; implicitHeight: 16; radius: 8
            color: control.applicable ? "#ffffff" : Theme.field
            border.color: slider.activeFocus ? Theme.accent : Theme.border
            border.width: slider.activeFocus ? 2 : 1
            Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Theme.accent; visible: slider.pressed }
        }
    }
}
