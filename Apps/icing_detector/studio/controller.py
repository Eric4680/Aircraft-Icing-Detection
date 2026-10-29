"""GUI-thread coordinator. Queued signals are the only route to background owners."""
from __future__ import annotations

import copy
from pathlib import Path
import threading
import uuid

from PySide6.QtCore import QObject, Property, QSettings, QThread, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import QFileDialog

from .domain import APP_DIR, SUPPORTED_EXTENSIONS, visible_detections
from .library import LibraryModel
from .workers import FileWorker, ImageProvider, ModelWorker, PreviewWorker


class StudioController(QObject):
    changed = Signal()
    detectionsChanged = Signal()
    viewReset = Signal()
    initializeModel = Signal()
    changeDevice = Signal(str)
    predictImage = Signal(str, str, int, float)
    importFiles = Signal(list)
    requestPreview = Signal(str, str)
    saveClipboard = Signal(object, str)
    exportFiles = Signal(list, str, str, dict, dict)

    def __init__(self, config: dict, provider: ImageProvider, parent=None):
        super().__init__(parent)
        self.config = config
        self.provider = provider
        self._library = LibraryModel(self)
        self._current = -1
        self._generation = 0
        self._pending = set()
        self._paths = set()
        self._cancelled = set()
        self._cancel_lock = threading.Lock()
        self._stopping = threading.Event()
        self._preview_lock = threading.Lock()
        self._wanted_preview = {"id": ""}
        self._preview_url = ""
        self._preview_revision = 0
        self._selected_box = -1
        self._ready = False
        self._loading = True
        self._importing = False
        self._exporting = False
        self._metadata = {"device": "", "devices": [], "end_to_end": True}
        self._notice = "正在初始化本地模型…"
        self._notice_kind = "info"
        self.preferences = QSettings(str(APP_DIR / ".runtime" / "settings.ini"), QSettings.Format.IniFormat)
        self._theme = str(self.preferences.value("theme", "light"))
        self._reduced_motion = self.preferences.value("reduced_motion", False, type=bool)
        self._confidence = config["confidence"]
        self._iou = config["iou"]
        self._opacity = 0.75
        self._label_mode = 0
        self._show_boxes = True
        self._threads = []
        self._model_worker = ModelWorker(config, self._cancelled, self._cancel_lock)
        self._file_worker = FileWorker(self._stopping)
        self._preview_worker = PreviewWorker(self._wanted_preview, self._preview_lock)
        for worker, name in ((self._model_worker, "IcingInference"), (self._file_worker, "IcingFiles"), (self._preview_worker, "IcingPreview")):
            thread = QThread(self)
            thread.setObjectName(name)
            worker.moveToThread(thread)
            thread.finished.connect(worker.deleteLater)
            thread.start()
            self._threads.append(thread)
        self.initializeModel.connect(self._model_worker.initialize)
        self.changeDevice.connect(self._model_worker.switch_device)
        self.predictImage.connect(self._model_worker.predict)
        self._model_worker.ready.connect(self._on_ready)
        self._model_worker.result.connect(self._on_result)
        self._model_worker.failed.connect(self._on_inference_error)
        self._model_worker.cancelled.connect(self._on_cancelled)
        self.importFiles.connect(self._file_worker.import_paths)
        self.requestPreview.connect(self._preview_worker.preview)
        self.saveClipboard.connect(self._file_worker.save_clipboard)
        self.exportFiles.connect(self._file_worker.export)
        self._file_worker.imported.connect(self._on_imported)
        self._file_worker.importFinished.connect(self._on_import_finished)
        self._preview_worker.previewReady.connect(self._on_preview)
        self._preview_worker.error.connect(lambda error: self._message(error, "error"))
        self._file_worker.error.connect(lambda error: self._message(error, "error"))
        self._file_worker.exported.connect(self._on_exported)
        QTimer.singleShot(0, self.initializeModel.emit)

    @Property(QObject, constant=True)
    def library(self):
        return self._library

    def _entry(self):
        return self._library.entries[self._current] if 0 <= self._current < self._library.count else None

    def _find(self, image_id):
        return next((entry for entry in self._library.entries if entry["id"] == image_id), None)

    def _valid_result(self, entry):
        if entry and entry.get("generation") == self._generation:
            return entry.get("result")
        return None

    @Property("QVariantList", notify=detectionsChanged)
    def detections(self):
        return visible_detections(self._valid_result(self._entry()), self._confidence)

    @Property("QVariantMap", notify=changed)
    def state(self):
        entry = self._entry()
        result = self._valid_result(entry)
        device_label = next((item["label"] for item in self._metadata["devices"]
                             if item["id"] == self._metadata["device"]), "初始化中")
        return {
            "ready": self._ready, "loading": self._loading, "busy": bool(self._pending),
            "pendingCount": len(self._pending), "importing": self._importing,
            "exporting": self._exporting, "currentIndex": self._current,
            "modelName": self.config["model_name"], "device": self._metadata["device"],
            "deviceLabel": device_label, "devices": self._metadata["devices"],
            "endToEnd": self._metadata["end_to_end"], "confidence": self._confidence,
            "iou": self._iou, "opacity": self._opacity, "labelMode": self._label_mode,
            "showBoxes": self._show_boxes, "selectedBox": self._selected_box,
            "theme": self._theme, "reducedMotion": self._reduced_motion,
            "notice": self._notice, "noticeKind": self._notice_kind,
            "preview": self._preview_url, "hasImage": bool(entry),
            "imageName": entry["name"] if entry else "图像工作区",
            "imageWidth": entry["width"] if entry else 0,
            "imageHeight": entry["height"] if entry else 0,
            "imageStatus": entry["status"] if entry else "尚未导入图片",
            "hasResult": result is not None, "targetCount": len(self.detections),
            "elapsedMs": result["elapsed_ms"] if result else 0,
            "resultDevice": result["device"] if result else "",
            "modelLoads": self._metadata.get("model_loads", 0),
        }

    def _message(self, text, kind="info"):
        self._notice, self._notice_kind = text, kind
        self.changed.emit()

    @Slot()
    def dismissNotice(self):
        self._notice = ""
        self.changed.emit()

    @Slot()
    def retryModel(self):
        if not self._loading:
            self._loading = True
            self._message("正在重新初始化模型…")
            self.initializeModel.emit()

    @Slot(dict)
    def _on_ready(self, metadata):
        self._metadata = metadata
        self._loading = False
        self._ready = True
        self._message(metadata.get("warning") or "模型已就绪 · 本机离线推理", "warning" if metadata.get("warning") else "success")
        self._queue(self._entry())

    @Slot()
    def openImages(self):
        paths, _ = QFileDialog.getOpenFileNames(None, "导入飞机覆冰图片", "", "图片 (*.jpg *.jpeg *.png *.bmp *.webp *.tif *.tiff)")
        self.add_paths(paths)

    @Slot("QVariantList")
    def dropUrls(self, urls):
        self.add_paths([(url if isinstance(url, QUrl) else QUrl(str(url))).toLocalFile() for url in urls])

    def add_paths(self, paths):
        if self._importing:
            self._message("正在导入图片，请稍候再添加", "info")
            return
        records = []
        rejected = 0
        for raw in paths:
            path = Path(raw).resolve()
            if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS:
                key = str(path).casefold()
                if key not in self._paths:
                    self._paths.add(key)
                    records.append({"id": uuid.uuid4().hex, "path": str(path), "name": path.name})
            else:
                rejected += 1
        if records:
            self._importing = True
            self._message(f"正在读取 {len(records)} 张图片…")
            self.importFiles.emit(records)
        elif paths:
            self._message("没有可添加的新图片；支持 JPG、PNG、BMP、WebP、TIFF", "warning")

    @Slot()
    def pasteImage(self):
        if self._importing:
            self._message("正在导入图片，请稍候再粘贴")
            return
        clipboard = QGuiApplication.clipboard()
        mime = clipboard.mimeData()
        if mime.hasUrls():
            self.add_paths([url.toLocalFile() for url in mime.urls() if url.isLocalFile()])
        elif mime.hasImage():
            image = clipboard.image()
            if image.isNull():
                self._message("剪贴板中没有可读取的图片", "warning")
                return
            path = APP_DIR / ".runtime" / "clipboard" / f"{uuid.uuid4().hex}.png"
            path.parent.mkdir(parents=True, exist_ok=True)
            self._importing = True
            self.saveClipboard.emit(image.copy(), str(path))
            self._message("正在读取剪贴板图片…")
        else:
            self._message("剪贴板中没有图片或图片文件", "warning")

    @Slot(dict, object)
    def _on_imported(self, entry, thumbnail):
        with self._cancel_lock:
            if entry["id"] in self._cancelled:
                return
        self.provider.put(entry["id"], thumbnail)
        entry.update(imageId=entry["id"], thumbnail=f'image://media/{entry["id"]}', status="待检测", error="", result=None, generation=-1)
        self._library.append(entry)
        if self._current == -1:
            self.selectImage(0)
        self.changed.emit()

    @Slot(int, int)
    def _on_import_finished(self, good, bad):
        self._importing = False
        self._paths = {entry["path"].casefold() for entry in self._library.entries}
        if bad:
            self._message(f"已导入 {good} 张，{bad} 张读取失败；详情见 Apps/icing_detector/.runtime/studio.log", "warning")
        else:
            self._message(f"已导入 {good} 张图片", "success")

    @Slot(int)
    def selectImage(self, index):
        if not 0 <= index < self._library.count:
            return
        if index == self._current:
            return
        self._current = index
        self._selected_box = -1
        self._preview_url = ""
        entry = self._entry()
        with self._preview_lock:
            self._wanted_preview["id"] = entry["id"]
        self.viewReset.emit()
        self.requestPreview.emit(entry["id"], entry["path"])
        self.detectionsChanged.emit()
        self.changed.emit()
        self._queue(entry)

    @Slot(str, object)
    def _on_preview(self, image_id, image):
        entry = self._entry()
        if entry and image_id == entry["id"]:
            self.provider.put("preview", image)
            self._preview_revision += 1
            self._preview_url = f"image://media/preview?{self._preview_revision}"
            self.changed.emit()

    def _queue(self, entry, force=False):
        if not entry or not self._ready or self._loading:
            return
        key = (entry["id"], self._generation)
        if key in self._pending or (self._valid_result(entry) is not None and not force):
            return
        entry["status"], entry["error"] = "正在检测…", ""
        self._library.changed(entry)
        self._pending.add(key)
        self.predictImage.emit(entry["id"], entry["path"], self._generation, self._iou)
        self.changed.emit()

    @Slot()
    def detectCurrent(self):
        self._queue(self._entry(), force=True)

    @Slot()
    def detectAll(self):
        for entry in self._library.entries:
            self._queue(entry)
        self._message(f"批量检测已排队 · {len(self._pending)} 张")

    @Slot(str, int, dict)
    def _on_result(self, image_id, generation, result):
        self._pending.discard((image_id, generation))
        entry = self._find(image_id)
        if entry and generation == self._generation:
            entry.update(result=result, generation=generation, width=result["width"], height=result["height"])
            count = len(visible_detections(result, self._confidence))
            entry["status"] = f"{count} 个目标" if count else "未检出"
            self._library.changed(entry)
            self._metadata["device"] = result["device"]
            self.detectionsChanged.emit()
            if result.get("warning"):
                self._message(result["warning"], "warning")
            elif entry is self._entry():
                self._selected_box = -1
                self._message(f"检测完成 · {count} 个目标" if count else "未检测到结冰区域 · 可调整阈值检查", "success" if count else "info")
        self.changed.emit()

    @Slot(str, int)
    def _on_cancelled(self, image_id, generation):
        self._pending.discard((image_id, generation))
        self.changed.emit()

    @Slot(str, int, str)
    def _on_inference_error(self, image_id, generation, error):
        self._pending.discard((image_id, generation))
        if not image_id:
            self._loading = False
            if generation == -1:
                self._ready = False
        else:
            entry = self._find(image_id)
            if entry and generation == self._generation:
                entry.update(status="检测失败", error=error)
                self._library.changed(entry)
        self._message(f"模型加载失败：{error}" if generation == -1 else f"操作失败：{error}", "error")

    @Slot(float)
    def setConfidence(self, value):
        self._confidence = max(0, min(1, value))
        self._selected_box = -1
        for entry in self._library.entries:
            result = self._valid_result(entry)
            if result is not None and (entry["id"], self._generation) not in self._pending:
                count = len(visible_detections(result, self._confidence))
                entry["status"] = f"{count} 个目标" if count else "未检出"
                self._library.changed(entry)
        self.detectionsChanged.emit()
        self.changed.emit()

    def _invalidate(self):
        self._generation += 1
        self._selected_box = -1
        for entry in self._library.entries:
            entry.update(result=None, generation=-1, status="待检测", error="")
            self._library.changed(entry)
        self.detectionsChanged.emit()

    @Slot(float)
    def setIou(self, value):
        if self._metadata["end_to_end"]:
            return
        value = max(0, min(1, value))
        if value != self._iou:
            self._iou = value
            self._invalidate()
            self.changed.emit()
            self._queue(self._entry())

    @Slot(float)
    def setOpacity(self, value):
        self._opacity = max(0, min(1, value))
        self.changed.emit()

    @Slot(int)
    def setLabelMode(self, value):
        self._label_mode = max(0, min(4, value))
        self.changed.emit()

    @Slot(bool)
    def setShowBoxes(self, value):
        self._show_boxes = value
        self.changed.emit()

    @Slot(int)
    def selectBox(self, box_id):
        self._selected_box = box_id
        self.changed.emit()

    @Slot(int)
    def setDevice(self, index):
        if self._pending or self._loading or not self._ready:
            return
        if 0 <= index < len(self._metadata["devices"]):
            device = self._metadata["devices"][index]["id"]
            if device != self._metadata["device"]:
                self._invalidate()
                self._loading = True
                self.changeDevice.emit(device)
                self._message("正在切换计算设备…")

    @Slot(str)
    def setTheme(self, theme):
        self._theme = theme if theme in ("light", "dark") else "light"
        self.preferences.setValue("theme", self._theme)
        self.changed.emit()

    @Slot(bool)
    def setReducedMotion(self, value):
        self._reduced_motion = value
        self.preferences.setValue("reduced_motion", value)
        self.changed.emit()

    @Slot()
    def removeCurrent(self):
        entry = self._entry()
        if not entry:
            return
        if self._importing:
            self._message("请等待导入完成后移除图片")
            return
        row = self._current
        with self._cancel_lock:
            self._cancelled.add(entry["id"])
        self._paths.discard(entry["path"].casefold())
        self.provider.remove(entry["id"])
        self._library.remove(row)
        self._current = -1
        self._preview_url = ""
        if self._library.count:
            self.selectImage(min(row, self._library.count - 1))
        self.detectionsChanged.emit()
        self.changed.emit()

    @Slot()
    def clearImages(self):
        if self._importing:
            self._message("请等待导入完成后清空列表")
            return
        while self._library.count:
            entry = self._library.entries[-1]
            with self._cancel_lock:
                self._cancelled.add(entry["id"])
            self.provider.remove(entry["id"])
            self._library.remove(self._library.count - 1)
        self.provider.remove("preview")
        self._paths.clear()
        self._current = -1
        self._preview_url = ""
        with self._preview_lock:
            self._wanted_preview["id"] = ""
        self.detectionsChanged.emit()
        self._message("图片列表已清空；原文件保留")

    def _visual_settings(self):
        return dict(confidence=self._confidence, opacity=self._opacity, label_mode=self._label_mode,
                    show_boxes=self._show_boxes)

    @Slot(str)
    def exportCurrent(self, mode):
        entry = self._entry()
        if not entry or self._exporting or mode not in ("original", "annotated", "json"):
            return
        result = self._valid_result(entry)
        if mode != "original" and result is None:
            self._message("请先完成当前图片的检测", "warning")
            return
        stem = Path(entry["name"]).stem
        extension = ".json" if mode == "json" else ".png"
        filters = "JSON (*.json)" if mode == "json" else "PNG (*.png);;JPEG (*.jpg)"
        path, selected_filter = QFileDialog.getSaveFileName(None, "导出当前图片", stem + "_" + mode + extension, filters)
        if not path:
            return
        if not Path(path).suffix:
            path += ".json" if mode == "json" else (".jpg" if "JPEG" in selected_filter else ".png")
        if Path(path).resolve() == Path(entry["path"]).resolve():
            self._message("不能覆盖原图，请另选文件名", "error")
            return
        snapshot = copy.deepcopy(entry)
        snapshot["result"] = result
        self._start_export([snapshot], path, mode)

    @Slot()
    def exportAll(self):
        if self._exporting:
            return
        entries = self._library.entries
        if not entries or any(self._valid_result(entry) is None for entry in entries):
            self._message("请先完成全部图片的检测，再批量导出", "warning")
            return
        directory = QFileDialog.getExistingDirectory(None, "选择批量导出位置")
        if directory:
            # A unique session directory avoids overwriting previous exports.
            from datetime import datetime
            path = Path(directory) / (datetime.now().strftime("Icing_%Y%m%d_%H%M%S_") + uuid.uuid4().hex[:6])
            path.mkdir()
            self._start_export(copy.deepcopy(entries), str(path), "batch")

    def _start_export(self, entries, path, mode):
        self._exporting = True
        self.exportFiles.emit(entries, path, mode, self._visual_settings(), self.config)
        self._message("正在导出结果…")

    @Slot(str, int, int)
    def _on_exported(self, path, good, bad):
        self._exporting = False
        self._message(f"已导出 {good} 张 · {path}" if not bad else f"已导出 {good} 张，失败 {bad} 张；详情见日志", "success" if not bad else "warning")

    def can_close(self):
        if self._exporting:
            self._message("正在写入导出文件，请完成后再关闭", "warning")
            return False
        return True

    @Slot(result=bool)
    def requestClose(self):
        return self.can_close()

    def shutdown(self):
        self._stopping.set()
        with self._preview_lock:
            self._wanted_preview["id"] = ""
        with self._cancel_lock:
            self._cancelled.update(entry["id"] for entry in self._library.entries)
        for thread in self._threads:
            thread.quit()
        # Never terminate a running PyTorch operation or destroy its QThread.
        for thread in self._threads:
            thread.wait()
