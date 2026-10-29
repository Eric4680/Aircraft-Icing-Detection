import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: viewport
    property var viewState: ({})
    property var boxes: []
    property real panX: 0
    property real panY: 0
    property real manualScale: 1
    property bool fitMode: true
    readonly property real fitScale: viewState.imageWidth > 0 ? Math.min((width - 64) / viewState.imageWidth, (height - 104) / viewState.imageHeight) : 1
    readonly property real imageScale: fitMode ? Math.max(0.001, fitScale) : manualScale
    readonly property real percent: imageScale * Screen.devicePixelRatio * 100
    clip: true

    function fit() { fitMode = true; panX = 0; panY = 0 }
    function actual() { fitMode = false; manualScale = 1 / Screen.devicePixelRatio; panX = 0; panY = 0 }
    function zoomAt(factor, px, py) {
        if (!viewState.hasImage) return
        let oldScale = imageScale
        let nextScale = Math.max(0.005, Math.min(24, oldScale * factor))
        let imageX = (px - content.x) / oldScale
        let imageY = (py - content.y) / oldScale
        fitMode = false
        manualScale = nextScale
        panX = px - (width - viewState.imageWidth * nextScale) / 2 - imageX * nextScale
        panY = py - (height - viewState.imageHeight * nextScale) / 2 - imageY * nextScale
    }
    Connections { target: studio; function onViewReset() { viewport.fit() } }

    Rectangle { anchors.fill: parent; color: Theme.canvas }
    Column {
        visible: !viewport.viewState.hasImage
        anchors.centerIn: parent; spacing: 18
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 88; height: 88; radius: 24; color: Theme.panel; border.color: Theme.border
            Icon { name: "image"; width: 38; height: 38; ink: Theme.accent; anchors.centerIn: parent }
        }
        Text { text: "从一张照片开始"; font.pixelSize: 24; font.weight: Font.DemiBold; color: Theme.text; anchors.horizontalCenter: parent.horizontalCenter }
        Text { text: "拖入飞机或部件照片，查看可见覆冰的检测结果\n也可以按 Ctrl + V 粘贴图片"; font.pixelSize: 12; color: Theme.secondary; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.7; anchors.horizontalCenter: parent.horizontalCenter }
        StudioButton { text: "导入图片"; symbol: "plus"; primary: true; anchors.horizontalCenter: parent.horizontalCenter; onClicked: studio.openImages() }
        Text { text: "JPG · PNG · WebP · BMP · TIFF"; font.pixelSize: 10; color: Theme.muted; anchors.horizontalCenter: parent.horizontalCenter }
    }

    Item {
        id: content
        visible: viewport.viewState.hasImage && viewport.viewState.preview !== ""
        x: (viewport.width - width) / 2 + viewport.panX
        y: (viewport.height - height) / 2 + viewport.panY
        width: (viewport.viewState.imageWidth || 0) * viewport.imageScale
        height: (viewport.viewState.imageHeight || 0) * viewport.imageScale
        Image {
            anchors.fill: parent; source: viewport.viewState.preview || ""
            cache: false; asynchronous: true; smooth: true; mipmap: true
            fillMode: Image.Stretch
        }
        Repeater {
            model: viewport.viewState.showBoxes && viewport.viewState.labelMode !== 4 ? viewport.boxes : []
            delegate: Item {
                required property var modelData
                objectName: "boxOverlay_" + modelData.id
                readonly property bool selected: viewport.viewState.selectedBox === modelData.id
                x: modelData.xyxy[0] * viewport.imageScale
                y: modelData.xyxy[1] * viewport.imageScale
                width: (modelData.xyxy[2] - modelData.xyxy[0]) * viewport.imageScale
                height: (modelData.xyxy[3] - modelData.xyxy[1]) * viewport.imageScale
                opacity: viewport.viewState.opacity
                Rectangle { anchors.fill: parent; color: selected ? "#1923a6d5" : "transparent"; border.color: selected ? "#f3bf63" : Theme.cyan; border.width: selected ? 3 : 2; radius: 1 }
                Rectangle {
                    visible: viewport.viewState.labelMode < 3
                    x: Math.max(-parent.x, Math.min(0, content.width - parent.x - width))
                    y: parent.y >= height ? -height : 0
                    width: label.implicitWidth + 14; height: 25; radius: 4
                    color: parent.selected ? "#b97714" : Theme.cyan
                    Text {
                        id: label; anchors.centerIn: parent; color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold
                        text: viewport.viewState.labelMode === 0 ? modelData.class_name + " " + Math.round(modelData.confidence * 100) + "%"
                              : viewport.viewState.labelMode === 1 ? modelData.class_name : Math.round(modelData.confidence * 100) + "%"
                    }
                }
            }
        }
    }
    MouseArea {
        id: interaction
        anchors.fill: parent
        enabled: viewport.viewState.hasImage
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real originX: 0
        property real originY: 0
        property real startX: 0
        property real startY: 0
        onPressed: function(mouse) { originX = viewport.panX; originY = viewport.panY; startX = mouse.x; startY = mouse.y }
        onPositionChanged: function(mouse) { if (pressed) { viewport.panX = originX + mouse.x - startX; viewport.panY = originY + mouse.y - startY } }
        onClicked: function(mouse) {
            if (Math.abs(mouse.x - startX) + Math.abs(mouse.y - startY) > 5) return
            let x = (mouse.x - content.x) / viewport.imageScale
            let y = (mouse.y - content.y) / viewport.imageScale
            let chosen = -1
            if (viewport.viewState.showBoxes && viewport.viewState.labelMode !== 4) {
                for (let box of viewport.boxes) {
                    if (x >= box.xyxy[0] && x <= box.xyxy[2] && y >= box.xyxy[1] && y <= box.xyxy[3]) { chosen = box.id; break }
                }
            }
            studio.selectBox(chosen)
        }
        onWheel: function(wheel) { viewport.zoomAt(Math.pow(1.0015, wheel.angleDelta.y), wheel.x, wheel.y); wheel.accepted = true }
        onDoubleClicked: viewport.fit()
    }

    BusyIndicator { anchors.centerIn: parent; running: viewport.viewState.hasImage && viewport.viewState.preview === ""; visible: running; palette.dark: Theme.accent }
    Rectangle {
        visible: viewport.viewState.hasImage
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 20
        width: tools.implicitWidth + 16; height: 44; radius: 12
        color: Theme.panel; border.color: Theme.border
        Row {
            id: tools; spacing: 3; anchors.centerIn: parent
            StudioButton { quiet: true; symbol: "minus"; hint: "缩小"; onClicked: viewport.zoomAt(1 / 1.2, viewport.width / 2, viewport.height / 2) }
            Text { width: 55; height: 36; text: Math.round(viewport.percent) + "%"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: Theme.secondary; font.pixelSize: 11 }
            StudioButton { quiet: true; symbol: "plus"; hint: "放大"; onClicked: viewport.zoomAt(1.2, viewport.width / 2, viewport.height / 2) }
            Rectangle { width: 1; height: 18; color: Theme.border; anchors.verticalCenter: parent.verticalCenter }
            StudioButton { objectName: "fitButton"; quiet: true; symbol: "fit"; hint: "适应窗口 · Ctrl+0"; active: viewport.fitMode; onClicked: viewport.fit() }
            StudioButton { objectName: "actualPixelsButton"; quiet: true; symbol: "actual"; hint: "实际像素 · Ctrl+1"; onClicked: viewport.actual() }
        }
    }
}
