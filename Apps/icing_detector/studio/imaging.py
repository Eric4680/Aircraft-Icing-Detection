"""Image decoding and annotation. No Qt GUI or model dependency."""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

from .domain import label_text

# Retain Pillow's decompression-bomb protection; very large input is reported inline.
MAX_PIXELS = 80_000_000
PIL_OPEN = Image.open  # Preserve Pillow's decoder before Ultralytics installs global patches.


def read_image(path: str | Path) -> Image.Image:
    with PIL_OPEN(path) as source:
        if source.width * source.height > MAX_PIXELS:
            raise ValueError("图片超过 8000 万像素，请先缩小后导入")
        return ImageOps.exif_transpose(source).convert("RGB")


def render_annotations(image: Image.Image, detections: list[dict], settings: dict) -> Image.Image:
    """Same RGB color, opacity, label modes and box geometry as the QML overlay."""
    output = image.convert("RGBA")
    if not settings["show_boxes"] or settings["label_mode"] == 4:
        return output.convert("RGB")
    layer = Image.new("RGBA", image.size)
    draw = ImageDraw.Draw(layer)
    # Viewport uses constant screen widths; export scales the treatment to the source.
    unit = max(1.0, max(image.size) / 1400)
    line = max(2, round(2 * unit))
    size = max(13, round(13 * unit))
    font_path = Path("C:/Windows/Fonts/segoeui.ttf")
    font = ImageFont.truetype(str(font_path), size) if font_path.exists() else ImageFont.load_default(size=size)
    alpha = round(255 * settings["opacity"])
    color = (35, 166, 213, alpha)
    for box in detections:
        x1, y1, x2, y2 = box["xyxy"]
        draw.rectangle((x1, y1, x2, y2), outline=color, width=line)
        text = label_text(box, settings["label_mode"])
        if text:
            bounds = draw.textbbox((0, 0), text, font=font)
            text_width = bounds[2] - bounds[0]
            height = size + round(10 * unit)
            width = text_width + round(14 * unit)
            left = max(0, min(x1, image.width - width))
            top = max(0, y1 - height) if y1 >= height else y1
            draw.rounded_rectangle((left, top, left + width, top + height), radius=round(4 * unit), fill=color)
            draw.text((left + 7 * unit, top + 3 * unit), text, font=font, fill=(255, 255, 255, alpha))
    return Image.alpha_composite(output, layer).convert("RGB")
