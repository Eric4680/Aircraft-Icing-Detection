"""Startup and installer dependency checks; does not change installed packages."""
from __future__ import annotations

import argparse
from importlib import metadata, util
import os
from pathlib import Path
import struct
import sys


def check_environment(quick=False, cuda=False):
    if sys.version_info[:2] != (3, 12) or struct.calcsize('P') != 8:
        raise RuntimeError('需要 64 位 Python 3.12')
    from packaging.requirements import Requirement
    app_dir = Path(__file__).resolve().parents[1]
    for line in (app_dir / 'requirements.txt').read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        requirement = Requirement(line)
        if metadata.version(requirement.name) not in requirement.specifier:
            raise RuntimeError(f'依赖版本不匹配：{requirement}')
    for name in ('torch', 'ultralytics', 'PySide6', 'PIL', 'cv2', 'numpy'):
        if util.find_spec(name) is None:
            raise RuntimeError(f'缺少依赖：{name}')
    if quick:
        return
    os.environ.setdefault('YOLO_CONFIG_DIR', str(app_dir / '.runtime' / 'ultralytics'))
    Path(os.environ['YOLO_CONFIG_DIR']).mkdir(parents=True, exist_ok=True)
    os.environ['YOLO_OFFLINE'] = 'true'
    os.environ['YOLO_AUTOINSTALL'] = 'false'
    import torch
    from PySide6 import QtQuick, QtWidgets
    from PIL import Image
    import cv2
    import numpy
    from ultralytics import YOLO
    torch.zeros(1)
    if cuda:
        if not torch.cuda.is_available():
            raise RuntimeError('CUDA 不可用')
        torch.zeros(1, device='cuda:0')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--quick', action='store_true')
    parser.add_argument('--cuda', action='store_true')
    options = parser.parse_args()
    try:
        check_environment(options.quick, options.cuda)
        print('Environment OK')
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
