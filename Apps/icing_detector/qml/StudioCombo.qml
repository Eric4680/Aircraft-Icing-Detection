import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    property int textElide: Text.ElideRight
    implicitHeight: 36
    font.pixelSize: 12
    leftPadding: 12; rightPadding: 30
    opacity: enabled ? 1 : 0.45
    contentItem: Text { text: control.displayText; color: Theme.text; font: control.font; verticalAlignment: Text.AlignVCenter; elide: control.textElide }
    indicator: Icon { name: "chevron"; width: 15; height: 15; x: control.width - width - 10; y: (control.height - height) / 2 }
    background: Rectangle { radius: 8; color: Theme.field; border.color: control.activeFocus ? Theme.accent : Theme.border }
    delegate: ItemDelegate {
        required property int index
        required property var modelData
        width: control.width
        height: 36
        highlighted: control.highlightedIndex === index
        contentItem: Text { text: control.textRole ? modelData[control.textRole] : modelData; color: Theme.text; font: control.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        background: Rectangle { radius: 6; color: parent.highlighted ? Theme.accentFill : "transparent" }
    }
    popup: Popup {
        y: control.height + 5; width: control.width; padding: 5
        implicitHeight: Math.min(contentItem.implicitHeight + 10, 280)
        contentItem: ListView { clip: true; implicitHeight: contentHeight; model: control.popup.visible ? control.delegateModel : null; currentIndex: control.highlightedIndex; ScrollIndicator.vertical: ScrollIndicator {} }
        background: Rectangle { color: Theme.panel; border.color: Theme.border; radius: 10 }
    }
}
