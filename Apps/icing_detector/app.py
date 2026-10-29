"""Native Windows entry point. Run with this module's local .venv."""
from __future__ import annotations

import argparse
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import sys

APP_DIR = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent
RESOURCE_DIR = Path(getattr(sys, "_MEIPASS", APP_DIR))
RUNTIME = APP_DIR / ".runtime"
RUNTIME.mkdir(exist_ok=True)
os.environ.setdefault("YOLO_CONFIG_DIR", str(RUNTIME / "ultralytics"))
os.environ["YOLO_AUTOINSTALL"] = "false"
os.environ["YOLO_OFFLINE"] = "true"
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")


def configure_logging():
    handler = RotatingFileHandler(RUNTIME / "studio.log", maxBytes=2_000_000, backupCount=3, encoding="utf-8")
    logging.basicConfig(level=logging.INFO, handlers=[handler], format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    if sys.stdout:
        stream = logging.StreamHandler(sys.stdout)
        stream.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
        logging.getLogger().addHandler(stream)
    def error_hook(kind, value, trace):
        logging.getLogger("studio").critical("Unhandled exception", exc_info=(kind, value, trace))
    sys.excepthook = error_hook


def main():
    parser = argparse.ArgumentParser(description="Aircraft Icing Detection Studio")
    parser.add_argument("images", nargs="*")
    parser.add_argument("--smoke", action="store_true", help="Check the actual model without opening the GUI")
    args = parser.parse_args()
    configure_logging()
    from studio.domain import load_config
    config = load_config()
    if args.smoke:
        import json
        from studio.inference import Detector
        detector = Detector(config)
        print(json.dumps(detector.load(), ensure_ascii=False, indent=2))
        for image in args.images:
            result = detector.predict(image, config["iou"])
            from studio.domain import visible_detections
            print(json.dumps({"image": image, "candidate_count": len(result["detections"]),
                              **{key: value for key, value in result.items() if key != "detections"},
                              "detections": visible_detections(result, config["confidence"])},
                             ensure_ascii=False, indent=2))
        return 0

    from PySide6.QtCore import QUrl, QTimer, qInstallMessageHandler
    from PySide6.QtGui import QFont, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtWidgets import QApplication
    from studio.controller import StudioController
    from studio.workers import ImageProvider

    qInstallMessageHandler(lambda kind, context, message: logging.getLogger("qt").warning(message))
    application = QApplication(sys.argv[:1])
    application.setApplicationName("Aircraft Icing Detection Studio")
    application.setOrganizationName("Aircraft Icing")
    application.setApplicationVersion("1.0.0")
    application.setFont(QFont("Microsoft YaHei UI", 9))
    application.setWindowIcon(QIcon(str(RESOURCE_DIR / "assets" / "studio.svg")))
    provider = ImageProvider()
    controller = StudioController(config, provider)
    engine = QQmlApplicationEngine()
    engine.addImageProvider("media", provider)
    engine.rootContext().setContextProperty("studio", controller)
    engine.load(QUrl.fromLocalFile(str(RESOURCE_DIR / "qml" / "Main.qml")))
    if not engine.rootObjects():
        controller.shutdown()
        return 1
    window = engine.rootObjects()[0]
    available = window.screen().availableGeometry()
    window.setWidth(min(window.width(), max(window.minimumWidth(), available.width() - 48)))
    window.setHeight(min(window.height(), max(window.minimumHeight(), available.height() - 64)))
    window.setX(available.x() + max(0, (available.width() - window.width()) // 2))
    window.setY(available.y() + max(0, (available.height() - window.height()) // 2))
    if args.images:
        QTimer.singleShot(0, lambda: controller.add_paths(args.images))
    result = application.exec()
    controller.shutdown()
    engine.deleteLater()
    return result


if __name__ == "__main__":
    raise SystemExit(main())
