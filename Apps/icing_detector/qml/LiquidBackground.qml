import QtQuick
import Icing.Ambient 1.0

Item {
    id: background
    objectName: "liquidBackground"
    property bool animating: true
    property bool pointerInside: false
    property point pointerPosition: Qt.point(0.5, 0.5)
    readonly property bool shaderReady: pigment.status !== ShaderEffect.Error
    property alias texture: capture
    // Fixed visual settings. No workspace controls are exposed for decoration.
    readonly property real flowPeriod: 72
    readonly property real orbitPeriod: 600
    property real elapsed: 0

    ShaderEffect {
        id: pigment
        objectName: "pigmentShader"
        width: background.width; height: background.height
        property size resolution: Qt.size(width, height)
        property real phase: (background.elapsed / background.flowPeriod) % 1
        property real rotationPhase: (background.elapsed / background.orbitPeriod) % 1
        property real circulation: 0.76
        property real motion: 0.67
        property real blend: 0.55
        property real detail: 0.60
        property real relief: 0.33
        property real saturation: 1.00
        property real stir: 0.85
        property real radius: 0.60
        property real activity: water.activity
        property real envelope: water.envelope
        property real gentle: 1.0
        property var waterField: waterTexture
        property vector4d fieldMapping: Qt.vector4d(.45 / (water.aspect + .9), .45 / 1.9, water.aspect / (water.aspect + .9), 1 / 1.9)
        property size fieldTexel: Qt.size((water.aspect + .9) / (288 * water.aspect), 1.9 / 208)
        property real darkMode: Theme.dark ? 1 : 0
        fragmentShader: "shaders/pigment.frag.qsb"
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("Pigment shader:", log)
    }
    WaterField {
        id: water
        objectName: "ambientWaterField"
        running: background.animating
        pointerInside: background.pointerInside && background.animating
        pointerPosition: background.pointerPosition
        aspect: background.width / Math.max(1, background.height)
    }
    Image {
        id: waterTexture
        visible: false
        source: water.source
        cache: false
        asynchronous: false
        smooth: true
    }
    ShaderEffectSource {
        id: capture
        anchors.fill: parent
        sourceItem: pigment
        hideSource: true
        // One shared, bounded render target; panels reuse it instead of rerunning fbm.
        textureSize: Qt.size(Math.min(1000, Math.ceil(width)), Math.max(2, Math.ceil(height * Math.min(1, 1000 / Math.max(1, width)))))
        live: true
        smooth: true
    }
    Timer {
        id: clock
        objectName: "backgroundClock"
        interval: 33; repeat: true
        running: background.animating && background.visible
        property double previous: 0
        onRunningChanged: previous = 0
        onTriggered: {
            let now = Date.now()
            if (previous > 0) background.elapsed += Math.min(0.1, (now - previous) / 1000)
            previous = now
        }
    }
}
