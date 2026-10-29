import QtQuick

Image {
    id: icon
    property string name: "image"
    property color ink: Theme.secondary
    width: 18; height: 18
    sourceSize: Qt.size(width * 2, height * 2)
    property var paths: ({
        "plus": "<path d='M12 5v14M5 12h14'/>",
        "image": "<rect x='3' y='3' width='18' height='18' rx='4'/><circle cx='8' cy='8' r='1.5'/><path d='m3 17 5-5 4 4 4-6 5 7'/>",
        "folder": "<path d='M3 7a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v10H3z'/>",
        "play": "<path d='m8 5 11 7-11 7z'/>",
        "batch": "<rect x='7' y='7' width='14' height='14' rx='3'/><path d='M17 3H6a3 3 0 0 0-3 3v11M12 11l5 3-5 3z'/>",
        "fit": "<path d='M9 3H3v6M15 3h6v6M3 15v6h6M15 21h6v-6M8 8h8v8H8z'/>",
        "actual": "<path d='M7 7v10M5 9l2-2M14 7h3v10M12 17h7'/>",
        "eye": "<path d='M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z'/><circle cx='12' cy='12' r='3'/>",
        "download": "<path d='M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5'/>",
        "trash": "<path d='M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7'/>",
        "sun": "<circle cx='12' cy='12' r='4'/><path d='M12 1v2m0 18v2M1 12h2m18 0h2M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2'/>",
        "moon": "<path d='M20 15A9 9 0 0 1 9 4a9 9 0 1 0 11 11z'/>",
        "chevron": "<path d='m7 10 5 5 5-5'/>",
        "close": "<path d='m6 6 12 12M6 18 18 6'/>",
        "help": "<circle cx='12' cy='12' r='9'/><path d='M9.5 9a2.5 2.5 0 1 1 4.3 1.7c-1 .8-1.8 1-1.8 2.8M12 17h.01'/>",
        "shield": "<path d='m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6z'/><path d='m8 12 3 3 5-6'/>",
        "snow": "<path d='M12 2v20M3.3 7l17.4 10M3.3 17 20.7 7M9 4l3 3 3-3M9 20l3-3 3 3M3.5 10 7 9l-1-3.5M20.5 14 17 15l1 3.5M3.5 14 7 15l-1 3.5M20.5 10 17 9l1-3.5'/>",
        "sliders": "<path d='M4 7h16M4 17h16'/><circle cx='9' cy='7' r='3'/><circle cx='16' cy='17' r='3'/>",
        "minus": "<path d='M5 12h14'/>"
    })
    source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='" + ink + "' stroke-width='1.65' stroke-linecap='round' stroke-linejoin='round'>" + (paths[name] || paths.image) + "</svg>")
}
