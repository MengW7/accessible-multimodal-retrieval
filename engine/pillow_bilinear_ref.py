"""Pillow bilinear reference for the Dart image preprocessor fixtures.

Reads a JSON list of {name, width, height, edge} and prints NCHW bytes in
the same order as ImagePreprocessor: shortest edge, Image.BILINEAR, center
crop. Pixel bytes are (x * 17 + y * 29 + channel * 41) & 255. The Dart side
divides by 255 after this crop.
"""

import json
import sys
from pathlib import Path

import PIL
from PIL import Image


def pattern(width: int, height: int) -> bytes:
    raw = bytearray(width * height * 3)
    index = 0
    for y in range(height):
        for x in range(width):
            for channel in range(3):
                raw[index] = (x * 17 + y * 29 + channel * 41) & 255
                index += 1
    return bytes(raw)


def preprocess(width: int, height: int, edge: int) -> list[int]:
    image = Image.frombytes("RGB", (width, height), pattern(width, height))
    short = min(width, height)
    scale = edge / short
    resized = (
        max(edge, round(width * scale)),
        max(edge, round(height * scale)),
    )
    image = image.resize(resized, Image.BILINEAR)
    left = (image.width - edge) // 2
    top = (image.height - edge) // 2
    image = image.crop((left, top, left + edge, top + edge))
    pixels = image.load()
    if pixels is None:
        raise RuntimeError("Pillow did not expose pixels")
    values: list[int] = []
    for channel in range(3):
        for y in range(edge):
            for x in range(edge):
                values.append(int(pixels[x, y][channel]))
    return values


def main() -> None:
    cases = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    payload = {
        "pillow": PIL.__version__,
        "cases": [
            {
                "name": case["name"],
                "pixels": preprocess(case["width"], case["height"], case["edge"]),
            }
            for case in cases
        ],
    }
    json.dump(payload, sys.stdout)


if __name__ == "__main__":
    main()
