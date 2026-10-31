pragma Singleton
import QtQuick

QtObject {
    property bool dark: false
    property bool reducedMotion: false
    property var backdrop: null
    property bool glassEnabled: false
    readonly property color background: dark ? "#171a20" : "#f5f6f8"
    readonly property color panel: dark ? "#20242b" : "#ffffff"
    readonly property color sidebar: dark ? "#1c2027" : "#edf0f4"
    readonly property color canvas: dark ? "#12151a" : "#e7ebf0"
    readonly property color field: dark ? "#2a3039" : "#f2f4f7"
    readonly property color text: dark ? "#f0f2f6" : "#202835"
    readonly property color secondary: dark ? "#adb7c7" : "#647085"
    readonly property color muted: dark ? "#8793a7" : "#778398"
    readonly property color border: dark ? "#353c48" : "#dce1e9"
    readonly property color accent: dark ? "#60b1ff" : "#1477e5"
    readonly property color accentFill: dark ? "#223d59" : "#e2efff"
    readonly property color cyan: "#23a6d5"
    readonly property color success: dark ? "#69ccac" : "#218569"
    readonly property color error: dark ? "#ffaaa6" : "#b84843"
    readonly property color warning: dark ? "#efcd86" : "#95631d"
    readonly property int motion: reducedMotion ? 0 : 140
}
