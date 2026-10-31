import QtQuick

Rectangle {
    id: surface
    property color tint: Theme.panel
    property real materialWeight: 0.72
    color: Theme.glassEnabled ? "transparent" : tint

    Loader {
        anchors.fill: parent
        active: Theme.glassEnabled && Theme.backdrop !== null
        sourceComponent: ShaderEffect {
            // All panes sample the same background in window coordinates.
            property var backdrop: Theme.backdrop
            property vector4d sampleRect: {
                if (!Theme.backdrop) return Qt.vector4d(0, 0, 1, 1)
                let p = surface.mapToItem(Theme.backdrop, 0, 0)
                return Qt.vector4d(p.x / Theme.backdrop.width, p.y / Theme.backdrop.height,
                                  surface.width / Theme.backdrop.width, surface.height / Theme.backdrop.height)
            }
            property size paneSize: Qt.size(surface.width, surface.height)
            property size backdropSize: Theme.backdrop ? Qt.size(Theme.backdrop.width, Theme.backdrop.height) : Qt.size(1, 1)
            property color glassTint: surface.tint
            property real weight: surface.materialWeight
            property real cornerRadius: surface.radius
            fragmentShader: "shaders/glass.frag.qsb"
        }
    }
}
