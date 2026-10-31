"""Native shader/material regression, with real model inference and retained water.

Run with the app's Python. --software exercises the static-renderer fallback.
Artifacts overwrite .runtime/verification/background; user preferences are restored.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time

APP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(APP))
parser = argparse.ArgumentParser()
parser.add_argument('--image')
parser.add_argument('--software', action='store_true')
args = parser.parse_args()
os.environ['QT_QUICK_CONTROLS_STYLE'] = 'Basic'
os.environ['QT_QPA_FONTDIR'] = 'C:/Windows/Fonts'
os.environ['YOLO_OFFLINE'] = 'true'
os.environ['YOLO_AUTOINSTALL'] = 'false'
os.environ['YOLO_CONFIG_DIR'] = str(APP / '.runtime' / 'ultralytics')
if args.software:
    os.environ['QT_QUICK_BACKEND'] = 'software'
    os.environ['QT_QPA_PLATFORM'] = 'offscreen'

from PySide6.QtCore import QObject, QPoint, QUrl, qInstallMessageHandler
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication
from studio.ambient import WaterField, WaterImageProvider
from studio.controller import StudioController
from studio.domain import load_config
from studio.workers import ImageProvider


def main():
    warnings = []
    qInstallMessageHandler(lambda kind, context, message: warnings.append(message))
    app = QApplication([])
    provider = ImageProvider()
    controller = StudioController(load_config(), provider)
    saved = controller.state.copy()
    controller.setTheme('light')
    controller.setReducedMotion(False)
    engine = QQmlApplicationEngine()
    engine.addImageProvider('ambient', WaterImageProvider())
    engine.addImageProvider('media', provider)
    engine.rootContext().setContextProperty('studio', controller)
    out = APP / '.runtime' / 'verification' / 'background'
    out.mkdir(parents=True, exist_ok=True)
    report = {'checks': [], 'warnings': warnings, 'renderer': 'software' if args.software else 'native'}

    def pump(seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            app.processEvents()
            time.sleep(.005)

    def wait(predicate, label, timeout=50):
        deadline = time.monotonic() + timeout
        while not predicate():
            if time.monotonic() > deadline:
                raise AssertionError(label)
            pump(.02)

    def check(condition, label):
        assert condition, label
        report['checks'].append(label)
        print('PASS', label, flush=True)

    def capture(name):
        image = window.grabWindow()
        check(not image.isNull(), 'Rendered ' + name)
        image.save(str(out / name))
        return image

    try:
        engine.load(QUrl.fromLocalFile(str(APP / 'qml' / 'Main.qml')))
        check(bool(engine.rootObjects()), 'Real workspace opens')
        window = engine.rootObjects()[0]
        report['device_pixel_ratio'] = window.devicePixelRatio()
        available = window.screen().availableGeometry()
        window.setWidth(min(1460, available.width()-48))
        window.setHeight(min(940, available.height()-64))
        loader = window.findChild(QObject, 'liquidBackgroundLoader')
        pump(1)
        if args.software:
            check(loader.property('item') is None, 'Software renderer uses static fallback')
            capture('software.png')
        else:
            wait(lambda: loader.property('item') is not None and loader.property('item').property('shaderReady'), 'Pigment shader compiles')
            background = loader.property('item')
            before = background.property('elapsed')
            first = capture('liquid_light.png')
            pump(1.2)
            second = window.grabWindow()
            check(background.property('elapsed') > before+.5, 'Background clock advances')
            check(first != second, 'Native shader produces changing pixels')
            field = window.findChild(QObject, 'ambientWaterField')
            QTest.mouseMove(window, QPoint(int(window.width()*.4), int(window.height()*.6)))
            pump(.2)
            check(field.property('pointerInside') and abs(field.property('pointerX')-.4) < .02,
                  'Workspace hover reaches background without consuming input')
            field.setProperty('pointerInside', True)
            field.setProperty('pointerX', .4)
            field.setProperty('pointerY', .6)
            pump(.9)
            check(field.property('activity') > .5 and field._vortex.max() > .2, 'Stationary hover builds retained water')
            field.setProperty('pointerInside', False)
            old = field._vortex.copy()
            pump(.6)
            check(field.property('activity') > .5 and (old != field._vortex).any(), 'Trail continues after pointer leaves')
            capture('liquid_trail.png')
            window.showMinimized()
            pump(.2)
            paused = background.property('elapsed')
            pump(.3)
            check(background.property('elapsed') == paused and not field.property('running'), 'Minimized window stops both animation solvers')
            window.showNormal()
            pump(.4)
            check(background.property('elapsed') > paused, 'Restored window resumes')
            controller.setTheme('dark')
            pump(.4)
            capture('liquid_dark.png')
            controller.setTheme('light')
            # Use the actual UI checkbox, rather than calling the preference setter.
            toggle = window.findChild(QObject, 'reducedMotionCheck')
            toggle.setProperty('checked', True)
            toggle.toggled.emit()
            pump(.4)
            check(controller.state['reducedMotion'] and loader.property('item') is None, 'Reduced motion unloads shaders, textures and water timer')
            static = capture('static_light.png')
            pump(.3)
            # Model status can finish loading asynchronously; test the empty canvas.
            sample = static.pixelColor(int(static.width()*.50), int(static.height()*.27))
            check(sample.name() == '#e7ebf0', 'Reduced motion restores exact original canvas color')
            toggle.setProperty('checked', False)
            toggle.toggled.emit()
            wait(lambda: loader.property('item') is not None and loader.property('item').property('shaderReady'), 'Restored shader ready')
            pump(.4)
            check(not controller.state['reducedMotion'], 'Checkbox restores liquid background')
            restored = window.grabWindow()
            pump(.5)
            check(restored != window.grabWindow(), 'Background pixels keep moving after disable/enable')
            window.setWidth(1024)
            window.setHeight(700)
            pump(.3)
            capture('liquid_compact.png')

        wait(lambda: controller.state['ready'], 'Real model ready')
        if args.image:
            controller.add_paths([args.image])
            wait(lambda: controller.state['hasResult'] and bool(controller.state['preview']) and not controller.state['busy'], 'Real photo inference completes')
            pump(.4)
            check(controller.state['targetCount'] > 0, 'Real Icing detection remains functional')
            result = controller.detections
            report['capture_motion_reduced'] = controller.state['reducedMotion']
            if not args.software:
                check(loader.property('item') is not None and loader.property('item').property('shaderReady'), 'Liquid shader remains rendered during inference')
            capture('liquid_detection.png' if not args.software else 'software_detection.png')
            controller.setReducedMotion(True)
            pump(.3)
            check(controller.detections == result, 'Background switch preserves detection output')
            report['targets'] = controller.state['targetCount']
        # CPU work has a fixed footprint and sleeps after the trail expires.
        field = WaterField()
        field._inside = True
        durations = []
        for _ in range(30):
            start = time.perf_counter()
            field._step(1/30)
            field._pack()
            durations.append((time.perf_counter()-start)*1000)
        field._inside = False
        for _ in range(335):
            field._step(1/30)
            if not field._active:
                break
        check(not field._active and field._envelope == 0, 'Water field fully releases retained trail')
        report['water_step_mean_ms'] = round(sum(durations)/len(durations), 3)
        report['water_step_max_ms'] = round(max(durations), 3)
        bad = [w for w in warnings if any(x in w.lower() for x in ('error', 'failed', 'cannot', 'binding loop', 'not defined', 'not supported', 'not assigned'))]
        check(not bad, 'No QML or shader runtime errors: ' + str(bad))
        report['status'] = 'PASS'
    except Exception as exc:
        report['status'] = 'FAIL'
        report['error'] = str(exc)
        raise
    finally:
        controller.setTheme(saved['theme'])
        controller.setReducedMotion(saved['reducedMotion'])
        controller.shutdown()
        engine.deleteLater()
        (out / ('software_report.json' if args.software else 'report.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)


if __name__ == '__main__':
    main()
