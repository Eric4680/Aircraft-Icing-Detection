"""Small serializable contracts shared by inference, UI and exports."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

APP_DIR = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parents[1]
SUPPORTED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}


def load_config() -> dict:
    config = json.loads((APP_DIR / "config.json").read_text(encoding="utf-8-sig"))
    config["model_path"] = str((APP_DIR / config["model_path"]).resolve())
    if config["input_size"] % 32:
        raise ValueError("input_size 必须是 32 的倍数")
    return config


def sha256(path: str | Path) -> str:
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def visible_detections(result: dict | None, confidence: float) -> list[dict]:
    if result is None:
        return []
    return [box for box in result["detections"] if box["confidence"] >= confidence]


def label_text(box: dict, mode: int) -> str:
    if mode == 0:
        return f'{box["class_name"]} {box["confidence"]:.0%}'
    if mode == 1:
        return box["class_name"]
    if mode == 2:
        return f'{box["confidence"]:.0%}'
    return ""


def result_document(entry: dict, result: dict, settings: dict, config: dict) -> dict:
    return {
        "schema_version": 1,
        "image": {"name": entry["name"], "width": entry["width"], "height": entry["height"],
                  "sha256": result["image_sha256"], "orientation": "EXIF-transposed"},
        "model": {"name": config["model_name"], "task": "detect",
                  "sha256": result["model_sha256"], "classes": result["classes"]},
        "inference": {key: result[key] for key in
                      ("device", "elapsed_ms", "input_size", "end_to_end", "max_detections")},
        "thresholds": {"confidence": settings["confidence"],
                       "iou": None if result["end_to_end"] else result["iou"],
                       "candidate_confidence_floor": 0.0},
        "visualization": {key: settings[key] for key in ("opacity", "label_mode", "show_boxes")},
        "coordinate_system": "xyxy / xywh, original EXIF-oriented image pixels",
        "detections": visible_detections(result, settings["confidence"]),
        "notes": "未检出不等于确认无冰。结果为模型预测，未经人工质量验收。",
    }
