import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: root
    objectName: "studioWindow"
    visible: true
    width: 1460; height: 940
    minimumWidth: 960; minimumHeight: 640
    title: "Aircraft Icing Detection Studio"
    color: Theme.background
    property var s: studio.state
    property var boxes: studio.detections
    Binding { target: Theme; property: "dark"; value: root.s.theme === "dark" }
    Binding { target: Theme; property: "reducedMotion"; value: root.s.reducedMotion }
    Binding { target: Theme; property: "backdrop"; value: liquidLoader.item ? liquidLoader.item.texture : null }
    Binding { target: Theme; property: "glassEnabled"; value: liquidLoader.item ? liquidLoader.item.shaderReady : false }
    palette.window: Theme.panel; palette.base: Theme.panel; palette.text: Theme.text
    palette.buttonText: Theme.text; palette.highlight: Theme.accent
    font.family: "Microsoft YaHei UI"
    font.pixelSize: 12
    onClosing: function(close) { close.accepted = studio.requestClose() }

    Shortcut { sequence: "Ctrl+O"; onActivated: studio.openImages() }
    Shortcut { sequence: "Ctrl+V"; onActivated: studio.pasteImage() }
    Shortcut { sequence: "Ctrl+0"; onActivated: viewport.fit() }
    Shortcut { sequence: "Ctrl+1"; onActivated: viewport.actual() }
    Shortcut { sequence: "Ctrl+Return"; onActivated: studio.detectCurrent() }
    Shortcut { sequence: "Ctrl+S"; onActivated: studio.exportCurrent("annotated") }

    Loader {
        id: liquidLoader
        objectName: "liquidBackgroundLoader"
        anchors.fill: parent
        active: !root.s.reducedMotion && root.GraphicsInfo.api !== GraphicsInfo.Software
        sourceComponent: LiquidBackground {
            animating: root.visible && root.visibility !== Window.Minimized
            pointerInside: ambientHover.hovered
            pointerPosition: Qt.point(ambientHover.point.position.x / Math.max(1, root.width), ambientHover.point.position.y / Math.max(1, root.height))
        }
    }
    HoverHandler {
        id: ambientHover
        enabled: Theme.glassEnabled
        blocking: false
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        GlassSurface {
            Layout.fillWidth: true; Layout.preferredHeight: 76; tint: Theme.panel
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 22; spacing: 14
                Rectangle { width: 38; height: 38; radius: 11; color: Theme.accentFill; Icon { name: "snow"; anchors.centerIn: parent; width: 24; height: 24; ink: Theme.accent } }
                ColumnLayout {
                    spacing: 4
                    Text { text: "Aircraft Icing"; color: Theme.text; font.pixelSize: 20; font.weight: Font.DemiBold; font.letterSpacing: -0.45 }
                    Text { text: "DETECTION STUDIO"; color: Theme.muted; font.pixelSize: 9; font.letterSpacing: 1.6; font.weight: Font.Medium }
                }
                Item { Layout.fillWidth: true }
                StudioButton { symbol: "plus"; text: "导入图片"; onClicked: studio.openImages(); enabled: !root.s.importing }
                StudioButton { symbol: "batch"; text: "批量检测"; primary: true; enabled: root.s.ready && !root.s.loading && studio.library.count > 0; onClicked: studio.detectAll() }
                StudioButton {
                    id: exportButton; symbol: "download"; text: "导出"; enabled: root.s.hasImage && !root.s.exporting
                    onClicked: exportMenu.open()
                    Menu {
                        id: exportMenu; y: exportButton.height + 6; width: 208
                        MenuItem { text: "保存检测图片…"; enabled: root.s.hasResult; onTriggered: studio.exportCurrent("annotated") }
                        MenuItem { text: "保存原图副本…"; onTriggered: studio.exportCurrent("original") }
                        MenuItem { text: "导出 JSON…"; enabled: root.s.hasResult; onTriggered: studio.exportCurrent("json") }
                        MenuSeparator {}
                        MenuItem { text: "批量导出全部结果…"; enabled: !root.s.busy; onTriggered: studio.exportAll() }
                    }
                }
                StudioButton { symbol: root.s.theme === "light" ? "moon" : "sun"; quiet: true; hint: "切换浅色 / 深色"; onClicked: studio.setTheme(root.s.theme === "light" ? "dark" : "light") }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            // Library — restrained material and persistent spatial organization.
            GlassSurface {
                Layout.preferredWidth: root.width < 1250 ? 206 : 238
                Layout.fillHeight: true; tint: Theme.sidebar; materialWeight: 0.67
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "图片库"; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true }
                        Text { text: studio.library.count.toString().padStart(2, "0"); color: Theme.muted; font.pixelSize: 11 }
                    }
                    Text { text: "点击图片，自动检测"; color: Theme.muted; font.pixelSize: 10 }
                    ListView {
                        id: libraryView
                        objectName: "libraryView"
                        Layout.fillWidth: true; Layout.fillHeight: true
                        model: studio.library; spacing: 7; clip: true
                        currentIndex: root.s.currentIndex
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            id: imageRow
                            required property int index
                            required property string imageId
                            required property string name
                            required property string thumbnail
                            required property int pixelWidth
                            required property int pixelHeight
                            required property string status
                            width: libraryView.width; height: 86; radius: 10
                            color: root.s.currentIndex === index ? Theme.panel : libraryMouse.containsMouse ? Theme.field : "transparent"
                            border.color: root.s.currentIndex === index ? Theme.accent : "transparent"
                            border.width: root.s.currentIndex === index ? 1.5 : 1
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 9; spacing: 10
                                Rectangle {
                                    width: 58; height: 64; radius: 6; color: Theme.canvas; clip: true
                                    Image { anchors.fill: parent; anchors.margins: 2; source: imageRow.thumbnail; fillMode: Image.PreserveAspectFit; asynchronous: true }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text { text: imageRow.name; color: Theme.text; font.pixelSize: 11; font.weight: Font.Medium; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                    Text { text: imageRow.pixelWidth + " × " + imageRow.pixelHeight; color: Theme.muted; font.pixelSize: 9 }
                                    Text { text: imageRow.status; color: imageRow.status === "检测失败" ? Theme.error : root.s.currentIndex === imageRow.index ? Theme.accent : Theme.secondary; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                            MouseArea { id: libraryMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: studio.selectImage(imageRow.index) }
                        }
                    }
                    Text { visible: studio.library.count === 0; text: "图片将显示在这里"; color: Theme.muted; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 4
                        StudioButton { text: "移除"; symbol: "trash"; quiet: true; enabled: root.s.hasImage && !root.s.importing; onClicked: studio.removeCurrent(); hint: "仅从列表移除，原文件保留" }
                        Item { Layout.fillWidth: true }
                        StudioButton { text: "清空"; quiet: true; enabled: root.s.hasImage && !root.s.importing; onClicked: studio.clearImages() }
                    }
                    Text { text: "Ctrl+O 导入    Ctrl+V 粘贴"; font.pixelSize: 9; color: Theme.muted; Layout.alignment: Qt.AlignHCenter }
                }
            }
            Rectangle { width: 1; Layout.fillHeight: true; color: Theme.border }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                GlassSurface {
                    Layout.fillWidth: true; Layout.preferredHeight: 58; tint: Theme.panel
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 14; spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4
                            Text { text: root.s.imageName; color: Theme.text; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            Text { text: root.s.hasImage ? root.s.imageWidth + " × " + root.s.imageHeight + " px" : "照片中的可见覆冰区域"; color: Theme.muted; font.pixelSize: 10 }
                        }
                        StudioButton { text: "原图"; quiet: true; active: !root.s.showBoxes; enabled: root.s.hasImage; onClicked: studio.setShowBoxes(false) }
                        StudioButton { text: "检测结果"; symbol: "eye"; quiet: true; active: root.s.showBoxes; enabled: root.s.hasImage; onClicked: studio.setShowBoxes(true) }
                        Rectangle { width: 1; height: 20; color: Theme.border }
                        StudioButton { symbol: "play"; quiet: true; hint: "重新检测 · Ctrl+Enter"; enabled: root.s.ready && root.s.hasImage && !root.s.loading; onClicked: studio.detectCurrent() }
                    }
                }
                ImageViewport { id: viewport; objectName: "imageViewport"; Layout.fillWidth: true; Layout.fillHeight: true; viewState: root.s; boxes: root.boxes }
                GlassSurface {
                    Layout.fillWidth: true; Layout.preferredHeight: 37; tint: Theme.panel
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18
                        Rectangle { width: 6; height: 6; radius: 3; color: root.s.busy || root.s.loading ? Theme.accent : root.s.ready ? Theme.success : Theme.error }
                        Text { text: root.s.loading ? "模型加载中…" : root.s.busy ? "正在检测 · 队列 " + root.s.pendingCount : root.s.imageStatus; color: Theme.secondary; font.pixelSize: 10 }
                        Item { Layout.fillWidth: true }
                        Text { text: root.s.hasImage ? "滚轮缩放 · 拖动平移 · 双击适应" : "本地照片工作区"; color: Theme.muted; font.pixelSize: 9 }
                    }
                }
            }
            Rectangle { width: 1; Layout.fillHeight: true; color: Theme.border }
            GlassSurface {
                Layout.preferredWidth: root.width < 1250 ? 286 : 316
                Layout.fillHeight: true; tint: Theme.panel; materialWeight: 0.78
                ScrollView {
                    id: inspectorScroll
                    anchors.fill: parent; clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ColumnLayout {
                        width: inspectorScroll.availableWidth
                        spacing: 0
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.margins: 20; spacing: 14
                            RowLayout {
                                Icon { name: "sliders"; ink: Theme.text; width: 17; height: 17 }
                                Text { text: "模型与可视化"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                            }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 81; radius: 11; color: Theme.field
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 12; spacing: 5
                                    RowLayout {
                                        Rectangle { width: 6; height: 6; radius: 3; color: root.s.ready ? Theme.success : root.s.loading ? Theme.accent : Theme.error }
                                        Text { text: root.s.modelName; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                    }
                                    Text { text: "Icing · 目标检测 · 640 px"; color: Theme.secondary; font.pixelSize: 10 }
                                    Text { text: root.s.loading ? "模型初始化中…" : root.s.ready ? "权重已校验 · 本机运行" : "模型加载失败"; color: root.s.ready ? Theme.success : Theme.secondary; font.pixelSize: 10 }
                                }
                            }
                            StudioCombo {
                                objectName: "deviceCombo"; Layout.fillWidth: true; model: root.s.devices; textRole: "label"
                                currentIndex: { for (let i = 0; i < root.s.devices.length; i++) if (root.s.devices[i].id === root.s.device) return i; return -1 }
                                displayText: root.s.deviceLabel; enabled: root.s.ready && !root.s.loading && !root.s.busy
                                textElide: Text.ElideMiddle
                                hoverEnabled: true
                                ToolTip.visible: hovered
                                ToolTip.text: root.s.deviceLabel
                                ToolTip.delay: 600
                                Accessible.name: "计算设备"
                                onActivated: function(index) { studio.setDevice(index) }
                            }
                            StudioButton { visible: !root.s.ready && !root.s.loading; text: "重试加载模型"; Layout.fillWidth: true; onClicked: studio.retryModel() }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.margins: 20; spacing: 18
                            Text { text: "检测参数"; color: Theme.muted; font.pixelSize: 10; font.weight: Font.DemiBold }
                            ThresholdControl { objectName: "confidenceControl"; Layout.fillWidth: true; title: "置信度阈值"; value: root.s.confidence; helpText: "只显示可信度达到该数值的检测框。调高可减少误报，调低可找到更多疑似结冰区域。"; onEdited: function(value) { studio.setConfidence(value) } }
                            ThresholdControl { objectName: "iouControl"; Layout.fillWidth: true; title: "重叠阈值 · IoU"; value: root.s.iou; applicable: root.s.ready && !root.s.endToEnd; helpText: !root.s.ready ? "模型加载后会判断是否需要此项。" : root.s.endToEnd ? "用于筛除位置重复的检测框。当前模型不使用这一步，因此无需调整。" : "用于筛除重复框：数值越低，重叠框越容易被去除。"; onEdited: function(value) { studio.setIou(value) } }
                            ThresholdControl { objectName: "opacityControl"; Layout.fillWidth: true; title: "检测框不透明度"; value: root.s.opacity; helpText: "0% 完全透明，100% 完全不透明。只改变显示效果，不影响检测结果。"; onEdited: function(value) { studio.setOpacity(value) } }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text { text: "标签显示"; color: Theme.text; font.pixelSize: 12; font.weight: Font.Medium }
                                StudioCombo { objectName: "labelCombo"; Layout.fillWidth: true; model: ["类别与置信度", "仅显示类别", "仅显示置信度", "隐藏标签", "隐藏所有检测框"]; currentIndex: root.s.labelMode; onActivated: function(index) { studio.setLabelMode(index) } Accessible.name: "标签显示方式" }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.margins: 20; spacing: 12
                            RowLayout {
                                Text { text: "检测结果"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                Text { text: root.s.hasResult ? root.s.elapsedMs.toFixed(0) + " ms" : "—"; color: Theme.muted; font.pixelSize: 10 }
                            }
                            RowLayout {
                                spacing: 7
                                Text { text: root.s.hasResult ? root.s.targetCount : "—"; color: Theme.text; font.pixelSize: 31; font.weight: Font.DemiBold }
                                Text { text: "个结冰区域"; color: Theme.secondary; font.pixelSize: 11; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 6 }
                            }
                            Text { visible: !root.s.hasResult || root.s.targetCount === 0; text: root.s.hasResult ? "未检出目标。可降低置信度阈值检查。" : "导入图片后自动开始检测。"; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: 11; lineHeight: 1.45 }
                            Repeater {
                                model: root.boxes
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; implicitHeight: 68; radius: 9
                                    color: root.s.selectedBox === modelData.id ? Theme.accentFill : resultMouse.containsMouse ? Theme.field : "transparent"
                                    border.color: root.s.selectedBox === modelData.id ? Theme.accent : Theme.border
                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: 10; spacing: 7
                                        RowLayout {
                                            Text { text: String(index + 1).padStart(2, "0"); color: Theme.muted; font.pixelSize: 10 }
                                            Rectangle { width: 6; height: 6; radius: 2; color: Theme.cyan }
                                            Text { text: modelData.class_name; color: Theme.text; font.pixelSize: 12; Layout.fillWidth: true; font.weight: Font.Medium }
                                            Text { text: (modelData.confidence * 100).toFixed(1) + "%"; color: Theme.accent; font.pixelSize: 12; font.weight: Font.DemiBold }
                                        }
                                        Text { text: "x " + modelData.xywh[0].toFixed(0) + "  y " + modelData.xywh[1].toFixed(0) + "   ·   " + modelData.xywh[2].toFixed(0) + " × " + modelData.xywh[3].toFixed(0) + " px"; color: Theme.secondary; font.pixelSize: 10 }
                                    }
                                    MouseArea { id: resultMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: studio.selectBox(modelData.id) }
                                }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.margins: 20; spacing: 9
                            Text { text: "结果导出"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                            StudioButton { Layout.fillWidth: true; text: "保存检测图片"; symbol: "download"; primary: true; enabled: root.s.hasResult && !root.s.exporting; onClicked: studio.exportCurrent("annotated") }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                StudioButton { Layout.fillWidth: true; text: "原图副本"; enabled: root.s.hasImage && !root.s.exporting; onClicked: studio.exportCurrent("original") }
                                StudioButton { Layout.fillWidth: true; text: "JSON"; enabled: root.s.hasResult && !root.s.exporting; onClicked: studio.exportCurrent("json") }
                            }
                            StudioButton { Layout.fillWidth: true; text: root.s.exporting ? "正在导出…" : "批量导出全部结果"; enabled: studio.library.count > 0 && !root.s.busy && !root.s.exporting; onClicked: studio.exportAll() }
                            CheckBox {
                                objectName: "reducedMotionCheck"
                                text: "减少动效"; checked: root.s.reducedMotion
                                onToggled: studio.setReducedMotion(checked)
                                font.pixelSize: 10; palette.windowText: Theme.muted; Layout.topMargin: 4
                                hoverEnabled: true
                                ToolTip.visible: hovered
                                ToolTip.text: "关闭流彩背景与玻璃效果，恢复静态界面。"
                                ToolTip.delay: 600
                            }
                        }
                    }
                }
            }
        }
        GlassSurface {
            Layout.fillWidth: true; Layout.preferredHeight: root.s.notice.length ? Math.max(42, noticeText.implicitHeight + 20) : 0
            visible: root.s.notice.length > 0
            tint: root.s.noticeKind === "error" ? (Theme.dark ? "#382b2d" : "#fff0ef") : root.s.noticeKind === "warning" ? (Theme.dark ? "#363022" : "#fff8e9") : Theme.panel
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 12; spacing: 10
                Rectangle { width: 6; height: 6; radius: 3; color: root.s.noticeKind === "error" ? Theme.error : root.s.noticeKind === "warning" ? Theme.warning : root.s.noticeKind === "success" ? Theme.success : Theme.accent }
                Text { id: noticeText; Layout.fillWidth: true; text: root.s.notice; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; font.pixelSize: 11; color: root.s.noticeKind === "error" ? Theme.error : Theme.secondary }
                StudioButton { symbol: "close"; quiet: true; hint: "收起通知"; onClicked: studio.dismissNotice() }
            }
        }
    }
    DropArea {
        id: drop; anchors.fill: parent
        onDropped: function(event) { if (event.hasUrls) { studio.dropUrls(event.urls); event.acceptProposedAction() } }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 8; radius: 16; z: 10
        visible: drop.containsDrag; color: Theme.dark ? "#e0202e40" : "#edecf5ff"; border.color: Theme.accent; border.width: 2
        Column { anchors.centerIn: parent; spacing: 18; Icon { name: "plus"; width: 40; height: 40; ink: Theme.accent; anchors.horizontalCenter: parent.horizontalCenter } Text { text: "松开以导入图片"; color: Theme.accent; font.pixelSize: 24; font.weight: Font.DemiBold } }
    }
}
