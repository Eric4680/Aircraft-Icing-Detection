r"""Real-weight integration / renderer checks. No simulated model outputs.

Usage: .venv\Scripts\python.exe tests\verify_app.py --image <photo> --extra <wide-photo>
The Qt offscreen software renderer makes reproducible captures without touching the desktop.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import sys
import time
import faulthandler

APP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(APP))
if "--native" not in sys.argv:
    os.environ["QT_QPA_PLATFORM"] = "offscreen"
    os.environ["QT_QUICK_BACKEND"] = "software"
os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"
os.environ["QT_QPA_FONTDIR"] = "C:/Windows/Fonts"
os.environ["YOLO_OFFLINE"] = "true"
os.environ["YOLO_AUTOINSTALL"] = "false"
os.environ["YOLO_CONFIG_DIR"] = str(APP / ".runtime" / "ultralytics")

from PySide6.QtCore import QObject, QPoint, QPointF, QUrl, QTimer, QMimeData, qInstallMessageHandler, Qt
from PySide6.QtGui import QImage
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication
from PIL import Image, ImageChops

from studio.controller import StudioController
from studio.domain import load_config, result_document, visible_detections
from studio.imaging import read_image, render_annotations
from studio.workers import ImageProvider
from studio.ambient import WaterImageProvider


def main():
    faulthandler.dump_traceback_later(20)
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--extra", required=True)
    parser.add_argument("--native", action="store_true")
    args = parser.parse_args()
    out = APP / ".runtime" / "verification"
    if args.native:
        out = out / "native"
    elif os.getenv("QT_SCALE_FACTOR"):
        out = out / "hidpi"
    out.mkdir(parents=True, exist_ok=True)
    warnings = []
    qInstallMessageHandler(lambda kind, context, message: warnings.append(message))
    app = QApplication([])
    saved_clipboard = None
    if args.native:
        saved_clipboard = QMimeData()
        clipboard_mime = app.clipboard().mimeData()
        if clipboard_mime:
            for mime_format in clipboard_mime.formats():
                saved_clipboard.setData(mime_format, clipboard_mime.data(mime_format))
    app.setFont(__import__("PySide6.QtGui", fromlist=["QFont"]).QFont("Microsoft YaHei UI", 9))
    config = load_config()
    provider = ImageProvider()
    controller = StudioController(config, provider)
    original_theme = controller.state["theme"]
    original_motion = controller.state["reducedMotion"]
    engine = QQmlApplicationEngine()
    engine.addImageProvider("ambient", WaterImageProvider())
    engine.addImageProvider("media", provider)
    engine.rootContext().setContextProperty("studio", controller)
    engine.load(QUrl.fromLocalFile(str(APP / "qml" / "Main.qml")))
    report = {"checks": [], "images": [], "qt_warnings": warnings}
    import socket
    network_calls = []
    original_connect = socket.socket.connect
    def deny_network(sock, address):
        network_calls.append(str(address))
        raise OSError("Network deliberately unavailable in offline verification")
    socket.socket.connect = deny_network
    ticks = []
    heartbeat = QTimer()
    heartbeat.setInterval(25)
    heartbeat.timeout.connect(lambda: ticks.append(time.perf_counter()))
    heartbeat.start()

    def wait_for(predicate, reason, timeout=45):
        deadline = time.monotonic() + timeout
        while not predicate():
            if time.monotonic() >= deadline:
                raise AssertionError(f"Timeout: {reason}; {controller.state}")
            app.processEvents()
            time.sleep(0.01)  # Release the GIL so Python worker imports can progress.

    def check(condition, name):
        if not condition:
            raise AssertionError(name)
        report["checks"].append(name)
        print("PASS", name, flush=True)

    def capture(name):
        QTest.qWait(220)
        shot = window.grabWindow()
        check(not shot.isNull(), "QML rendered: " + name)
        shot.save(str(out / name))

    try:
        check(bool(engine.rootObjects()), "Native QML workspace loads")
        window = engine.rootObjects()[0]
        if args.native:
            window.showNormal()
            window.raise_()
            window.requestActivate()
        report["renderer"] = "native Windows" if args.native else "Qt offscreen software"
        report["device_pixel_ratio"] = window.devicePixelRatio()
        window.resize(1460, 940)
        viewport = window.findChild(QObject, "imageViewport")
        check(viewport is not None, "Interactive image viewport exists")
        wait_for(lambda: controller.state["ready"] or not controller.state["loading"], "model initialization")
        check(controller.state["ready"], "User weights load successfully")
        check(controller.state["endToEnd"], "YOLO26 end-to-end mode preserved")
        check(controller.state["modelLoads"] == 1, "One model load")
        for device in controller.state["devices"]:
            if device["id"].startswith("cuda:"):
                index = int(device["id"].split(":")[1])
                name = controller._model_worker.detector.torch.cuda.get_device_name(index)
                check(device["label"] == f"GPU ({name})", "GPU label uses the actual detected hardware name")
        controller.setTheme("light")
        capture("empty_light.png")
        # Keep hover tests independent of the live desktop cursor; native tests
        # below still exercise rendering, buttons, sliders and actual inference.
        if not args.native:
            for control_name in ("confidenceControl", "iouControl", "opacityControl"):
                help_button = window.findChild(QObject, control_name + "_help")
                tooltip = window.findChild(QObject, control_name + "_tooltip")
                point = help_button.mapToScene(QPointF(help_button.width() / 2, help_button.height() / 2)).toPoint()
                QTest.mouseMove(window, point)
                wait_for(lambda: tooltip.property("opened"), control_name + " hover help", timeout=3)
                check(tooltip.property("opened"), "Hover explanation works: " + control_name)
                if control_name == "iouControl":
                    check(not window.findChild(QObject, "iouControl_slider").property("enabled"), "Disabled IoU retains working help")
                    capture("parameter_help.png")
                QTest.mouseMove(window, QPoint(500, 100))
                wait_for(lambda: not tooltip.property("visible"), control_name + " help dismiss", timeout=3)
        report["hover_help_verified"] = not args.native
        invalid = out / "corrupt.png"
        invalid.write_bytes(b"invalid image")
        controller.add_paths([args.image, args.extra, str(invalid)])
        wait_for(lambda: not controller.state["importing"], "image import")
        wait_for(lambda: controller.state["hasResult"] and not controller.state["busy"] and controller.state["preview"], "first real prediction")
        check(controller.library.count == 2, "Corrupt image rejected; valid images retained")
        first = controller._entry()
        first_result = controller._valid_result(first)
        check(controller.state["targetCount"] > 0, "Real photo returns Icing detections at 25%")
        check(set(first_result["classes"].values()) == {"Icing"}, "Actual single class is Icing")
        before = controller._model_worker.detector.inference_count
        baseline = copy.deepcopy(controller.detections)
        slider = window.findChild(QObject, "confidenceControl_slider")
        click_point = slider.mapToScene(QPointF(slider.width() * 0.95, slider.height() / 2)).toPoint()
        QTest.mouseClick(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, click_point)
        app.processEvents()
        check(controller.state["confidence"] > 0.9 and controller.state["targetCount"] == 0,
              "Actual QML confidence slider controls real visible results")
        controller.setConfidence(0.25)
        label_combo = window.findChild(QObject, "labelCombo")
        combo_point = label_combo.mapToScene(QPointF(label_combo.width() / 2, label_combo.height() / 2)).toPoint()
        QTest.mouseClick(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, combo_point)
        QTest.qWait(100)
        QTest.keyClick(window, Qt.Key.Key_Down)
        QTest.keyClick(window, Qt.Key.Key_Return)
        app.processEvents()
        check(controller.state["labelMode"] == 1, "Actual QML label dropdown selection applies")
        controller.setLabelMode(0)
        controller.setConfidence(1)
        check(len(controller.detections) == 0, "100% confidence removes predictions")
        controller.setConfidence(0)
        check(len(controller.detections) >= len(baseline), "0% confidence displays cached candidates")
        controller.setConfidence(0.25)
        controller.setOpacity(0.43)
        controller.setLabelMode(2)
        controller.setShowBoxes(False)
        controller.setShowBoxes(True)
        controller.setOpacity(0.75)
        controller.setLabelMode(0)
        QTest.qWait(50)
        check(before == controller._model_worker.detector.inference_count, "Confidence/opacity/labels/view changes reuse cached prediction")
        controller.setIou(0.1)
        check(controller.state["iou"] == 0.5 and before == controller._model_worker.detector.inference_count,
              "Inapplicable IoU cannot pretend to change inference")
        controller.selectBox(baseline[0]["id"])
        check(controller.state["selectedBox"] == baseline[0]["id"], "Result selection highlights matching detection")
        controller.selectBox(-1)
        capture("detection_light.png")
        controller.setTheme("dark")
        capture("detection_dark.png")
        controller.setTheme("light")
        window.resize(1080, 720)
        capture("compact_light.png")
        scale = viewport.property("imageScale")
        check(abs((first["width"] * scale) / (first["height"] * scale) - first["width"] / first["height"]) < 1e-9,
              "Viewport preserves source aspect ratio")
        def visual_items(item):
            yield item
            for child in item.childItems():
                yield from visual_items(child)
        box = next((item for item in visual_items(viewport)
                    if item.objectName() == "boxOverlay_" + str(baseline[0]["id"])), None)
        check(box is not None, "Actual overlay instantiated")
        check(abs(box.property("x") - baseline[0]["xyxy"][0] * scale) < 0.01,
              "Actual box x matches original-pixel coordinates after resize")
        center = viewport.mapToScene(QPointF(viewport.width() / 2, viewport.height() / 2)).toPoint()
        QTest.wheelEvent(window, center, QPoint(0, 120))
        QTest.qWait(80)
        check(viewport.property("imageScale") > scale, "Real wheel input zooms image")
        initial_pan = viewport.property("panX")
        QTest.mousePress(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, center)
        QTest.mouseMove(window, center + QPoint(45, 30), delay=30)
        QTest.mouseRelease(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, center + QPoint(45, 30))
        actual_delta = viewport.property("panX") - initial_pan
        check(abs(actual_delta - 45) < 2, f"Real pointer drag pans image one-to-one (delta={actual_delta:.2f})")
        scale = viewport.property("imageScale")
        check(abs(box.property("x") - baseline[0]["xyxy"][0] * scale) < 0.01,
              "Overlay stays aligned after interactive zoom/pan")
        if args.native:
            actual_button = viewport.findChild(QObject, "actualPixelsButton")
            point = actual_button.mapToScene(QPointF(actual_button.width() / 2, actual_button.height() / 2)).toPoint()
            QTest.mouseClick(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, point)
        else:
            QTest.keyClick(window, Qt.Key.Key_1, Qt.KeyboardModifier.ControlModifier)
        QTest.qWait(50)
        check(abs(viewport.property("percent") - 100) < 0.01, "Actual pixel view honors device pixel ratio")
        if args.native:
            fit_button = viewport.findChild(QObject, "fitButton")
            point = fit_button.mapToScene(QPointF(fit_button.width() / 2, fit_button.height() / 2)).toPoint()
            QTest.mouseClick(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, point)
        else:
            QTest.keyClick(window, Qt.Key.Key_0, Qt.KeyboardModifier.ControlModifier)
        QTest.qWait(50)
        check(viewport.property("fitMode"), "Fit-to-window shortcut restores automatic layout")
        window.resize(1460, 940)
        controller.selectImage(1)
        wait_for(lambda: controller.state["hasResult"] and not controller.state["busy"] and controller.state["preview"], "second image inference")
        check(controller.state["imageWidth"] != controller.state["imageHeight"], "Real non-square image loaded")
        second_id = controller._entry()["id"]
        before_switch = controller._model_worker.detector.inference_count
        controller.selectImage(0)
        wait_for(lambda: bool(controller.state["preview"]), "cached image preview")
        check(controller._model_worker.detector.inference_count == before_switch, "Returning to previous image reuses its cache")
        for entry in controller.library.entries:
            result = controller._valid_result(entry)
            check(result is not None, "Batch record contains real result: " + entry["name"])
            for detection in result["detections"]:
                x1, y1, x2, y2 = detection["xyxy"]
                assert 0 <= x1 < x2 <= entry["width"] and 0 <= y1 < y2 <= entry["height"]
            report["images"].append({"name": entry["name"], "width": entry["width"], "height": entry["height"],
                                     "targets_at_25": len(visible_detections(result, 0.25)),
                                     "elapsed_ms": result["elapsed_ms"], "device": result["device"]})
        check(True, "All real predictions bounded by each original image")
        settings = controller._visual_settings()
        source = read_image(first["path"])
        no_boxes = render_annotations(source, baseline, {**settings, "opacity": 0})
        check(ImageChops.difference(source, no_boxes).getbbox() is None, "0% opacity exports unchanged pixels")
        hidden = render_annotations(source, baseline, {**settings, "show_boxes": False})
        check(ImageChops.difference(source, hidden).getbbox() is None, "Original view exports no boxes")
        for mode, target in (("annotated", "single.jpg"), ("original", "original.png"), ("json", "single.json")):
            controller._start_export([copy.deepcopy(first)], str(out / target), mode)
            wait_for(lambda: not controller.state["exporting"], "single export " + mode)
            check((out / target).is_file(), "Single export completed: " + mode)
        check(ImageChops.difference(read_image(out / "original.png"), source).getbbox() is None,
              "Original PNG copy preserves decoded source pixels")
        controller._start_export(copy.deepcopy(controller.library.entries), str(out), "batch")
        wait_for(lambda: not controller.state["exporting"], "actual batch PNG/JSON export")
        json_files = [file for file in out.glob("*.json") if file.name != "report.json"]
        check(len(json_files) >= 2, "Batch JSON and annotated/original images written")
        for file in json_files:
            document = json.loads(file.read_text(encoding="utf-8"))
            if "detections" in document:
                check(all(box["confidence"] >= settings["confidence"] for box in document["detections"]), "JSON honors visible confidence")
                check(document["thresholds"]["iou"] is None, "JSON marks end-to-end IoU as inapplicable")
        detector = controller._model_worker.detector
        report["device_options"] = detector.devices
        report["model_sha256"] = detector.digest
        report["model_loads"] = detector.load_count
        report["end_to_end"] = detector.end_to_end
        if len(detector.devices) > 1:
            auto_device = controller.state["device"]
            controller.setDevice(0)
            wait_for(lambda: not controller.state["loading"] and not controller.state["busy"] and controller.state["hasResult"], "CPU switch and actual inference")
            check(controller.state["resultDevice"] == "cpu", "Manual CPU switch performs real inference")
            controller.setDevice(1)
            wait_for(lambda: not controller.state["loading"] and not controller.state["busy"] and controller.state["hasResult"], "GPU switch and actual inference")
            check(controller.state["resultDevice"].startswith("cuda"), "Manual GPU switch performs real inference")
            check(detector.load_count == 1, "CPU/GPU changes keep same model instance")
            original_predict = detector.model.predict
            failure_injected = [False]
            def predict_with_one_gpu_failure(*args, **kwargs):
                if not failure_injected[0] and str(kwargs.get("device", "")).startswith("cuda"):
                    failure_injected[0] = True
                    raise RuntimeError("Injected GPU error for fallback verification")
                return original_predict(*args, **kwargs)
            detector.model.predict = predict_with_one_gpu_failure
            controller.detectCurrent()
            wait_for(lambda: not controller.state["busy"], "real CPU fallback after injected GPU exception")
            detector.model.predict = original_predict
            check(failure_injected[0] and controller.state["resultDevice"] == "cpu",
                  "GPU exception falls back to real CPU inference")
            check(controller.state["noticeKind"] == "warning", "GPU fallback is explained inline")
            controller.setDevice(1)
            wait_for(lambda: not controller.state["loading"] and not controller.state["busy"] and controller.state["hasResult"], "restore GPU")
        # Clipboard path uses a real image; offscreen clipboard doesn't alter the Windows clipboard.
        app.clipboard().setImage(QImage(args.image))
        controller.pasteImage()
        wait_for(lambda: not controller.state["importing"], "clipboard import")
        check(controller.library.count == 3, "Clipboard image imports successfully")
        # Paths dropped by QML are QUrl objects, not strings.
        controller.dropUrls([QUrl.fromLocalFile(args.image)])
        check(controller.library.count == 3, "Drop URL decoding works and duplicate source is skipped")
        controller.selectImage(2)
        controller.removeCurrent()
        wait_for(lambda: not controller.state["busy"], "removed image job drained")
        check(controller.library.count == 2 and Path(args.image).is_file(), "Remove cancels work and preserves original file")
        controller.setConfidence(0.25)
        controller.selectImage(1)
        wait_for(lambda: bool(controller.state["preview"]), "wide preview")
        capture("wide_image.png")
        report["heartbeat_ticks"] = len(ticks)
        report["heartbeat_max_gap_ms"] = round(max((b - a for a, b in zip(ticks, ticks[1:])), default=0) * 1000, 1)
        check(len(ticks) > 20, "GUI event loop continues while model/file workers run")
        important = [message for message in warnings if any(term in message for term in ("ReferenceError", "TypeError", "Binding loop", "failed to load", "Cannot assign", "Required property"))]
        check(not important, "No QML binding/type/runtime errors")
        controller.clearImages()
        check(controller.library.count == 0 and not controller.state["hasImage"], "Clear removes session entries only")
        rotated = out / "oriented.jpg"
        photo = read_image(args.extra)
        exif = photo.getexif()
        exif[274] = 6
        photo.save(rotated, exif=exif)
        controller.add_paths([str(rotated)])
        wait_for(lambda: not controller.state["importing"] and controller.state["hasResult"] and not controller.state["busy"], "EXIF-oriented photo")
        check(controller.state["imageWidth"] == photo.height and controller.state["imageHeight"] == photo.width,
              "EXIF orientation is applied consistently to metadata and inference")
        controller.clearImages()
        check(not network_calls, "Model/image/export workflow makes no outgoing socket connections")
        report["network_attempts"] = network_calls
        faulthandler.cancel_dump_traceback_later()
        report["status"] = "PASS"
    except Exception as exc:
        report["status"] = "FAIL"
        report["error"] = str(exc)
        raise
    finally:
        socket.socket.connect = original_connect
        if saved_clipboard is not None:
            app.clipboard().setMimeData(saved_clipboard)
        controller.setTheme(original_theme)
        controller.setReducedMotion(original_motion)
        controller.shutdown()
        (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({key: value for key, value in report.items() if key != "checks"}, ensure_ascii=False, indent=2), flush=True)
        engine.deleteLater()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
