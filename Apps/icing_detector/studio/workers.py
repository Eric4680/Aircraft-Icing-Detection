"""Serial background owners for model work and file work; GUI never waits on I/O."""
from __future__ import annotations

import json
import logging
from pathlib import Path
import re
import threading

from PIL import Image
from PySide6.QtCore import QObject, Signal, Slot, QSize
from PySide6.QtGui import QImage
from PySide6.QtQuick import QQuickImageProvider

from .domain import result_document, sha256, visible_detections
from .imaging import read_image, render_annotations
from .inference import Detector

log = logging.getLogger(__name__)


def qt_image(image: Image.Image) -> QImage:
    rgb = image.convert("RGB")
    return QImage(rgb.tobytes(), rgb.width, rgb.height,
                  rgb.width * 3, QImage.Format.Format_RGB888).copy()


class ImageProvider(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Image)
        self._images: dict[str, QImage] = {}
        self._lock = threading.Lock()

    def put(self, key: str, image: QImage):
        with self._lock:
            self._images[key] = image

    def remove(self, key: str):
        with self._lock:
            self._images.pop(key, None)

    def requestImage(self, identifier: str, size: QSize, requestedSize: QSize) -> QImage:
        with self._lock:
            result = self._images.get(identifier.split("?")[0], QImage()).copy()
        size.setWidth(result.width())
        size.setHeight(result.height())
        return result


class ModelWorker(QObject):
    ready = Signal(dict)
    result = Signal(str, int, dict)
    failed = Signal(str, int, str)
    cancelled = Signal(str, int)

    def __init__(self, config: dict, cancelled_ids: set[str], cancel_lock: threading.Lock):
        super().__init__()
        self.detector = Detector(config)
        self.cancelled_ids = cancelled_ids
        self.cancel_lock = cancel_lock

    @Slot()
    def initialize(self):
        log.info("Model worker initialization started")
        try:
            self.ready.emit(self.detector.load())
            log.info("Model worker initialization completed")
        except Exception as exc:
            log.exception("Model initialization failed")
            self.failed.emit("", -1, str(exc))

    @Slot(str)
    def switch_device(self, device: str):
        try:
            self.ready.emit(self.detector.switch_device(device))
        except Exception as exc:
            log.exception("Device switch failed")
            self.failed.emit("", -2, str(exc))

    @Slot(str, str, int, float)
    def predict(self, image_id: str, path: str, generation: int, iou: float):
        with self.cancel_lock:
            cancelled = image_id in self.cancelled_ids
        if cancelled:
            self.cancelled.emit(image_id, generation)
            return
        try:
            self.result.emit(image_id, generation, self.detector.predict(path, iou))
        except Exception as exc:
            log.exception("Inference failed: %s", path)
            self.failed.emit(image_id, generation, str(exc))


class PreviewWorker(QObject):
    previewReady = Signal(str, QImage)
    error = Signal(str)

    def __init__(self, wanted: dict, lock: threading.Lock):
        super().__init__()
        self.wanted, self.lock = wanted, lock

    @Slot(str, str)
    def preview(self, image_id: str, path: str):
        with self.lock:
            if self.wanted.get("id") != image_id:
                return
        try:
            image = read_image(path)
            # Only the selected full-size preview is retained. Obsolete queued
            # requests are skipped when the user rapidly selects other photos.
            with self.lock:
                if self.wanted.get("id") != image_id:
                    return
            self.previewReady.emit(image_id, qt_image(image))
        except Exception as exc:
            self.error.emit(f"预览读取失败：{exc}")


class FileWorker(QObject):
    imported = Signal(dict, QImage)
    importFinished = Signal(int, int)
    error = Signal(str)
    exported = Signal(str, int, int)

    def __init__(self, stopping: threading.Event):
        super().__init__()
        self.stopping = stopping

    @Slot(list)
    def import_paths(self, records: list[dict]):
        good = bad = 0
        for entry in records:
            if self.stopping.is_set():
                break
            try:
                image = read_image(entry["path"])
                entry.update(width=image.width, height=image.height)
                image.thumbnail((192, 144), Image.Resampling.LANCZOS)
                self.imported.emit(entry, qt_image(image))
                good += 1
            except Exception as exc:
                log.exception("Import failed")
                self.error.emit(f'{entry["name"]}：图片读取失败 · {exc}')
                bad += 1
        self.importFinished.emit(good, bad)

    @Slot(object, str)
    def save_clipboard(self, image: QImage, path: str):
        try:
            if image.width() * image.height() > 80_000_000:
                raise ValueError("剪贴板图片超过 8000 万像素")
            if not image.save(path, "PNG"):
                raise OSError("无法保存剪贴板图片")
            self.import_paths([{"id": Path(path).stem, "path": path, "name": "粘贴的图片.png"}])
        except Exception as exc:
            self.error.emit(f"粘贴失败：{exc}")

    @Slot(list, str, str, dict, dict)
    def export(self, entries: list[dict], destination: str, mode: str, settings: dict, config: dict):
        good = bad = 0
        for entry in entries:
            try:
                result = entry.get("result")
                if mode != "batch" and Path(destination).resolve() == Path(entry["path"]).resolve():
                    raise ValueError("不能覆盖导入的原图")
                # Prevent accidental export of stale coordinates after the source changed.
                if result and sha256(entry["path"]) != result["image_sha256"]:
                    raise ValueError("原文件已改变，请移除后重新导入并检测")
                if mode != "original" and not result:
                    raise ValueError("图片尚未完成当前参数的检测")
                if mode == "batch":
                    stem = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", Path(entry["name"]).stem)[:100]
                    prefix = Path(destination) / f'{stem}_{entry["id"][:8]}'
                    original_target = prefix.with_name(prefix.name + "_original.png")
                    image_target = prefix.with_name(prefix.name + "_detected.png")
                    json_target = prefix.with_suffix(".json")
                    image = read_image(entry["path"])
                    image.save(original_target)
                    render_annotations(image, visible_detections(result, settings["confidence"]), settings).save(image_target)
                    json_target.write_text(json.dumps(result_document(entry, result, settings, config),
                                                      indent=2, ensure_ascii=False), encoding="utf-8")
                elif mode == "json":
                    Path(destination).write_text(json.dumps(result_document(entry, result, settings, config),
                                                           indent=2, ensure_ascii=False), encoding="utf-8")
                else:
                    target = Path(destination)
                    if target.resolve() == Path(entry["path"]).resolve():
                        raise ValueError("请另选文件名，不能覆盖导入的原图")
                    image = read_image(entry["path"])
                    if mode == "annotated":
                        image = render_annotations(image, visible_detections(result, settings["confidence"]), settings)
                    image.save(target, quality=95) if target.suffix.lower() in (".jpg", ".jpeg") else image.save(target)
                good += 1
            except Exception as exc:
                bad += 1
                log.exception("Export failed")
                self.error.emit(f'{entry["name"]}：导出失败 · {exc}')
        self.exported.emit(destination, good, bad)
