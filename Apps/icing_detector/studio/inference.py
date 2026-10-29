"""Single model instance, owned exclusively by the inference worker thread."""
from __future__ import annotations

import time
from pathlib import Path

from .domain import sha256
from .imaging import read_image


class Detector:
    def __init__(self, config: dict):
        self.config = config
        self.model = None
        self.load_count = 0
        self.inference_count = 0

    def load(self) -> dict:
        if self.model is not None:
            return self.metadata()
        path = Path(self.config["model_path"])
        if not path.is_file():
            raise FileNotFoundError(f"找不到模型：{path}；请检查 config.json")
        digest = sha256(path)
        if self.config.get("expected_sha256") and digest != self.config["expected_sha256"].lower():
            raise ValueError("模型校验值不匹配；请确认权重，并更新 config.json 的 expected_sha256")
        import torch
        import ultralytics
        from ultralytics import YOLO

        if ultralytics.__version__ != self.config["ultralytics_version"]:
            raise RuntimeError(f'需要 Ultralytics {self.config["ultralytics_version"]}，当前为 {ultralytics.__version__}；请运行安装依赖脚本')

        self.torch = torch
        self.devices = [{"id": "cpu", "label": "CPU"}]
        self.warning = ""
        if not torch.cuda.is_available():
            # A CUDA-visible driver alone doesn't prove the installed torch can use it.
            import subprocess
            try:
                driver = subprocess.run(["nvidia-smi", "-L"], capture_output=True, timeout=4,
                                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                if driver.returncode == 0 and b"GPU" in driver.stdout:
                    self.warning = "检测到 NVIDIA 显卡，但当前 PyTorch 无法使用 CUDA，已回退 CPU。可运行安装依赖脚本启用 GPU。"
            except (OSError, subprocess.SubprocessError):
                pass
        if torch.cuda.is_available():
            for index in range(torch.cuda.device_count()):
                try:
                    torch.zeros(1, device=f"cuda:{index}")
                    self.devices.append({"id": f"cuda:{index}",
                                         "label": f"GPU ({torch.cuda.get_device_name(index)})"})
                except Exception as exc:
                    self.warning = f"GPU 不可用，已使用 CPU：{exc}"
        self.device = self.devices[1]["id"] if len(self.devices) > 1 else "cpu"
        model = YOLO(str(path), task="detect")
        if model.task != "detect":
            raise ValueError(f"模型任务为 {model.task}，当前软件只接受 detect 权重")
        names = {int(key): str(value) for key, value in model.names.items()}
        if len(names) != 1 or next(iter(names.values())).casefold() != "icing":
            raise ValueError(f"预期单类 Icing，实际类别为 {names}；请核对权重")
        self.end_to_end = bool(getattr(model.model, "end2end", False))
        self.classes = names
        self.digest = digest
        self.model = model
        self.load_count += 1
        try:
            self.switch_device(self.device)
        except Exception as exc:
            self.switch_device("cpu")
            self.warning = f"GPU 初始化失败，已回退 CPU：{exc}"
        return self.metadata()

    def metadata(self) -> dict:
        return {"name": self.config["model_name"], "sha256": self.digest,
                "classes": self.classes, "end_to_end": self.end_to_end,
                "device": self.device, "devices": self.devices, "warning": self.warning,
                "model_loads": self.load_count}

    def switch_device(self, device: str) -> dict:
        if device not in [item["id"] for item in self.devices]:
            raise ValueError("所选计算设备不可用")
        self.model.to(device)
        self.model.predictor = None
        self.device = device
        return self.metadata()

    def predict(self, path: str, iou: float) -> dict:
        import numpy as np

        image = read_image(path)
        image_digest = sha256(path)
        start = time.perf_counter()
        warning = ""
        kwargs = dict(imgsz=self.config["input_size"], conf=0.0, iou=iou,
                      max_det=self.config["max_detections"], verbose=False, save=False,
                      augment=False, rect=True, half=False)
        # ndarray avoids ASCII-only OpenCV file APIs, RGB -> BGR preserves color.
        bgr = np.asarray(image)[:, :, ::-1].copy()
        try:
            result = self.model.predict(bgr, device=self.device, **kwargs)[0]
        except (RuntimeError, AssertionError) as exc:
            if not self.device.startswith("cuda"):
                raise
            self.switch_device("cpu")
            self.torch.cuda.empty_cache()
            warning = f"GPU 推理失败，已回退 CPU：{exc}"
            result = self.model.predict(bgr, device="cpu", **kwargs)[0]
        self.inference_count += 1
        boxes = []
        width, height = image.size
        for index, row in enumerate(result.boxes.data.detach().cpu().tolist()):
            x1, y1, x2, y2, confidence, class_id = row[:6]
            x1, x2 = max(0.0, min(width, x1)), max(0.0, min(width, x2))
            y1, y2 = max(0.0, min(height, y1)), max(0.0, min(height, y2))
            if x2 <= x1 or y2 <= y1:
                continue
            boxes.append({"id": index, "class_id": int(class_id),
                          "class_name": self.classes[int(class_id)], "confidence": confidence,
                          "xyxy": [x1, y1, x2, y2], "xywh": [x1, y1, x2 - x1, y2 - y1]})
        return {"detections": boxes, "width": width, "height": height,
                "elapsed_ms": round((time.perf_counter() - start) * 1000, 2),
                "device": self.device, "classes": self.classes,
                "model_sha256": self.digest, "image_sha256": image_digest,
                "input_size": self.config["input_size"], "iou": iou,
                "end_to_end": self.end_to_end, "max_detections": self.config["max_detections"],
                "warning": warning, "inference_count": self.inference_count}
