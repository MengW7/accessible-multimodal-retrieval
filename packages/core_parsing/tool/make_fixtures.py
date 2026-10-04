"""Regenerate the binary and text fixtures used by core_parsing's unit tests.

Why a generator instead of committing an opaque blob: every fixture in
``test/fixtures/`` is either text or a few hundred bytes, and its exact byte
layout is part of the test contract (encoding cases, corrupted inputs, files
the scanner must skip). Regenerating is cheap and keeps the intent reviewable.

The real sample documents are **not** copied here: the integration tests read
``datasets/samples/`` directly, which keeps this folder small.

Usage::

    python tool/make_fixtures.py

Note: Python is not a build dependency of the Dart package. This script only
produces fixtures; it is never executed by ``dart test`` or by the application.
"""

from __future__ import annotations

import codecs
import zipfile
from pathlib import Path

FIXTURES = Path(__file__).resolve().parent.parent / "test" / "fixtures"

# GBK bytes for 中文测试 - hard-coded on purpose: the fixture must stay byte
# stable even on a machine without a GBK codec installed.
GBK_ZHONG_WEN_CE_SHI = bytes([0xD6, 0xD0, 0xCE, 0xC4, 0xB2, 0xE2, 0xCA, 0xD4])

DOCX_CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>
"""

DOCX_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>
"""

# Three paragraphs, one of them split across several <w:r> runs: the parser must
# join runs inside a paragraph and separate paragraphs.
DOCX_DOCUMENT = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Hello DOCX fixture.</w:t></w:r></w:p>
    <w:p><w:r><w:t>Second paragraph with </w:t></w:r><w:r><w:t>split runs</w:t></w:r><w:r><w:t>.</w:t></w:r></w:p>
    <w:p><w:r><w:t>中文段落测试</w:t></w:r></w:p>
    <w:sectPr/>
  </w:body>
</w:document>
"""

DOCX_CORE_PROPERTIES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Core Parsing Fixture</dc:title>
  <dc:creator>Week 2</dc:creator>
  <dcterms:created xsi:type="dcterms:W3CDTF">2026-09-27T00:00:00Z</dcterms:created>
</cp:coreProperties>
"""

# A PDF whose declared stream length deliberately exceeds the bytes present:
# parsers must degrade to partial/failed instead of crashing.
TRUNCATED_PDF = (
    b"%PDF-1.4\n"
    b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
    b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
    b"3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n"
    b"4 0 obj\n<< /Length 9999 >>\nstream\nBT /F1 12 Tf (truncated) Tj ET\n"
)


def _write_text(name: str, text: str, *, encoding: str = "utf-8",
                newline: str | None = None) -> None:
    data = text.encode(encoding)
    if newline is not None:
        data = data.replace(b"\n", newline.encode("ascii"))
    (FIXTURES / name).write_bytes(data)


def make_docx() -> None:
    """Write a minimal but structurally valid OOXML package."""
    with zipfile.ZipFile(FIXTURES / "docx_minimal.docx", "w",
                         compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", DOCX_CONTENT_TYPES)
        archive.writestr("_rels/.rels", DOCX_RELS)
        archive.writestr("word/document.xml", DOCX_DOCUMENT)
        archive.writestr("docProps/core.xml", DOCX_CORE_PROPERTIES)


def make_png() -> None:
    """Write a real 8x8 RGB PNG (Pillow is available in the bundled runtime)."""
    from PIL import Image

    Image.new("RGB", (8, 8), (200, 30, 30)).save(FIXTURES / "tiny.png")


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    (FIXTURES / "nested").mkdir(exist_ok=True)

    # --- text encodings -----------------------------------------------------
    _write_text("hello.txt", "Hello core_parsing.\n第二行：中文内容。\n",
                newline="\r\n")
    _write_text("hello_utf8_bom.txt", "BOM prefixed ASCII and 中文。\n",
                encoding="utf-8-sig")
    (FIXTURES / "hello_gbk.txt").write_bytes(
        b"GBK: " + GBK_ZHONG_WEN_CE_SHI + b"\n")
    (FIXTURES / "hello_utf16le.txt").write_bytes(
        codecs.BOM_UTF16_LE + "UTF-16LE 中文\n".encode("utf-16-le"))
    _write_text("UPPER.TXT", "extension case must not matter\n")
    (FIXTURES / "empty.txt").write_bytes(b"")
    _write_text("nested/a.txt", "nested fixture\n")

    # --- files the scanner must skip ---------------------------------------
    _write_text(".hidden.txt", "hidden file\n")
    (FIXTURES / "~$temp.docx").write_bytes(b"office lock file placeholder\n")

    # --- corrupted / degenerate inputs -------------------------------------
    (FIXTURES / "zero.pdf").write_bytes(b"")
    (FIXTURES / "truncated.pdf").write_bytes(TRUNCATED_PDF)
    (FIXTURES / "corrupt.docx").write_bytes(b"this is not a zip container\n")
    (FIXTURES / "fake.png").write_bytes(b"this is not a png\n")

    make_docx()
    make_png()

    total = 0
    for path in sorted(FIXTURES.rglob("*")):
        if path.is_file():
            total += path.stat().st_size
            print(f"{path.relative_to(FIXTURES)!s:>28}  {path.stat().st_size:>7} B")
    print(f"total fixture size: {total} B (budget: < 204800 B)")


if __name__ == "__main__":
    main()
