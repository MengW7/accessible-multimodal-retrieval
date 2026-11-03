"""Render a Markdown report to PDF via HTML + headless Chrome.

Mirrors the W01-W04 report PDFs, which were produced by HeadlessChrome (Skia/PDF).
Only used for the weekly report; it does not touch the Markdown source.
"""
from __future__ import annotations

import html
import pathlib
import re
import subprocess
import sys

import markdown

CHROME = pathlib.Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")

CSS = """
@page { size: A4; margin: 16mm 14mm; }
body {
  font-family: "Microsoft YaHei", "Segoe UI", sans-serif;
  font-size: 10.5pt; line-height: 1.6; color: #1a1a1a;
  letter-spacing: 0;
}
h1 { font-size: 19pt; border-bottom: 2px solid #006a64; padding-bottom: 6px; margin: 0 0 14px; }
h2 { font-size: 14pt; margin: 22px 0 8px; color: #00453f; border-bottom: 1px solid #d6e2df; padding-bottom: 4px; }
h3 { font-size: 11.5pt; margin: 16px 0 6px; color: #00453f; }
table { border-collapse: collapse; width: 100%; margin: 10px 0 14px; font-size: 9pt; table-layout: auto; }
th, td { border: 1px solid #b9c7c4; padding: 5px 7px; vertical-align: top; text-align: left; }
th { background: #e8f1ef; font-weight: 600; }
th:first-child, td:first-child { white-space: nowrap; }
tr { page-break-inside: avoid; }
thead { display: table-header-group; }
code { background: #f2f5f4; padding: 1px 4px; border-radius: 3px; font-family: Consolas, monospace; font-size: 9pt; }
pre { background: #f6f8f7; border: 1px solid #dde5e3; border-radius: 4px; padding: 9px; overflow-x: auto; }
pre code { background: none; padding: 0; font-size: 8.5pt; }
blockquote { border-left: 3px solid #006a64; margin: 10px 0; padding: 2px 12px; color: #3f4947; background: #f6faf9; }
a { color: #006a64; text-decoration: none; word-break: break-all; }
ul, ol { margin: 6px 0 10px; padding-left: 22px; }
li { margin: 3px 0; }
hr { border: none; border-top: 1px solid #d6e2df; margin: 18px 0; }
img { max-width: 100%; }
"""


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: md_to_pdf.py SOURCE.md OUTPUT.html OUTPUT.pdf", file=sys.stderr)
        return 64
    src = pathlib.Path(sys.argv[1]).resolve()
    html_out = pathlib.Path(sys.argv[2]).resolve()
    pdf_out = pathlib.Path(sys.argv[3]).resolve()

    text = src.read_text(encoding="utf-8")
    body = markdown.markdown(
        text,
        extensions=["tables", "fenced_code", "sane_lists", "toc", "attr_list"],
    )

    # Relative links and images resolve against the Markdown file's directory.
    base = src.parent.as_uri() + "/"
    doc = (
        "<!DOCTYPE html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\">"
        f"<base href=\"{html.escape(base)}\">"
        f"<title>{html.escape(src.stem)}</title><style>{CSS}</style></head>"
        f"<body>{body}</body></html>"
    )
    html_out.write_text(doc, encoding="utf-8")

    chrome = CHROME if CHROME.exists() else pathlib.Path(
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    )
    cmd = [
        str(chrome),
        "--headless",
        "--disable-gpu",
        "--no-sandbox",
        "--no-pdf-header-footer",
        f"--print-to-pdf={pdf_out}",
        html_out.as_uri(),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if not pdf_out.exists():
        print(proc.stdout[-2000:], file=sys.stderr)
        print(proc.stderr[-2000:], file=sys.stderr)
        return 1
    print(f"wrote {pdf_out} ({pdf_out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
