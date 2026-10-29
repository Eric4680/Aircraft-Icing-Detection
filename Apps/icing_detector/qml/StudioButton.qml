import QtQuick
import QtQuick.Controls

Button {
    id: button
    property bool primary: false
    property bool quiet: false
    property string symbol: ""
    property string hint: ""
    property bool active: false
    implicitHeight: 36
    implicitWidth: body.implicitWidth + (text.length ? 26 : 20)
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.4
    font.pixelSize: 12
    Accessible.name: text || hint
    contentItem: Item {
        implicitWidth: body.implicitWidth
        Row {
            id: body; anchors.centerIn: parent; spacing: 7
            Icon { visible: button.symbol !== ""; name: button.symbol; anchors.verticalCenter: parent.verticalCenter; ink: button.primary ? "white" : (button.active ? Theme.accent : Theme.secondary) }
            Text { visible: text.length > 0; text: button.text; font.pixelSize: button.font.pixelSize; font.family: button.font.family; font.weight: Font.Medium; color: button.primary ? "white" : (button.active ? Theme.accent : Theme.text); anchors.verticalCenter: parent.verticalCenter }
        }
    }
    background: Rectangle {
        radius: 8
        color: button.primary ? (button.down ? "#1263bd" : button.hovered ? "#2787ef" : "#1477e5")
                             : button.active ? Theme.accentFill : button.down ? Theme.border : button.hovered ? Theme.field : button.quiet ? "transparent" : Theme.panel
        border.color: button.visualFocus ? Theme.accent : button.primary || button.quiet ? "transparent" : Theme.border
        border.width: button.visualFocus ? 2 : 1
        Behavior on color { ColorAnimation { duration: button.down ? 0 : Theme.motion } }
    }
    ToolTip.visible: hovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 600
}
